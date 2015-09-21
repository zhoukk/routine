#include "pixel.h"
#include "pixel_impl.h"
#include "lock.h"
#include "socket.h"
#include "timer.h"
#include "handle.h"
#include "queue.h"
#include "module.h"
#include "harbor.h"
#include "monitor.h"
#include "dump.h"
#include "log.h"
#include "env.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdarg.h>

struct pixel {
	struct queue *queue;
	struct module *module;
	void *inst;
	uint32_t handle;
	int session;
	pixel_cb cb;
	void *ud;
	int endless;
	FILE *logfile;
	char tmp[32];
};

struct pixel_global {
	int total;
	struct pixel *log;
};

static struct pixel_global G;

void *pixel_alloc(void *p, int size) {
	if (size == 0) {
		if (p) {
			free(p);
		}
		return 0;
	} else {
		p = malloc(size);
		memset(p, 0, size);
		return p;
	}
}

void pixel_log(struct pixel *ctx, const char *fmt, ...) {
	if (G.log == 0) {
		va_list ap;
		if (ctx) {
			fprintf(stderr, "[%u] ", ctx->handle);
		} else {
			fprintf(stderr, "[%u] ", 0);
		}
		va_start(ap, fmt);
		vfprintf(stderr, fmt, ap);
		va_end(ap);
		return;
	} else {
		struct message m;
		size_t size;
		va_list ap;
		va_start(ap, fmt);
		size = vsnprintf(0, 0, fmt, ap);
		va_end(ap);
		m.data = pixel_alloc(0, size+1);
		va_start(ap, fmt);
		vsnprintf((char *)m.data, size+1, fmt, ap);
		va_end(ap);
		if (!ctx) {
			m.source = 0;
		} else {
			m.source = pixel_handle(ctx);
		}
		m.session = 0;
		m.size = size | ((size_t)PIXEL_TEXT << MSG_TYPE_SHIFT);
		if (pixel_push(G.log->handle, &m)) {
			if (ctx) {
				fprintf(stderr, "[%u] ", ctx->handle);
			} else {
				fprintf(stderr, "[%u] ", 0);
			}
			fprintf(stderr, "%s", (char *)m.data);
			pixel_alloc(m.data, 0);
		}
	}
}

void pixel_setlog(struct pixel *ctx) {
	G.log = ctx;
	pixel_reserve(ctx);
}

void pixel_init(void) {
	G.total = 0;
	G.log = 0;
	env_init();
}

void pixel_unit(void) {
	harbor_unit();
	pixel_dispatchall(G.log);
	pixel_force_free(G.log);
	socket_unit();
	timer_unit();
	handle_unit();
	module_unit();
	queue_unit();
	env_unit();
}

static void _pixel_total_inc(void) {
	atom_inc(&G.total);
}

static void _pixel_total_dec(void) {
	atom_dec(&G.total);
}

void pixel_reserve(struct pixel *ctx) {
	handle_grab(ctx->handle);
	_pixel_total_dec();
}

void pixel_free(struct pixel *ctx) {
	if (ctx) {
		pixel_log(ctx, "EXIT\n");
		if (ctx->logfile) {
			fclose(ctx->logfile);
		}
		queue_mark_free(ctx->queue);
		module_inst_free(ctx->module, ctx->inst);
		pixel_alloc(ctx, 0);
	}
}

static void _drop_message(struct message *m, void *ud) {
	pixel_alloc(m->data, 0);
}

void pixel_force_free(struct pixel *ctx) {
	struct queue *q = ctx->queue;
	ctx = handle_release(ctx->handle);
	if (!ctx) {
		queue_free(q, _drop_message, 0);
		_pixel_total_dec();
	}
}

void pixel_exit(void) {
	handle_exit();
}

