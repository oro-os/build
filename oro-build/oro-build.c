#include "./ext/lua/onelua.c"
#include "./ext/luafilesystem/src/lfs.c"

#include "./ext/lua/lua.h"
#include "./ext/lua/lualib.h"
#include "./ext/lua/lauxlib.h"
#include "./ext/luafilesystem/src/lfs.h"
#include "./ext/subprocess.h/subprocess.h"
#include "./ext/rapidstring/include/rapidstring.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>

#ifdef _WIN32
#	include <windows.h>
#endif

static int display_traceback(lua_State *L) {
	/* -, +1 */
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	lua_pushvalue(L, 1);
	lua_pushinteger(L, 2);
	lua_call(L, 2, 1);
	return 1;
}

static int read_stream_to_rs(FILE *fd, rapidstring *rs) {
	char buf[4096];
	size_t nread = -1;

	while ((nread = fread(buf, 1, sizeof(buf), fd)) > 0) {
		rs_cat_n(rs, buf, nread);
	}

	return ferror(fd);
}

static void pushenv(lua_State *L) {
	/* -, +1 */
	lua_newtable(L);

#ifdef _WIN32
	LPCH env_p = GetEnvironmentStrings();
#else
	extern char **environ;
	char **env_p = environ;
#endif

	while (*env_p) {
#ifdef _WIN32
		char *var = env_p;
#else
		char *var = *env_p;
#endif
		char *eq = strchr(var, '=');

		if (eq == NULL) {
#ifdef _WIN32
			/* skip (scan until next null) */
			env_p += strlen(env_p) + 1;
#else
			/* skip (go to next pointer) */
			++env_p;
#endif
			continue;
		}

		lua_pushlstring(L, var, eq - var);
		var += eq - var + 1;
		size_t len = strlen(var);
		lua_pushlstring(L, var, len);
		lua_rawset(L, -3);

#ifdef _WIN32
		env_p += (var + len + 1) - env_p;
#else
		++env_p;
#endif
	}
}

