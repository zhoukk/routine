#include "pixel.h"
#include "pixel_impl.h"
#include "env.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

static int optint(const char *key, int opt) {
	const char *val = env_get(key);
	if (!val) {
		char tmp[16];
		sprintf(tmp, "%d", opt);
		env_set(key, tmp);
		return opt;
	}
	return strtol(val, 0, 10);
}

static const char *optstring(const char *key, const char *opt) {
	const char *val = env_get(key);
	if (!val) {
		if (opt) {
			env_set(key, opt);
			opt = env_get(key);
		}
		return opt;
	}
	return val;
}

static void _init_env(lua_State *L) {
	lua_pushglobaltable(L);
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		const char *key;
		int kt = lua_type(L, -2);
		if (kt != LUA_TSTRING) {
			fprintf(stderr, "invalid config key\n");
			exit(1);
		}
		key = lua_tostring(L, -2);
		if (lua_type(L, -1) == LUA_TBOOLEAN) {
			int b = lua_toboolean(L, -1);
			env_set(key, b?"true":"false");
		} else {
			const char *val = lua_tostring(L, -1);
			if (!val) {
				fprintf(stderr, "invalid config val, key=%s\n", key);
				exit(1);
			}
			env_set(key, val);
		}
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
}

void signin(void) {
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = SIG_IGN;
	sigaction(SIGPIPE, &sa, 0);
}

int main(int argc, char *argv[]) {
	const char *config = "config";
	struct pixel_config cfg;
	lua_State *L;
	if (argc > 1) {
		config = argv[1];
	}
	signin();
	pixel_init();
	L = luaL_newstate();
	if (LUA_OK != luaL_dofile(L, config)) {
		fprintf(stderr, "load config:%s\n", lua_tostring(L, -1));
		return 1;
	}
	_init_env(L);
	cfg.thread = optint("thread", 8);
	cfg.harbor = optint("harbor", 1);
	cfg.module_path = optstring("cservice", "./?.so");
	cfg.bootstrap = optstring("bootstrap", "lua bootstrap");
	cfg.logfile = optstring("log", 0);
	lua_close(L);
	pixel_start(&cfg);
	pixel_unit();
	return 0;
}
