 /*
	 __   __   __
	/  \ |__) /  \
	\__/ |  \ \__/

	ORO BUILD GENERATOR
	Copyright (c) 2021-2022, Josh Junon
	License TBD
*/

/*
	Lua environment C support runtime
*/

#ifndef _WIN32
#	if defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE < 200809L
#		undef _POSIX_C_SOURCE
#	endif
#	ifndef _POSIX_C_SOURCE
#		define _POSIX_C_SOURCE 200809L
#	endif
#endif

#include "./ext/lua/onelua.c"
#include "./ext/luafilesystem/src/lfs.c"

#include "./ext/lua/lua.h"
#include "./ext/lua/lualib.h"
#include "./ext/lua/lauxlib.h"
#include "./ext/luafilesystem/src/lfs.h"
#include "./ext/subprocess.h/subprocess.h"
#include "./ext/rapidstring/include/rapidstring.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#ifdef _WIN32
#	include <windows.h>
#	define ORO_PLATFORM_PATH_SEP ";"
#	define ORO_PLATFORM_PATH_DELIMS "/\\"
#	define oro_stat _stat
#	define ORO_S_ISREG(m) (((m) & _S_IFREG) == _S_IFREG)
#	ifdef _S_IXUSR
#		define ORO_S_IXUSR _S_IXUSR
#	else
#		define ORO_S_IXUSR 0100
#	endif
	typedef struct _stat oro_stat_t;
#else
#	include <fcntl.h>
#	include <dirent.h>
#	include <sys/stat.h>
#	include <sys/types.h>
#	include <sys/time.h>
#	include <sys/sendfile.h>
#	include <unistd.h>
#	ifndef O_PATH
#		define O_PATH 010000000
#	endif
#	define ORO_PLATFORM_PATH_SEP ":"
#	define ORO_PLATFORM_PATH_DELIMS "/"
#	define oro_stat stat
#	define ORO_S_ISREG S_ISREG
	typedef struct stat oro_stat_t;
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

static int next_iterator(lua_State *L) {
	/* -1, +(2|0) */
	/*
		requires upvalues:
		   1: the table on which to call lua_next()
	*/
	return lua_next(L, lua_upvalueindex(1))
		? 2
		: 0;
}

static int pair_iterator(lua_State *L) {
	/* -1, +2 */
	/*
		requires upvalues:
		   1: the table on which to call the iterator
		   2: the iterator function (usually result
		      of a call to __pairs() metamethod)
	*/

	lua_pushvalue(L, lua_upvalueindex(1));
	lua_pushvalue(L, -2);
	lua_copy(L, lua_upvalueindex(2), -3);
	lua_call(L, 2, 2);
	return 2;
}

static int iterator_next(lua_State *L) {
	/* -2, +(1|3), r */
	lua_pushvalue(L, -1);
	lua_copy(L, -3, -2);
	lua_call(L, 1, 2);

	if (lua_isnil(L, -2)) {
		lua_pop(L, 2);
		return 0;
	}

	return 1;
}

static char * oro_strndup(const char *str, size_t len) {
	char * newstr = malloc(len + 1);
	strncpy(newstr, str, len + 1);
	newstr[len] = 0;
	return newstr;
}

/* https://stackoverflow.com/a/26228023/510036 */
static char * oro_strsep(char **stringp, const char *delim) {
	if (*stringp == NULL) { return NULL; }
	char *token_start = *stringp;
	*stringp = strpbrk(token_start, delim);
	if (*stringp) {
		**stringp = '\0';
		(*stringp)++;
	}
	return token_start;
}

static int split_string(lua_State *L) {
	/* -, +1, ERR */
	size_t strn;
	const char *str = luaL_checklstring(L, 1, &strn);
	const char *delim = luaL_checkstring(L, 2);

	lua_newtable(L);
	char *strd = oro_strndup(str, strn);
	char *cursor = strd;

	const char *token;
	size_t i = 0;
	while ((token = oro_strsep(&cursor, delim))) {
		lua_pushstring(L, token);
		lua_seti(L, -2, ++i);
	}

	free(strd);

	return 1;
}

static int try_access(const char *pathname, int amode) {
	/* Stub wrapper that calls access(3) without affecting `errno`. */
	int errno_before = errno;
	int r = access(pathname, amode);
	errno = errno_before;
	return r;
}

