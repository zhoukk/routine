#include "log.h"
#include "timer.h"
#include "socket.h"
#include "pixel.h"
#include "dump.h"

#include <time.h>

FILE *log_open(struct pixel *ctx, uint32_t handle) {
	char tmp[128];
	FILE *f;
	sprintf(tmp, "%u.log", handle);
	f = fopen(tmp, "ab");
	if (f) {
		uint32_t starttime = timer_starttime();
		uint32_t curtime = timer_now();
		time_t ti = starttime + curtime/100;
		pixel_log(ctx, "open log file %s\n", tmp);
		fprintf(f, "open time:%u %s", curtime, ctime(&ti));
		fflush(f);
	} else {
		pixel_log(ctx, "open log file %s failed\n", tmp);
	}
	return f;
}

void log_close(struct pixel *ctx, FILE *f, uint32_t handle) {
	pixel_log(ctx, "close log file %u\n", handle);
	fprintf(f, "close time:%u\n", timer_now());
	fclose(f);
}

static void print(void *ud, const char *line) {
	fprintf((FILE *)ud, "%s", line);
}

static void log_blob(FILE *f, void *data, size_t size) {
	dump((const unsigned char *)data, size, print, (void *)f);
}

static void log_socket(FILE *f, void *data, int size) {
	struct socket_message *m = (struct socket_message *)data;
	if (m->type == SOCKET_DATA) {
		fprintf(f, "[socket] %d %d %d\n", m->id, m->type, m->size);
		log_blob(f, m->data, m->size);
		fprintf(f, "\n");
		fflush(f);
	}
}

void log_output(FILE *f, uint32_t source, int type, int session, void *data, size_t size) {
	if (type == PIXEL_SOCKET) {
		log_socket(f, data, size);
	} else {
		uint32_t ti = timer_now();
		fprintf(f, "[%u] %d %d %u\n", source, type, session, ti);
		log_blob(f, data, size);
		fprintf(f, "\n");
		fflush(f);
	}
}
