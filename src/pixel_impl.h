#ifndef _PIXEL_IMPL_H_
#define _PIXEL_IMPL_H_

#ifdef __cplusplus
extern "C" {
#endif

	struct message;
	struct pixel;
	struct socket_message;
	struct monitor;

	struct pixel_config {
		int thread;
		int harbor;
		const char *module_path;
		const char *logfile;
		const char *bootstrap;
	};

	void pixel_init(void);
	void pixel_unit(void);
	void pixel_start(struct pixel_config *cfg);
	struct pixel *pixel_new(const char *name, const char *param);
	void pixel_free(struct pixel *ctx);
	void pixel_exit(void);
	uint32_t pixel_handle(struct pixel *ctx);
	void pixel_reserve(struct pixel *ctx);
	void pixel_force_free(struct pixel *ctx);
	int pixel_push(uint32_t handle, struct message *m);
	struct queue *pixel_dispatch(struct queue *q, struct monitor *monitor);
	void pixel_setlog(struct pixel *ctx);
	int pixel_total(void);
	void pixel_endless(uint32_t handle);
	int pixel_session(struct pixel *ctx);
	void pixel_dispatchall(struct pixel *ctx);
	void pixel_timer_dispatch(void *);
	void pixel_socket_dispatch(struct socket_message *);

#ifdef __cplusplus
};
#endif

#endif // _PIXEL_IMPL_H_