static int search_path(lua_State *L) {
	/* -, +1 */
	const char *search = luaL_checkstring(L, 1);
	size_t pathstringn;
	const char *pathstring = luaL_checklstring(L, 2, &pathstringn);

	if (strpbrk(search, ORO_PLATFORM_PATH_DELIMS) == NULL) {
		const char * const delim = lua_isstring(L, 3)
			? lua_tostring(L, 3)
			: ORO_PLATFORM_PATH_SEP;

		const char *path_entry;
		char *pathstringd = oro_strndup(pathstring, pathstringn);
		char *pathstringc = pathstringd;
		int found = 0;

		while ((path_entry = oro_strsep(&pathstringc, delim))) {
			if (*path_entry == '\0') {
				path_entry = ".";
			}

			lua_pushfstring(L, "%s%c%s", path_entry, ORO_PLATFORM_PATH_DELIMS[0], search);
			const char *fullpath = lua_tostring(L, -1);

			oro_stat_t stats;
			errno = 0;
			int r = oro_stat(fullpath, &stats);

			if (
				r == 0
				&& ORO_S_ISREG(stats.st_mode)
#			ifdef _WIN32
				&& (stats.st_mode & ORO_S_IXUSR) != 0
#			else
				&& try_access(fullpath, X_OK) == 0
#			endif
			) {
				found = 1;
				break;
			} else {
				lua_pop(L, 1); /* NOTE: `fullpath` is no longer a valid pointer after this point */

				/*
					There are a few error cases where
					we just want to silently ignore.
				*/
				switch (errno) {
				case 0:
					/*
						this also handles cases where the stat()/access() call(s) succeeded,
						but the node wasn't suitable (not a regular file or not executable).
					*/
				case EACCES:
				case ELOOP:
				case ENOENT:
				case ENOTDIR:
					continue;
				}

				luaL_error(
					L,
					/*
						we can't re-use `fullpath` here since it's undefined
						what happens to the pointer after we pop it, so we
						re-create the value here.
					*/
					"fatal error attempting to resolve path: %s: %s%c%s (attempting to find '%s' in '%s')",
					strerror(errno),
					path_entry,
					ORO_PLATFORM_PATH_DELIMS[0],
					search,
					search,
					path_entry
				);
			}
		}

		free(pathstringd);

		if (!found) lua_pushnil(L);
	} else {
		/* No search necessary; just return. */
		lua_pushvalue(L, 1);
	}

	return 1;
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

		/* More information: https://stackoverflow.com/a/69367175/510036 */
		switch (luaL_getmetafield(L, -1, "__pairs")) {
			default:
				/* unsupported type; fall back to default */
				lua_pop(L, 1);
				/* fallthrough */
			case LUA_TNIL:
				/* nothing was pushed; no need to pop first. */
				lua_pushcclosure(L, &next_iterator, 1);
				break;
			case LUA_TFUNCTION:
				/* call the __pairs() metamethod and get a function back */
				lua_pushvalue(L, -2);
				lua_call(L, 1, 1);
				/* now pass the pairs function iterator closure */
				lua_pushcclosure(L, &pair_iterator, 2);
				break;
		}

		lua_pushnil(L);
		while (iterator_next(L)) {
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

			/* pop the value, leaving just the iterator and key */
			lua_pop(L, 1);
		}
		/* pop the iterator */
		lua_pop(L, 1);

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

	lua_pop(L, nargs);

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

static int main_build(int argc, char *argv[]) {
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
		fputs("error: (hint: don't call `.oro/build` directly)\n", stderr);
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
			lua_pushstring(L, "search_path");
			lua_pushcfunction(L, search_path);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "execute");
			lua_pushcfunction(L, execute_process);
			lua_rawset(L, -3);
		}
		{
			lua_pushstring(L, "split");
			lua_pushcfunction(L, split_string);
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
	lua_setglobal(L, "__ORO__");

	/*
		Set up the package search path.
		In the case we `require` a directory,
		look for the "index" at `<dir>/_.lua`.
	*/
	lua_getglobal(L, "package");
	lua_pushfstring(L, "%s/?.lua;%s/?/_.lua", root_dir, root_dir);
	lua_setfield(L, -2, "path");
	lua_pop(L, 1);

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

static int main_touch(int argc, char *argv[]) {
	assert(argc > 0);

	int status = 0;

	for (int i = 1; i < argc; i++) {
		const char *filepath = argv[i];

		int fd = open(filepath, O_WRONLY | O_CREAT | O_APPEND, 0644);
		if (fd == -1) {
			fprintf(stderr, "touch: open(): %s: %s\n", strerror(errno), filepath);
			status = 1;
			continue;
		}

		if (futimens(fd, NULL)) {
			fprintf(stderr, "touch: futimes(): %s: %s\n", strerror(errno), filepath);
			status = 1;
		}

		if (close(fd) != 0) {
			fprintf(stderr, "touch: warning: close(): %s: %s\n", strerror(errno), filepath);
			// We don't count this as an error.
		}
	}

	return status;
}

static int main_echo(int argc, char *argv[]) {
	assert(argc > 0);

	const char *sep = "";
	for (int i = 1; i < argc; i++) {
		printf("%s%s", sep, argv[i]);
		sep = " ";
	}
	putc('\n', stdout);

	return 0;
}

static int main_init_depfile(int argc, char *argv[]) {
	assert(argc > 0);

	if (argc == 1) {
		fputs("error: no output file given\n", stderr);
		return 2;
	}

	if (argc > 2) {
		fprintf(stderr, "error: expected exactly 1 argument; got %d\n", argc - 1);
		return 2;
	}

	char *filepath = argv[1];
	if (*filepath == 0) {
		fputs("error: filepath cannot be empty\n", stderr);
		return 2;
	}

	size_t len = strlen(filepath);
	if (len < 3 || filepath[len-1] != 'd' || filepath[len-2] != '.') {
		fprintf(stderr, "error: filepath must end with '.d': %s\n", filepath);
		return 2;
	}

	int status = 1;

	FILE *fd = fopen(filepath, "wb");

	if (fd == NULL) {
		fprintf(stderr, "error: fopen(): %s: %s\n", strerror(errno), filepath);
		goto exit;
	}

	filepath[len - 2] = 0;

	errno = 0;
	if (fprintf(fd, "%s:\n", filepath) < 0) {
		fprintf(stderr, "error: fprintf(): %s: %s\n", strerror(errno), filepath);
		goto exit_close;
	}

	status = 0;

exit_close:
	fclose(fd);
exit:
	return status;
}

static int cp_file_outfd(const char *from, int outfd) {
	int status = 1;

	FILE *inf = fopen(from, "rb");
	if (inf == NULL) {
		fprintf(stderr, "fopen(rb): %s: %s\n", strerror(errno), from);
		goto exit;
	}

	int infd = fileno(inf);
	assert(infd != -1); // should never happen.

	struct stat stats;
	if (fstat(infd, &stats) != 0) {
		fprintf(stderr, "fstat(): %s: %s\n", strerror(errno), from);
		goto exit_close_inf;
	}

	off_t offset = 0;
	size_t remaining = stats.st_size;

	while (offset >= 0 && remaining > 0) {
		// If this is failing, it might mean you're on
		// a kernel older than 2.6.33. Please open an
		// issue if this is really a blocker for you.
		// Likewise, a PR that adequately detected
		// such a case and performed a byte-buffer copy
		// would be accepted.
		ssize_t sent = sendfile(outfd, infd, &offset, remaining);
		if (sent < 0) {
			fprintf(stderr, "sendfile(): %s: %s \n", strerror(errno), from);
			goto exit_close_inf;
		}

		remaining -= (size_t) sent;
		offset += sent;
	}

	if (remaining > 0) {
		fprintf(stderr, "sendfile(): unexpected error (remaining > 0): %s\n", from);
		goto exit_close_inf;
	}

	status = 0;

exit_close_inf:
	fclose(inf);
exit:
	return status;
}

static int cp_file(const char *from, const char *to) {
#ifdef _WIN32
	// PR welcome!
#	error "`--syscall cp` is unsupported on Windows"
#else
	int status = 1;

	FILE *outf = fopen(to, "wb");
	if (outf == NULL) {
		fprintf(stderr, "fopen(wb): %s: %s\n", strerror(errno), to);
		goto exit;
	}

	int outfd = fileno(outf);
	assert(outfd != -1); // should never happen.

	status = cp_file_outfd(from, outfd);

	fclose(outf);
exit:
	return status;
#endif
}

static int main_cp(int argc, char *argv[]) {
	assert(argc > 0);

	if (argc < 3) {
		fputs("error: usage: cp <inputs[...]> <output[_directory]>\n", stderr);
		return 2;
	}

	int failed = 0;

	if (argc == 3) {
		failed = cp_file(argv[1], argv[2]) != 0;
	} else {
		assert(argc > 3);

		const char *dirpath = argv[argc - 1];
		int outdir = open(dirpath, O_DIRECTORY | O_PATH);

		if (outdir == -1) {
			fprintf(stderr, "open(DIRECTORY): %s: %s\n", strerror(errno), dirpath);
			failed = 1;
		} else {
			for (int i = 1, last = argc - 1; i < last; i++) {
				const char *filename = argv[i];
				const char *base = strrchr(filename, '/');
				base = base ? &base[1] : filename;

				int outfd = openat(outdir, base, O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
				if (outfd == -1) {
					fprintf(stderr, "openat(): %s: %s/%s\n", strerror(errno), dirpath, base);
					failed = 1;
					continue;
				}

				if (cp_file_outfd(filename, outfd) != 0) {
					failed = 1;
				}

				close(outfd);
			}

			close(outdir);
		}
	}

	return failed;
}

int main(int argc, char *argv[]) {
	if (argc == 0) {
		fputs("error: no arg0\n", stderr);
		return 2;
	}

	if (argc > 1 && strcmp(argv[1], "--syscall") == 0) {
		argc -= 2;
		argv += 2;

		if (argc == 0) {
			fputs("error: --syscall takes at least 1 argument (got none)\n", stderr);
			return 2;
		}

		if (strcmp(argv[0], "touch") == 0) return main_touch(argc, argv);
		if (strcmp(argv[0], "pass") == 0) return 0;
		if (strcmp(argv[0], "fail") == 0) return 1;
		if (strcmp(argv[0], "echo") == 0) return main_echo(argc, argv);
		if (strcmp(argv[0], "init-depfile") == 0) return main_init_depfile(argc, argv);
		if (strcmp(argv[0], "cp") == 0) return main_cp(argc, argv);

		fprintf(stderr, "error: unknown syscall: %s\n", argv[0]);
		return 2;
	}

	return main_build(argc, argv);
}