static int execute_process(lua_State *L) {
	/* -, +3, ERR */
	int success = 0;
	int status_code = -1;
	int should_throw = 1;
	int nargs;
	int r;
	const char **command_line;
	struct subprocess_s subprocess;
	FILE *fd;

	luaL_checktype(L, 1, LUA_TTABLE);
	nargs = luaL_len(L, 1);
	luaL_argcheck(L, nargs > 0, 1, "argument list cannot be empty");

	if (lua_getfield(L, 1, "raise") != LUA_TNIL) {
		should_throw = lua_toboolean(L, -1);
	}
	lua_pop(L, 1);

	rapidstring sout;
	rapidstring serr;
	rs_init(&sout);
	rs_init(&serr);

	command_line = malloc(sizeof(const char *) * (nargs + 1));
	if (command_line == NULL) {
		lua_pushliteral(L, "failed to allocate memory (execute_process)");
		goto err;
	}

	command_line[nargs] = NULL;
	for (int i = 0; i < nargs; i++) {
		lua_geti(L, -i-1, i+1);
		command_line[i] = lua_tostring(L, -1);
	}

	r = lua_getfield(L, 1, "env");
	if (r == LUA_TNIL) {
		r = subprocess_create(
			command_line,
			subprocess_option_no_window | subprocess_option_inherit_environment,
			&subprocess
		);
	} else if (r == LUA_TTABLE) {
		int env_success = 0;
		int env_count = 0;

		struct string_link_s {
			rapidstring rs;
			struct string_link_s *parent;
		} *cur_link = NULL;

		/* If this is an ENV table (with an __environ meta key) use that instead. */
		switch (luaL_getmetafield(L, -1, "__environ")) {
			case LUA_TNIL:
				break;
			case LUA_TTABLE:
				lua_remove(L, -2);
				break;
			default:
				/* ignore it. */
				lua_pop(L, 1);
				break;
		}

		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			struct string_link_s *next_link = malloc(sizeof(*next_link));
			if (next_link == NULL) abort(); /* TODO better error message */

			if (lua_type(L, -2) == LUA_TNUMBER) {
				size_t sz;
				const char *str = lua_tolstring(L, -1, &sz);
				rs_init_w_n(&next_link->rs, str, sz);
			} else {
				/* duplicate the key so we can safely run `tolstring()` on it */
				lua_pushvalue(L, -2);

				size_t sz;
				const char *str = lua_tolstring(L, -1, &sz);
				rs_init_w_n(&next_link->rs, str, sz);
				rs_cat_n(&next_link->rs, "=", 1);
				str = lua_tolstring(L, -2, &sz);
				rs_cat_n(&next_link->rs, str, sz);
				lua_pop(L, 1);
			}

			next_link->parent = cur_link;
			cur_link = next_link;

			++env_count;

			lua_pop(L, 1);
		}

		const char **new_env = malloc(sizeof(*new_env) * (env_count + 1));

		if (new_env == NULL) {
			lua_pushliteral(L, "failed to allocate memory for subprocess environment");
			goto env_err_free;
		}

		{
			struct string_link_s *link = cur_link;

			new_env[env_count--] = NULL;
			for (int i = env_count; i >= 0; i--) {
				new_env[i] = rs_data_c(&link->rs);
				link = link->parent;
			}
		}

		r = subprocess_create_ex(
			command_line,
			subprocess_option_no_window,
			new_env,
			&subprocess
		);

		/*
			NOTE: this just means we got through the subprocess creation step,
			NOTE: NOT that the creation was a success. Confusing, I know. Sorry.
		*/
		env_success = 1;

env_err_free:
		free(new_env);

		while (cur_link != NULL) {
			struct string_link_s *link = cur_link;
			cur_link = link->parent;
			rs_free(&link->rs);
			free(link);
		}

		if (!env_success) goto err_free;
	} else {
		lua_pushliteral(L, "`env` option must either be nil or a table");
		goto err_free;
	}
	lua_pop(L, nargs + 1);

	if (r != 0) {
		lua_pushliteral(L, "failed to create subprocess");
		goto err_free;
	}

	if (lua_getfield(L, 1, "stdin") != LUA_TNIL) {
		size_t stdin_size;
		const char *c = lua_tolstring(L, -1, &stdin_size);

		fd = subprocess_stdin(&subprocess);
		if (fd == NULL) {
			lua_pushliteral(L, "`stdin` was provided but failed to get stdin file handle for subprocess");
			goto err_destroy;
		}

		if (fwrite(c, 1, stdin_size, fd) != stdin_size) {
			lua_pushfstring(L, "failed to write stdin to subprocess: %s", strerror(errno));
			goto err_destroy;
		}
	}
	lua_pop(L, 1);

	r = subprocess_join(&subprocess, &status_code);
	if (r != 0) {
		lua_pushliteral(L, "failed to join subprocess");
		goto err_destroy;
	}

	fd = subprocess_stdout(&subprocess);
	if (fd == NULL) {
		lua_pushliteral(L, "failed to get stdout file handle for subprocess");
		goto err_destroy;
	}

	r = read_stream_to_rs(fd, &sout);
	if (r != 0) {
		lua_pushfstring(L, "failed to read subprocess stdout: %s", strerror(errno));
		goto err_destroy;
	}

	fd = subprocess_stderr(&subprocess);
	if (fd == NULL) {
		lua_pushliteral(L, "failed to get stderr file handle for subprocess");
		goto err_destroy;
	}

	r = read_stream_to_rs(fd, &serr);
	if (r != 0) {
		lua_pushfstring(L, "failed to read subprocess stderr: %s", strerror(errno));
		goto err_destroy;
	}

	if (status_code != 0 && should_throw) {
		rapidstring errmsg;
		rs_init(&errmsg);
		rs_cat(&errmsg, "subprocess exited non-zero:");
		for (int i = 0; i < nargs; i++) {
			rs_cat_n(&errmsg, " «", 3);
			rs_cat(&errmsg, command_line[i]);
			rs_cat_n(&errmsg, "»", 2);
		}
		rs_cat(&errmsg, "\n\n--- STDOUT ------------\n");
		rs_cat_rs(&errmsg, &sout);
		rs_cat(&errmsg, "\n--- STDERR ------------\n");
		rs_cat_rs(&errmsg, &serr);
		rs_cat_n(&errmsg, "\n", 1);
		lua_pushlstring(L, rs_data_c(&errmsg), rs_len(&errmsg));
		rs_free(&errmsg);
		goto err_destroy;
	}

	lua_pushnumber(L, status_code);
	lua_pushlstring(L, rs_data_c(&sout), rs_len(&sout));
	lua_pushlstring(L, rs_data_c(&serr), rs_len(&serr));

	success = 3;

