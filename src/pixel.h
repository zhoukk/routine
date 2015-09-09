#ifndef _PIXEL_H_
#define _PIXEL_H_

#include <stdint.h>
#include <stddef.h>

#define PIXEL_TEXT 0
#define PIXEL_RESPONSE 1
#define PIXEL_MULTICAST 2
#define PIXEL_CLIENT 3
#define PIXEL_SYSTEM 4
#define PIXEL_HARBOR 5
#define PIXEL_SOCKET 6
#define PIXEL_ERROR 7
#define PIXEL_RESERVED_QUEUE 8
#define PIXEL_RESERVED_DEBUG 9
#define PIXEL_RESERVED_LUA 10
#define PIXEL_RESERVED_SNAX 11

#define PIXEL_TAG_DONTCOPY 0x10000
#define PIXEL_TAG_ALLOCSESSION 0x20000

#ifdef __cplusplus
extern "C" {
#endif

	struct pixel;
	typedef int (*pixel_cb)(struct pixel *ctx, void *ud, int type, int session, uint32_t source, const void *data, size_t size);
	void *pixel_alloc(void *p, int size);
	void pixel_log(struct pixel *ctx, const char *fmt, ...);
	const char *pixel_command(struct pixel *ctx, const char *cmd, const char *param);
	int pixel_send(struct pixel *ctx, uint32_t source, uint32_t destination, int type, int session, void *data, size_t size);
	void pixel_callback(struct pixel *ctx, void *ud, pixel_cb cb);

#ifdef PIXEL_LUA
#include "lua.h"
	int pixel_lua(lua_State *L);
	int pixel_serial(lua_State *L);
#endif // PIXEL_LUA

#ifdef __cplusplus
};
#endif

#endif // _PIXEL_H_
