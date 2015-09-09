#include "env.h"
#include "lock.h"

#include "lua.h"
#include "lauxlib.h"

struct env {
	struct spinlock lock;
	lua_State *L;
};

static struct env E;

void env_init(void) {
	spinlock_init(&E.lock);
	E.L = luaL_newstate();
}

void env_unit(void) {
	lua_close(E.L);
	spinlock_unit(&E.lock);
}

void env_set(const char *key, const char *val) {
	spinlock_lock(&E.lock);
	lua_getglobal(E.L, key);
	lua_pop(E.L, 1);
	lua_pushstring(E.L, val);
	lua_setglobal(E.L, key);
	spinlock_unlock(&E.lock);
}

const char *env_get(const char *key) {
	const char *val;
	spinlock_lock(&E.lock);
	lua_getglobal(E.L, key);
	val = lua_tostring(E.L, -1);
	lua_pop(E.L, 1);
	spinlock_unlock(&E.lock);
	return val;
}
