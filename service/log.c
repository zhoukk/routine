#include "pixel.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct log {
	FILE *f;
};
static int _log(struct pixel *ctx, void *ud, int type, int session, uint32_t source, const void *data, size_t size) {
	struct log *log = (struct log *)ud;
	fprintf(log->f, "[%u] ",source);
	fwrite(data, size, 1, log->f);
	fflush(log->f);
	return 0;
}
void *log_new(void) {
	struct log *log = (struct log *)pixel_alloc(0, sizeof *log);
	log->f = 0;
	return log;
}
int log_init(struct log *log, struct pixel *ctx, const char *param) {
	if (param) {
		log->f = fopen(param, "w");
	} else {
		log->f = stdout;
	}
	if (log->f) {
		pixel_callback(ctx, log, _log);
		return 0;
	} else {
		return 1;
	}
}
void log_free(struct log *log) {
	if (log->f != stdout) {
		fclose(log->f);
	}
	pixel_alloc(log, 0);
}