struct pixel *pixel_new(const char *name, const char *param) {
	struct pixel *ctx;
	struct module *module;
	void *inst;
	module = module_query(name);
	if (!module) {
		return 0;
	}
	inst = module_inst_new(module);
	if (!inst) {
		return 0;
	}
	ctx = (struct pixel *)pixel_alloc(0, sizeof *ctx);
	ctx->module = module;
	ctx->inst = inst;
	ctx->handle = handle_regist(ctx);
	ctx->session = 0;
	ctx->endless = 0;
	ctx->queue = queue_new(ctx->handle);
	_pixel_total_inc();
	ctx = handle_grab(ctx->handle);
	if (module_inst_init(module, inst, ctx, param)) {
		pixel_log(ctx, "LAUNCH FAILED %s %s\n", name, param ? param : "");
		handle_release(ctx->handle);
		pixel_force_free(ctx);
		return 0;
	}
	queue_push_global(ctx->queue);
	ctx = handle_release(ctx->handle);
	if (ctx) {
		pixel_log(ctx, "LAUNCH %s %s\n", name, param ? param : "");
	}
	return ctx;
}

int pixel_total(void) {
	return G.total;
}

void pixel_endless(uint32_t handle) {
	struct pixel *ctx = handle_grab(handle);
	if (ctx) {
		ctx->endless = 1;
		handle_release(handle);
	}
}

uint32_t pixel_handle(struct pixel *ctx) {
	return ctx->handle;
}

int pixel_session(struct pixel *ctx) {
	return ++ctx->session;
}

int pixel_push(uint32_t handle, struct message *m) {
	struct pixel *ctx = handle_grab(handle);
	if (!ctx) {
		return -1;
	}
	queue_push(ctx->queue, m);
	handle_release(ctx->handle);
	return 0;
}

static void _dispatch(struct pixel *ctx, struct message *m) {
	int type = m->size >> MSG_TYPE_SHIFT;
	size_t size = m->size & MSG_TYPE_MASK;
	if (ctx->logfile) {
		log_output(ctx->logfile, m->source, type, m->session, m->data, size);
	}
	if (!ctx->cb(ctx, ctx->ud, type, m->session, m->source, m->data, size)) {
		pixel_alloc(m->data, 0);
	}
}

void pixel_callback(struct pixel *ctx, void *ud, pixel_cb cb) {
	ctx->cb = cb;
	ctx->ud = ud;
}

static void _filter_args(struct pixel *ctx, int type, int *session, void **data, size_t *size) {
	int needcopy = !(type & PIXEL_TAG_DONTCOPY);
	int alloc_session = type & PIXEL_TAG_ALLOCSESSION;
	type &= 0xff;
	if (alloc_session) {
		*session = pixel_session(ctx);
	}
	if (needcopy && *data) {
		char *newdata = (char *)pixel_alloc(0, *size);
		memcpy(newdata, *data, *size);
		*data = newdata;
	}
	*size |= (size_t)type << MSG_TYPE_SHIFT;
}

int pixel_send(struct pixel *ctx, uint32_t source, uint32_t destination, int type, int session, void *data, size_t size) {
	int r;
	struct message m;
	if ((size & MSG_TYPE_MASK) != size) {
		pixel_log(ctx, "message to %u is too large (size=%d)\n", destination, size);
		if (type & PIXEL_TAG_DONTCOPY) {
			pixel_alloc(data, 0);
		}
		return -1;
	}
	if (destination == 0) {
		if (type & PIXEL_TAG_DONTCOPY) {
			pixel_alloc(data, 0);
		}
		return -1;
	}
	_filter_args(ctx, type, &session, (void **)&data, &size);
	if (source == 0) {
		source = ctx->handle;
	}
	m.source = source;
	m.session = session;
	m.data = data;
	m.size = size;
	if (harbor_isremote(destination)) {
		r = harbor_send(destination, &m);
	} else {
		r = pixel_push(destination, &m);
	}
	if (r) {
		pixel_alloc(data, 0);
		return -1;
	}
	return session;
}

struct timer_event {
	int session;
	uint32_t handle;
};

void pixel_timer_dispatch(void *ud) {
	struct timer_event *event = (struct timer_event *)ud;
	struct message m;
	m.source = 0;
	m.session = event->session;
	m.data = 0;
	m.size = (size_t)PIXEL_RESPONSE << MSG_TYPE_SHIFT;
	pixel_push(event->handle, &m);
}

