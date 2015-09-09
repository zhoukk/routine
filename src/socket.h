/*
socket.h

socket library

example:

	static void *my_alloc(void *ud, int size) {
		if (size > 0) {
			void *p = malloc(size);
			memset(p, 0, size);
			return p;
		} else
			free(ud);
		return 0;
	}

	void _dispatch(struct socket_message *sm) {
		switch (sm->type) {
		case SOCKET_ACCEPT:
			printf("new fd:%d from:%s\n", sm->size, sm->data);
			socket_start(sm->size, 0);
			break;
		case SOCKET_OPEN:
			printf("fd:%d open %s\n", sm->id, (char *)sm->data);
			if (strcmp(sm->data, "start")) {
				int size = 1024 * 1024 * 3;
				void *data = malloc(size);
				memset(data, 1, size);
				socket_send(sm->id, data, size, SOCKET_PRIORITY_HIGH);
			}
			break;
		case SOCKET_DATA:
			printf("data size :%d from %d\n", sm->size, sm->id);
			socket_send(sm->id, sm->data, sm->size, SOCKET_PRIORITY_HIGH);
			break;
		case SOCKET_CLOSE:
			printf("close:%d\n", sm->id);
			break;
		case SOCKET_ERR:
			printf("error:%d\n", sm->id);
			break;
		case SOCKET_WARNING:
			printf("warning:%d\n", sm->id);
			socket_exit();
			break;
		}
	}

	int main(int argc, char *argv[]) {
		socket_init(_dispatch, my_alloc);

		int listen = socket_listen("0.0.0.0", 80, 0);
		socket_start(listen, 0);
		socket_open("127.0.0.1", 80, 0);
		while (socket_poll() != SOCKET_EXIT);
		socket_unit();
		return 0;
	}


*/

#ifndef _SOCKET_H_
#define _SOCKET_H_

#define SOCKET_EXIT 0
#define SOCKET_CLOSE 1
#define SOCKET_OPEN 2
#define SOCKET_DATA 3
#define SOCKET_ACCEPT 4
#define SOCKET_ERR 5
#define SOCKET_UDP 6
#define SOCKET_WARNING 7

#define SOCKET_PRIORITY_HIGH 0
#define SOCKET_PRIORITY_LOW 1

#ifdef __cplusplus
extern "C" {
#endif

	struct socket_message {
		int type;
		int id;
		void *ud;
		char *data;
		int size;
	};

	typedef void(*socket_dispatch)(struct socket_message *m);
	typedef void *(*socket_alloc)(void *, int size);

	int socket_init(socket_dispatch, socket_alloc);
	void socket_unit(void);

	void socket_exit(void);
	void socket_start(int id, void *ud);
	void socket_close(int id, void *ud);
	void socket_nodelay(int id);
	int socket_open(const char *host, int port, void *ud);
	int socket_listen(const char *host, int port, void *ud);
	int socket_bind(int fd, void *ud);
	long socket_send(int id, const void *data, int size, int priority);
	int socket_poll(void);

	struct socket_udp_address;
	int socket_udp(const char *host, int port, void *ud);
	int socket_udpopen(int id, const char *host, int port);
	long socket_udpsend(int id, const struct socket_udp_address *addr, const void *data, int size);
	const struct socket_udp_address *socket_udpaddress(struct socket_message *m, int *address_size);

	struct socket_object_interface {
		void *(*data)(void *);
		int(*size)(void *);
		void(*free)(void *);
	};
	void socket_object(struct socket_object_interface *soi);

#ifdef __cplusplus
};
#endif

#endif // _SOCKET_H_
