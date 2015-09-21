#include "harbor.h"
#include "pixel.h"
#include "queue.h"
#include "pixel_impl.h"

#include <stdio.h>
#include <string.h>
#include <assert.h>

struct remote_message {
	struct message msg;
	uint32_t dest;
};

struct harbor {
	struct pixel *hctx;
	uint32_t harbor;
};

static struct harbor H = {0, ~0};

void harbor_init(int harbor) {
	H.hctx = 0;
	H.harbor = (uint32_t)(harbor & 0xff) << 24;
}

void harbor_unit(void) {
	if (H.hctx) {
		pixel_force_free(H.hctx);
	}
}

void harbor_start(struct pixel *ctx) {
	H.hctx = ctx;
	pixel_reserve(ctx);
}

int harbor_send(uint32_t dest, struct message *m) {
	uint32_t harbor = pixel_handle(H.hctx);
	struct message rm;
	rm.source = dest;
	rm.session = m->session;
	rm.data = pixel_alloc(0, sizeof *m);
	rm.size = sizeof *m;
	memcpy(rm.data, m, rm.size);
	rm.size |= (size_t)PIXEL_HARBOR << MSG_TYPE_SHIFT;
	return pixel_push(harbor, &rm);
}

int harbor_isremote(uint32_t handle) {
	int h;
	assert(H.harbor != ~0);
	h = (handle & ~0xffffff);
	return h != H.harbor && h != 0;
}