err_destroy:
	r = subprocess_destroy(&subprocess);
	if (r != 0 && success) {
		success = 0;
		lua_pushliteral(L, "failed to destroy (cleanup) subprocess");
	}
err_free:
	free(command_line);
	rs_free(&sout);
	rs_free(&serr);
err:
	if (!success) lua_error(L);
	return success;
}

int main(int argc, char *argv[]) {
	int status;
	const char *root_dir;
	const char *bin_dir;
	const char *build_script;
	const char *bootstrap_script;
	lua_State *L;
	int traceback_idx;

	status = 1;

	if (argc < 5) {
		fputs("error: Oro build system called with insufficient arguments\n", stderr);
		fputs("error: (hint: don't call `.oro-build` directly)\n", stderr);
		status = 2;
		goto exit;
	}

	root_dir = argv[1];
	bin_dir = argv[2];
	bootstrap_script = argv[3];
	build_script = argv[4];

	argv += 5;
	argc -= 5;

	L = luaL_newstate();

	if (L == NULL) {
		fputs("error: failed to initialize Lua state\n", stderr);
		goto exit;
	}

	luaL_openlibs(L);

	lua_pushcfunction(L, &display_traceback);
	traceback_idx = lua_gettop(L);

	lua_newtable(L);
	{
		{
			lua_pushstring(L, "root_dir");
			lua_pushstring(L, root_dir);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "bin_dir");
			lua_pushstring(L, bin_dir);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "build_script");
			lua_pushstring(L, build_script);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "execute");
			lua_pushcfunction(L, execute_process);
			lua_rawset(L, -3);
		}
		{
			lua_pushcfunction(L, &luaopen_lfs);
			if (lua_pcall(L, 0, 0, traceback_idx) != 0) {
				fprintf(stderr, "error: failed to load LFS: %s\n", lua_tostring(L, -1));
				goto exit_close_state;
			}

			lua_pushliteral(L, "lfs");
			lua_getglobal(L, "lfs");
			lua_rawset(L, -3);
			lua_pushnil(L);
			lua_setglobal(L, "lfs");
		}
		{
			lua_pushstring(L, "env");
			pushenv(L);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "arg");
			lua_newtable(L);
			for (int i = 0; i < argc; i++) {
				lua_pushstring(L, argv[i]);
				lua_rawseti(L, -2, i + 1);
			}
			lua_rawset(L, -3);
		}
	}
	lua_setglobal(L, "Oro");

	if (luaL_loadfile(L, bootstrap_script) != 0) {
		fprintf(stderr, "error: lua bootstrap failed: %s\n", lua_tostring(L, -1));
		goto exit_close_state;
	}

	if (lua_pcall(L, 0, 0, traceback_idx) != 0) {
		fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
		goto exit_close_state;
	}

	status = 0;

exit_close_state:
	lua_close(L);
exit:
	return status;
}