void pixel_socket_dispatch(struct socket_message *sm) {
	struct message m;
	unsigned handle;
	size_t size;
	int ret = sm->type;
	if (ret == SOCKET_EXIT) {
		return;
	}
	size = sizeof(*sm);
	m.data = pixel_alloc(0, size);
	memcpy(m.data, sm, size);
	m.size = size | ((size_t)PIXEL_SOCKET << MSG_TYPE_SHIFT);
	m.source = 0;
	m.session = 0;
	handle = (uint32_t)(uintptr_t)sm->ud;
	if (pixel_push(handle, &m)) {
		pixel_alloc(m.data, 0);
	}
}

struct queue *pixel_dispatch(struct queue *q, struct monitor *monitor) {
	uint32_t handle;
	struct message m;
	struct pixel *ctx;
	struct queue *next;
	int overload;
	if (!q) {
		q = queue_pop_global();
		if (!q) {
			return 0;
		}
	}
	handle = queue_handle(q);
	ctx = handle_grab(handle);
	if (!ctx) {
		queue_free(q, _drop_message, 0);
		_pixel_total_dec();
		return queue_pop_global();
	}
	if (0 != queue_pop(q, &m)) {
		handle_release(handle);
		return queue_pop_global();
	}
	overload = queue_overload(q);
	if (overload) {
		pixel_log(ctx, "overload queue length = %d\n", overload);
	}
	monitor_trigger(monitor, m.source, handle);
	if (!ctx->cb) {
		pixel_log(ctx, "_dispatch handle:%u err\n", ctx->handle);
		pixel_alloc(m.data, 0);
	} else {
		_dispatch(ctx, &m);
	}
	monitor_trigger(monitor, 0, 0);
	next = queue_pop_global();
	if (next) {
		queue_push_global(q);
		q = next;
	}
	handle_release(handle);
	return q;
}

void pixel_dispatchall(struct pixel *ctx) {
	struct message m;
	struct queue *q = ctx->queue;
	while (!queue_pop(q, &m)) {
		_dispatch(ctx, &m);
	}
}

static const char *_cmd_launch(struct pixel *ctx, const char *cmd , const char *param) {
	struct pixel *newctx;
	char tmp[strlen(param)+1];
	char *p, *name;
	strcpy(tmp, param);
	p = tmp;
	name = strsep(&p, " ");
	newctx = pixel_new(name, p);
	if (!newctx) {
		return 0;
	}
	sprintf(ctx->tmp, "%u", newctx->handle);
	return ctx->tmp;
}

static const char *_cmd_kill(struct pixel *ctx, const char *cmd , const char *param) {
	uint32_t handle = ctx->handle;
	if (param) {
		handle = strtoul(param, 0, 0);
		if (handle == 0) {
			pixel_log(ctx, "kill:%s failed\n", param);
			return 0;
		}
	}
	handle_release(handle);
	return 0;
}

static const char *_cmd_abort(struct pixel *ctx, const char *cmd , const char *param) {
	pixel_exit();
	return 0;
}

static const char *_cmd_timeout(struct pixel *ctx, const char *cmd, const char *param) {
	int ti = atoi(param);
	int session = pixel_session(ctx);
	if (ti == 0) {
		struct message m;
		m.session = session;
		m.source = 0;
		m.data = 0;
		m.size = (size_t)PIXEL_RESPONSE << MSG_TYPE_SHIFT;
		if (pixel_push(ctx->handle, &m)) {
			session = -1;
		}
	} else {
		struct timer_event event;
		event.session = session;
		event.handle = ctx->handle;
		timer_timeout(ti, &event, sizeof event);
	}
	sprintf(ctx->tmp, "%d", session);
	return ctx->tmp;
}

static const char *_cmd_now(struct pixel *ctx, const char *cmd, const char *param) {
	uint32_t now = timer_now();
	sprintf(ctx->tmp, "%u", now);
	return ctx->tmp;
}

