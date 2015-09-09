#ifndef _EVENT_H_
#define _EVENT_H_

#ifdef __cplusplus
extern "C" {
#endif

	struct event {
		int read;
		int write;
		void *ud;
	};

	struct pollfd;
	struct pollfd *event_new(void);
	void event_free(struct pollfd *pfd);
	int event_add(struct pollfd *pfd, int fd, void *ud);
	void event_del(struct pollfd *pfd, int fd);
	void event_write(struct pollfd *pfd, int fd, void *ud, int enable);
	int event_wait(struct pollfd *pfd, struct event *e, int maxev);

#ifdef __cplusplus
};
#endif

#endif // _EVENT_H_
