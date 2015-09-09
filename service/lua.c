#include "pixel.h"
#include "lalloc.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct lua {
	struct pixel *ctx;
	lua_State *L;
	struct allocator *A;
};

static int traceback(lua_State *L) {
	const char *err = lua_tostring(L, 1);
	if (err) {
		luaL_traceback(L, L, err, 1);
	} else {
		lua_pushliteral(L, "(no error message)");
	}
	return 1;
}

static const char *optstring(struct pixel *ctx, const char *key, const char *def) {
	const char *ret = pixel_command(ctx, "GETENV", key);
	if (!ret) {
		return def;
	}
	return ret;
}

static int _launch(struct pixel *ctx, struct lua *lua, const char *param) {
	const char *loader, *path, *cpath, *service_path;
	lua_State *L = lua->L;
	lua->ctx = ctx;
	lua_gc(L, LUA_GCSTOP, 0);
	luaL_openlibs(L);
	lua_pushlightuserdata(L, ctx);
	lua_setfield(L, LUA_REGISTRYINDEX, "pixel");
	luaL_requiref(L, "pixel.c", pixel_lua, 0);
	luaL_requiref(L, "pixel.serial", pixel_serial, 0);
	lua_settop(L, 0);
	path = optstring(ctx, "lua_path", "./?.lua;./lualib/?.lua");
	lua_pushstring(L, path);
	lua_setglobal(L, "LUA_PATH");
	cpath = optstring(ctx, "lua_cpath", "./?.so");
	lua_pushstring(L, cpath);
	lua_setglobal(L, "LUA_CPATH");
	service_path = optstring(ctx, "lua_service", "./service/?.lua");
	lua_pushstring(L, service_path);
	lua_setglobal(L, "LUA_SERVICE");
	lua_pushcfunction(L, traceback);
	assert(lua_gettop(L) == 1);
	loader = optstring(ctx, "lua_loader", "./lualib/loader.lua");
	if (LUA_OK != luaL_loadfile(L, loader)) {
		pixel_log(ctx, "luaL_loadfile %s\n", lua_tostring(L, -1));
		return -1;
	}
	lua_pushstring(L, param);
	if (LUA_OK != lua_pcall(L, 1, 0, 1)) {
		pixel_log(ctx, "lua loader %s\n", lua_tostring(L, -1));
		return -1;
	}
	lua_settop(L, 0);
	lua_gc(L, LUA_GCRESTART, 0);
	return 0;
}

int lua_init(struct lua *lua, struct pixel *ctx, const char *param) {
	return _launch(ctx, lua, param);
}

void *lua_new(void) {
	struct lua *lua = (struct lua *)malloc(sizeof *lua);
	lua->A = allocator_new();
	lua->L = lua_newstate(pixel_lalloc, lua->A);
	lua->ctx = 0;
	return lua;
}

void lua_free(struct lua *lua) {
	lua_close(lua->L);
	allocator_free(lua->A);
	free(lua);
}

void lua_signal(struct lua *lua, int signal) {
	pixel_log(lua->ctx, "lua signal:%d\n", signal);
}
