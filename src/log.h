#ifndef _LOG_H_
#define _LOG_H_

#include <stdint.h>
#include <stdio.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

	struct pixel;
	FILE *log_open(struct pixel *ctx, uint32_t handle);
	void log_close(struct pixel *ctx, FILE *f, uint32_t handle);
	void log_output(FILE *f, uint32_t source, int type, int session, void *data, size_t size);

#ifdef __cplusplus
};
#endif

#endif // _LOG_H_
