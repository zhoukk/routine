#include "harbor.h"
#include "pixel.h"
#include "queue.h"
#include "pixel_impl.h"

#include <assert.h>

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

int harbor_send(struct message *m) {
	uint32_t harbor = pixel_handle(H.hctx);
	return pixel_push(harbor, m);
}

int harbor_isremote(uint32_t handle) {
	int h;
	assert(H.harbor != ~0);
	h = (handle & ~0xffffff);
	return h != H.harbor && h != 0;
}
