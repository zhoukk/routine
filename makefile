
BUILD ?= .

CFLAGS := -g -Wall -DPIXEL_LUA -DLUA_USE_DLOPEN -DLUA_USE_POSIX -I/usr/local/include
LIBS := -ldl -lrt -lpthread -lm -llua
LDFLAGS :=
SHARED := -fPIC --shared
EXPORT := -Wl,-E -Wl,-rpath,/usr/local/lib

SRC = \
	lserial.c \
	epoll.c \
	env.c \
	monitor.c \
	harbor.c \
	handle.c \
	log.c \
	main.c \
	start.c \
	module.c \
	queue.c \
	pixel.c \
	socket.c \
	timer.c

all : $(BUILD)/pixel log.so lua.so socket.so crypt.so netpack.so sharedata.so multicast.so sproto.so lpeg.so stm.so clientsocket.so

$(BUILD)/pixel : $(foreach v, $(SRC), src/$(v))
		$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(EXPORT) $(LIBS)

log.so : service/log.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

lua.so : service/lua.c service/lalloc.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

crypt.so : lualib/lcrypt.c lualib/lsha1.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

socket.so : lualib/lsocket.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

netpack.so : lualib/lnetpack.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

sharedata.so : lualib/lsharedata.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

multicast.so : lualib/lmulticast.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

sproto.so : lualib/sproto/lsproto.c lualib/sproto/sproto.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Ilualib/sproto

stm.so : lualib/lstm.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

clientsocket.so : lualib/lclientsocket.c
		$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Isrc

lpeg.so :
		cd 3rd/lpeg-0.12.2 && $(MAKE) CC=$(CC) && cp ./lpeg.so ../../

clean:
	rm -f $(BUILD)/pixel log.so lua.so socket.so crypt.so netpack.so sharedata.so multicast.so sproto.so lpeg.so stm.so clientsocket.so