static const char *_cmd_starttime(struct pixel *ctx, const char *cmd, const char *param) {
	uint32_t starttime = timer_starttime();
	sprintf(ctx->tmp, "%u", starttime);
	return ctx->tmp;
}

static const char *_cmd_self(struct pixel *ctx, const char *cmd, const char *param) {
	sprintf(ctx->tmp, "%u", ctx->handle);
	return ctx->tmp;
}

static const char *_cmd_name(struct pixel *ctx, const char *cmd, const char *param) {
	int i;
	uint32_t handle;
	char name[strlen(param)+1];
	for (i=0; param[i]!=' '&&param[i]; i++) {
		name[i] = param[i];
	}
	if (param[i] == '\0') {
		return 0;
	}
	name[i] = '\0';
	param += i+1;
	handle = strtoul(param, 0, 0);
	handle_name(name, handle);
	return 0;
}

static const char *_cmd_query(struct pixel *ctx, const char *cmd, const char *param) {
	if (param && param[0] != '\0') {
		uint32_t handle = handle_name(param, 0);
		if (handle > 0) {
			sprintf(ctx->tmp, "%u", handle);
			return ctx->tmp;
		}
	}
	return 0;
}

static const char *_cmd_session(struct pixel *ctx, const char *cmd, const char *param) {
	int session = pixel_session(ctx);
	sprintf(ctx->tmp, "%d", session);
	return ctx->tmp;
}

static const char *_cmd_endless(struct pixel *ctx, const char *cmd, const char *param) {
	if (ctx->endless) {
		strcpy(ctx->tmp, "1");
		ctx->endless = 0;
		return ctx->tmp;
	}
	return 0;
}

static const char *_cmd_mqlen(struct pixel *ctx, const char *cmd, const char *param) {
	int len = queue_len(ctx->queue);
	sprintf(ctx->tmp, "%d", len);
	return ctx->tmp;
}

static const char *_cmd_logon(struct pixel *ctx, const char *cmd, const char *param) {
	uint32_t handle = ctx->handle;
	struct pixel *_ctx;
	if (param) {
		handle = strtoul(param, 0, 0);
		if (handle == 0) {
			pixel_log(ctx, "logon:%s failed\n", param);
			return 0;
		}
	}
	_ctx = handle_grab(handle);
	if (!_ctx) {
		return 0;
	}
	if (!_ctx->logfile) {
		FILE *f = log_open(ctx, handle);
		if (f) {
			if (!atom_cas(&_ctx->logfile, 0, f)) {
				fclose(f);
			}
		}
	}
	handle_release(handle);
	return 0;
}

static const char *_cmd_logoff(struct pixel *ctx, const char *cmd, const char *param) {
	uint32_t handle = ctx->handle;
	struct pixel *_ctx;
	FILE *f;
	if (param) {
		handle = strtoul(param, 0, 0);
		if (handle == 0) {
			pixel_log(ctx, "logoff:%s failed\n", param);
			return 0;
		}
	}
	_ctx = handle_grab(handle);
	if (!_ctx) {
		return 0;
	}
	f = _ctx->logfile;
	if (f) {
		if (atom_cas(&_ctx->logfile, f, 0)) {
			log_close(ctx, f, handle);
		}
	}
	handle_release(handle);
	return 0;
}

static const char *_cmd_setenv(struct pixel *ctx, const char *cmd, const char *param) {
	int i;
	char key[strlen(param)+1];
	for (i=0; param[i]!=' '&&param[i]; i++) {
		key[i] = param[i];
	}
	if (param[i] == '\0') {
		return 0;
	}
	key[i] = '\0';
	param += i+1;
	env_set(key, param);
	return 0;
}

static const char *_cmd_getenv(struct pixel *ctx, const char *cmd, const char *param) {
	return env_get(param);
}

