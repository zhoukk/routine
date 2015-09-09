#ifndef _HANDLE_H_
#define _HANDLE_H_

#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

	struct pixel;
	void handle_init(int harbor);
	void handle_unit(void);
	uint32_t handle_regist(struct pixel *ctx);
	struct pixel *handle_grab(uint32_t handle);
	struct pixel *handle_release(uint32_t handle);
	uint32_t handle_name(const char *name, uint32_t handle);
	void handle_exit(void);
	
#ifdef __cplusplus
}
#endif
#endif // _HANDLE_H_
