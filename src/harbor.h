#ifndef _HARBOR_H_
#define _HARBOR_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

	struct pixel;
	struct message;
	void harbor_init(int harbor);
	void harbor_unit(void);
	void harbor_start(struct pixel *ctx);
	int harbor_send(uint32_t dest, struct message *m_);
	int harbor_isremote(uint32_t handle);

#ifdef __cplusplus
};
#endif

#endif // _HARBOR_H_