static const char *_cmd_signal(struct pixel *ctx, const char *cmd, const char *param) {
	uint32_t handle = ctx->handle;
	int sig = 0;
	if (param) {
		handle = strtoul(param, 0, 0);
		if (handle == 0) {
			pixel_log(ctx, "signal:%s failed\n", param);
			return 0;
		}
	}
	ctx = handle_grab(handle);
	if (!ctx) {
		return 0;
	}
	param = strchr(param, ' ');
	if (param) {
		sig = strtol(param, 0, 0);
	}
	module_inst_signal(ctx->module, ctx->inst, sig);
	handle_release(handle);
	return 0;
}

static const char *_cmd_harbor(struct pixel *ctx, const char *cmd, const char *param) {
	harbor_start(ctx);
	return 0;
}

struct cmd_func {
	const char *name;
	const char *(*func)(struct pixel *ctx, const char *cmd , const char *param);
};

static struct cmd_func funcs[] = {
	{"KILL", _cmd_kill},
	{"LAUNCH", _cmd_launch},
	{"TIMEOUT", _cmd_timeout},
	{"ABORT", _cmd_abort},
	{"NOW", _cmd_now},
	{"SELF", _cmd_self},
	{"NAME", _cmd_name},
	{"QUERY", _cmd_query},
	{"HARBOR", _cmd_harbor},
	{"SESSION", _cmd_session},
	{"ENDLESS", _cmd_endless},
	{"STARTTIME", _cmd_starttime},
	{"MQLEN", _cmd_mqlen},
	{"LOGON", _cmd_logon},
	{"LOGOFF", _cmd_logoff},
	{"SETENV", _cmd_setenv},
	{"GETENV", _cmd_getenv},
	{"SIGNAL", _cmd_signal},
	{0, 0},
};

const char *pixel_command(struct pixel *ctx, const char *cmd, const char *param) {
	struct cmd_func *method = &funcs[0];
	while (method->name) {
		if (0 == strcmp(cmd, method->name)) {
			return method->func(ctx, cmd, param);
		}
		++method;
	}
	pixel_log(ctx, "not support cmd:%s\n", cmd);
	return 0;
}

#ifdef PIXEL_LUA

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static int lsend(lua_State *L) {
	struct pixel *ctx = (struct pixel *)lua_touserdata(L, lua_upvalueindex(1));
	uint32_t dest = (uint32_t)lua_tointeger(L, 1);
	uint32_t source = (uint32_t)lua_tointeger(L, 2);
	int type = (int)luaL_checkinteger(L, 3);
	int session = 0;
	int ltype;
	size_t size;
	void *data = 0;
	if (lua_isnil(L, 4)) {
		type |= PIXEL_TAG_ALLOCSESSION;
	} else {
		session = (int)luaL_checkinteger(L, 4);
	}
	ltype = lua_type(L, 5);
	switch (ltype) {
		case LUA_TSTRING:
			data = (void *)lua_tolstring(L, 5, &size);
			break;
		case LUA_TLIGHTUSERDATA:
			data = lua_touserdata(L, 5);
			size = (size_t)luaL_checkinteger(L, 6);
			type |= PIXEL_TAG_DONTCOPY;
			break;
		default:
			luaL_error(L, "pixel.send invalid param :%s", lua_typename(L, ltype));
			return 0;
	}
	session = pixel_send(ctx, source, dest, type, session, data, size);
	if (session < 0) {
		return 0;
	}
	lua_pushinteger(L, session);
	return 1;
}

static int lsession(lua_State *L) {
	struct pixel *ctx = (struct pixel *)lua_touserdata(L, lua_upvalueindex(1));
	int session = pixel_session(ctx);
	lua_pushinteger(L, session);
	return 1;
}

static int lcommand(lua_State *L) {
	struct pixel *ctx = (struct pixel *)lua_touserdata(L, lua_upvalueindex(1));
	const char *cmd = luaL_checkstring(L, 1);
	const char *ret;
	const char *pam = 0;
	if (lua_gettop(L) == 2) {
		pam = luaL_checkstring(L, 2);
	}
	ret = pixel_command(ctx, cmd, pam);
	if (ret) {
		lua_pushstring(L, ret);
		return 1;
	}
	return 0;
}

