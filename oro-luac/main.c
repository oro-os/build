#ifndef _WIN32
#	if defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE < 200809L
#		undef _POSIX_C_SOURCE
#	endif
#	ifndef _POSIX_C_SOURCE
#		define _POSIX_C_SOURCE 200809L
#	endif
#	define _DEFAULT_SOURCE 1 /* for dirent::d_type macros */
#endif

#define MAKE_LIB 1
#define LUA_ANSI 1
#include "../oro-build/ext/lua/onelua.c"
#undef LUA_ANSI
#undef MAKE_LIB

#include "../oro-build/ext/lua/lua.h"
#include "../oro-build/ext/lua/lualib.h"
#include "../oro-build/ext/lua/lauxlib.h"
#include "../oro-build/ext/rapidstring/include/rapidstring.h"

#include <dirent.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>
#include <stdio.h>
#include <string.h>

/*
	Perhaps a bit cheeky, but we use Lua here instead of
	using a custom hashmap system.
*/

static int dump_chunk(lua_State *L, const void *p, size_t sz, void *ud) {
	(void) L;
	rs_cat_n(ud, p, sz);
	return 0;
}

static int crawl_directory(lua_State *L, const rapidstring *root_path, DIR *dir, const rapidstring *path, int debug) {
	int status = 1;

	errno = 0;
	for (struct dirent *ent = NULL; (ent = readdir(dir)); errno = 0) {
		if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
			continue;
		}

		rapidstring child_path;
		rs_init_w_rs(&child_path, path);
		rs_cat(&child_path, "/");
		rs_cat(&child_path, ent->d_name);

		size_t name_len = strlen(ent->d_name);

		int is_dir = 0;
		if (ent->d_type == DT_UNKNOWN) {
			struct stat stats;
			int r = fstatat(dirfd(dir), ent->d_name, &stats, 0);
			if (r != 0) {
				fprintf(stderr, "error: fstatat(%s): %s\n", rs_data_c(&child_path), strerror(errno));
				rs_free(&child_path);
				goto finish;
			}

			is_dir = S_ISDIR(stats.st_mode);
		} else {
			is_dir = ent->d_type == DT_DIR;
		}

		if (is_dir) {
			int child_dir_fd = openat(dirfd(dir), ent->d_name, O_DIRECTORY);
			DIR *child_dir = fdopendir(child_dir_fd);

			int r = crawl_directory(L, root_path, child_dir, &child_path, debug);
			if (r != 0) {
				status = r;
				rs_free(&child_path);
				goto finish;
			}
		} else {
			if (name_len < 4 || strcmp(&ent->d_name[name_len - 4], ".lua") != 0) {
				rs_free(&child_path);
				continue;
			}

			rapidstring abs_path;
			rs_init_w_rs(&abs_path, root_path);
			rs_cat(&abs_path, "/");
			rs_cat_rs(&abs_path, &child_path);

			if (luaL_loadfile(L, rs_data_c(&abs_path)) != LUA_OK) {
				fprintf(stderr, "error: when loading %s:\n\n%s\n", rs_data_c(&abs_path), lua_tostring(L, -1));
				rs_free(&abs_path);
				rs_free(&child_path);
				goto finish;
			}

			rapidstring chunk_binary;
			rs_init(&chunk_binary);
			lua_dump(L, &dump_chunk, &chunk_binary, !debug);
			lua_pop(L, 1);

			lua_pushlstring(L, rs_data_c(&chunk_binary), rs_len(&chunk_binary));
			lua_setfield(L, -2, rs_data_c(&child_path));

			rs_free(&abs_path);
			rs_free(&chunk_binary);
			rs_free(&child_path);
		}
	}

	if (errno) {
		fprintf(stderr, "error: readdir(%s/%s): %s\n", rs_data_c(root_path), rs_data_c(path), strerror(errno));
		goto finish;
	} else {
		status = 0;
	}

finish:
	return status;
}

int main(int argc, char *argv[]) {
	int status = 1;

	if (argc != 5) {
		fprintf(stderr, "usage: %s <source_dir/> <prefix> <output_file.c> <debug:1|0>\n", argc > 0 ? argv[0] : "orb-luac");
		status = 2;
		goto exit;
	}

	rapidstring root_path;
	rs_init_w(&root_path, argv[1]);

	DIR *root_dir = opendir(argv[1]);
	if (root_dir == NULL) {
		fprintf(stderr, "error: opendir(%s): %s\n", argv[1], strerror(errno));
		goto exit_free_root_path;
	}

	int debug = strcmp(argv[4], "0") != 0;

	rapidstring current_path;
	rs_init(&current_path);

	lua_State *L = luaL_newstate();
	if (L == NULL) {
		fputs("error: failed to create Lua state\n", stderr);
		goto exit_free_current_path;
	}

	lua_createtable(L, 0, 0);

	if (crawl_directory(L, &root_path, root_dir, &current_path, debug)) {
		goto exit_lua;
	}

	FILE *out = fopen(argv[3], "w");
	if (out == NULL) {
		perror("error: fopen()");
		goto exit_lua;
	}

#	define chk(write_expr) do { if ((write_expr)) { perror("error: write()"); goto exit_output; } } while (0)
#	define writelit(literal) chk(fwrite((literal), sizeof((literal)) - 1, 1, out) != 1)
#	define writestr(str) chk({ size_t lenn = strlen((str)); int r = fwrite((str), lenn, 1, out) != 1; r })
#	define writestrn(str, n) chk(fwrite((str), n, 1, out) != 1)

	writelit(
		"/* NOTE: Auto-generated source; do not edit directly. */\n"
		"#include <stddef.h>\n"
		"\n"
		"struct orb_script_builtin_t {\n"
		"	const char *path;\n"
		"	size_t size;\n"
		"	const char *data;\n"
		"} static const orb_script_builtins[] = {"
	);

	lua_pushnil(L);
	while (lua_next(L, -2)) {
		rapidstring entry;
		rs_init_w(&entry, "\n\t{ \"");
		rs_cat(&entry, lua_tostring(L, -2));
		rs_cat(&entry, "\", ");
		lua_len(L, -1);
		rs_cat(&entry, lua_tostring(L, -1));
		lua_pop(L, 1);
		rs_cat(&entry, ", \"");
		size_t sz = 0;
		const char *base = lua_tolstring(L, -1, &sz);
		char code[4];
		code[0] = '\\';
		code[1] = 'x';
		for (size_t i = 0; i < sz; i++) {
			code[2] = '0' + ((base[i] >> 4) & 0xF);
			code[3] = '0' + (base[i] & 0xF);
			if (code[2] > '9') code[2] += ('A' - '9' - 1);
			if (code[3] > '9') code[3] += ('A' - '9' - 1);
			rs_cat_n(&entry, code, sizeof(code));
		}
		rs_cat(&entry, "\" },");
		lua_pop(L, 1);
		writestrn(rs_data_c(&entry), rs_len(&entry));
		rs_free(&entry);
	}

	writelit("\n};\n");

	status = 0;

exit_output:
	fclose(out);
exit_lua:
	lua_close(L);
exit_free_current_path:
	rs_free(&current_path);
	closedir(root_dir);
exit_free_root_path:
	rs_free(&root_path);
exit:
	return status;
}
