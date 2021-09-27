#include "./ext/lua/onelua.c"
#include "./ext/luafilesystem/src/lfs.c"

#include "./ext/lua/lua.h"
#include "./ext/lua/lualib.h"
#include "./ext/lua/lauxlib.h"
#include "./ext/luafilesystem/src/lfs.h"

#include <stdio.h>

static int display_traceback(lua_State *L) {
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	lua_pushvalue(L, 1);
	lua_pushinteger(L, 2);
	lua_call(L, 2, 1);
	return 1;
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

	lua_pushcfunction(L, &luaopen_lfs);
	if (lua_pcall(L, 0, 0, traceback_idx) != 0) {
		fprintf(stderr, "error: failed to load LFS: %s\n", lua_tostring(L, -1));
		goto exit_close_state;
	}

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