static int llog(lua_State *L) {
	struct pixel *ctx = (struct pixel *)lua_touserdata(L, lua_upvalueindex(1));
	pixel_log(ctx, "%s", luaL_checkstring(L, 1));
	return 0;
}

static int traceback(lua_State *L) {
	const char *err = lua_tostring(L, 1);
	if (err) {
		luaL_traceback(L, L, err, 1);
	} else {
		lua_pushliteral(L, "(no error message)");
	}
	return 1;
}

static int _cb(struct pixel *ctx, void *ud, int type, int session, uint32_t source, const void *data, size_t size) {
	lua_State *L = (lua_State *)ud;
	int r;
	int top = lua_gettop(L);
	if (top == 0) {
		lua_pushcfunction(L, traceback);
		lua_rawgetp(L, LUA_REGISTRYINDEX, _cb);
	} else {
		assert(top == 2);
	}
	lua_pushvalue(L, 2);
	lua_pushinteger(L, type);
	lua_pushlightuserdata(L, (void *)data);
	lua_pushinteger(L, size);
	lua_pushinteger(L, session);
	lua_pushinteger(L, source);
	r = lua_pcall(L, 5, 0, 1);
	if (r == LUA_OK) {
		return 0;
	}
	switch (r) {
		case LUA_ERRRUN:
			pixel_log(ctx, "LUA_ERRRUN :%s\n", lua_tostring(L, -1));
			break;
		case LUA_ERRMEM:
			pixel_log(ctx, "LUA_ERRMEM\n");
			break;
		case LUA_ERRERR:
			pixel_log(ctx, "LUA_ERRERR\n");
			break;
		case LUA_ERRGCMM:
			pixel_log(ctx, "LUA_ERRGCMM\n");
			break;
	}
	lua_pop(L, 1);
	return 0;
}

static int forward_cb(struct pixel *ctx, void *ud, int type, int session, uint32_t source, const void *data, size_t size) {
	_cb(ctx, ud, type, session, source, data, size);
	return 1;
}

static int lcallback(lua_State *L) {
	struct pixel *ctx = (struct pixel *)lua_touserdata(L, lua_upvalueindex(1));
	int forward = lua_toboolean(L, 2);
	lua_State *gL;
	luaL_checktype(L, 1, LUA_TFUNCTION);
	lua_settop(L, 1);
	lua_rawsetp(L, LUA_REGISTRYINDEX, _cb);
	lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
	gL = lua_tothread(L, -1);
	if (forward) {
		pixel_callback(ctx, gL, forward_cb);
	} else {
		pixel_callback(ctx, gL, _cb);
	}
	return 0;
}

static int ltostring(lua_State *L) {
	if (lua_isnoneornil(L, 1)) {
		return 0;
	} else {
		char *data = (char *)lua_touserdata(L, 1);
		int size = (int)luaL_checkinteger(L, 2);
		lua_pushlstring(L, data, size);
		return 1;
	}
}

static int ldrop(lua_State *L) {
	void *data = lua_touserdata(L, 1);
	pixel_alloc(data, 0);
	return 0;
}

static int lharbor(lua_State *L) {
	uint32_t handle = (uint32_t)lua_tointeger(L, 1);
	int ret = harbor_isremote(handle);
	int harbor = handle >> 24;
	lua_pushinteger(L, harbor);
	lua_pushboolean(L, ret);
	return 2;
}

int pixel_lua(lua_State *L) {
	luaL_Reg l[] = {
		{"send", lsend},
		{"session", lsession},
		{"command", lcommand},
		{"log", llog},
		{"callback", lcallback},
		{"tostring", ltostring},
		{"harbor", lharbor},
		{"drop", ldrop},
		{0, 0},
	};
	luaL_newlibtable(L, l);
	lua_getfield(L, LUA_REGISTRYINDEX, "pixel");
	if (!lua_touserdata(L, -1)) {
		return luaL_error(L, "init pixel first");
	}
	luaL_setfuncs(L, l, 1);
	return 1;
}

#endif // PIXEL_LUA
