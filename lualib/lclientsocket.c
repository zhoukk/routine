#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>

#include "lua.h"
#include "lauxlib.h"

static int lconnect(lua_State *L) {
	struct sockaddr_in addr;
	const char *host = luaL_checkstring(L, 1);
	int port = (int)luaL_checkinteger(L, 2);
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	addr.sin_addr.s_addr = inet_addr(host);
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	if (-1 == connect(fd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in))) {
		lua_pushnil(L);
		return 1;
	}
	int flag = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, flag|O_NONBLOCK);
	lua_pushinteger(L, fd);
	return 1;
}

static int lclose(lua_State *L) {
	int fd = (int)luaL_checkinteger(L, 1);
	close(fd);
	return 0;
}

static int lwrite(lua_State *L) {
	size_t size;
	int fd = (int)luaL_checkinteger(L, 1);
	const char *buffer = luaL_checklstring(L, 2, &size);
	while (size > 0) {
		int r = send(fd, buffer, size, 0);
		if (r < 0) {
			if (errno == EAGAIN || errno == EINTR) {
				continue;
			}
			return luaL_error(L, strerror(errno));
		}
		buffer += r;
		size -= r;
	}
	return 0;
}

static int lread(lua_State *L) {
	int fd = (int)luaL_checkinteger(L, 1);
	char buffer[1024];
	int r = recv(fd, buffer, 1024, 0);
	if (r == 0) {
		lua_pushstring(L, "");
		return 1;
	}
	if (r < 0) {
		if (errno == EAGAIN || errno == EINTR) {
			return 0;
		}
		return luaL_error(L, strerror(errno));
	}
	lua_pushlstring(L, buffer, r);
	return 1;
}

int luaopen_clientsocket_c(lua_State *L) {
	luaL_Reg l[] = {
		{"connect", lconnect},
		{"close", lclose},
		{"write", lwrite},
		{"read", lread},
		{0, 0},
	};
	luaL_newlib(L, l);
	return 1;
}
