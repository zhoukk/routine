#include "handle.h"
#include "pixel.h"
#include "pixel_impl.h"
#include "lock.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct handle_slot {
	uint32_t handle;
	int ref;
	struct pixel *ctx;
};

struct handle_name {
	char *name;
	uint32_t handle;
};

struct handle_global {
	uint32_t last_id;
	struct rwlock lock;
	uint32_t harbor;
	int cap;
	int n;
	struct handle_slot *slot;
	int name_cap;
	int name_count;
	struct handle_name *names;
};

static struct handle_global H;

void handle_init(int harbor) {
	H.last_id = 0;
	rwlock_init(&H.lock);
	H.cap = 16;
	H.n = 0;
	H.slot = (struct handle_slot *)pixel_alloc(0, H.cap * sizeof(*H.slot));
	H.harbor = (uint32_t)(harbor & 0xff) << 24;
	H.name_cap = 16;
	H.name_count = 0;
	H.names = (struct handle_name *)pixel_alloc(0, H.name_cap * sizeof(struct handle_name));
}

void handle_unit(void) {
	int i;
	pixel_alloc(H.slot, 0);
	rwlock_wlock(&H.lock);
	for (i=0; i<H.name_count; i++) {
		pixel_alloc(H.names[i].name, 0);
	}
	rwlock_wunlock(&H.lock);
	pixel_alloc(H.names, 0);
	rwlock_unit(&H.lock);
}

static int handle_expand() {
	int i, cap = H.cap;
	struct handle_slot *newslot;
	newslot = (struct handle_slot *)pixel_alloc(0, cap*2*sizeof(*newslot));
	if (!newslot) {
		return -1;
	}
	for (i=0; i<cap; i++) {
		struct handle_slot *os = &H.slot[i];
		struct handle_slot *ns = &newslot[os->handle&(cap*2-1)];
		*ns = *os;
	}
	free(H.slot);
	H.slot = newslot;
	H.cap = cap*2;
	return 0;
}

uint32_t handle_regist(struct pixel *ctx) {
	int i;
	rwlock_wlock(&H.lock);
	if (H.n >= H.cap * 3 / 4) {
		if (handle_expand()) {
			rwlock_wunlock(&H.lock);
			return 0;
		}
	}
	for (i=0; ;i++) {
		struct handle_slot *slot;
		uint32_t handle = ++H.last_id;
		if (handle == 0) {
			handle = ++H.last_id;
		}
		slot = &H.slot[handle&(H.cap-1)];
		if (slot->handle) {
			continue;
		}
		slot->handle = handle;
		slot->ref = 1;
		slot->ctx = ctx;
		++H.n;
		rwlock_wunlock(&H.lock);
		return handle | H.harbor;
	}
}

struct pixel *handle_grab(uint32_t handle) {
	struct handle_slot *slot;
	struct pixel *ctx;
	handle &= 0xffffff;
	rwlock_rlock(&H.lock);
	slot = &H.slot[handle&(H.cap-1)];
	if (slot->handle != handle) {
		rwlock_runlock(&H.lock);
		return 0;
	}
	ctx = slot->ctx;
	__sync_add_and_fetch(&slot->ref, 1);
	rwlock_runlock(&H.lock);
	return ctx;
}

static struct pixel *handle_release_ref(uint32_t handle) {
	struct handle_slot *slot;
	struct pixel *ctx = 0;
	rwlock_rlock(&H.lock);
	slot = &H.slot[handle&(H.cap-1)];
	if (slot->handle != handle) {
		rwlock_runlock(&H.lock);
		return 0;
	}
	if (__sync_sub_and_fetch(&slot->ref, 1) > 0) {
		ctx = slot->ctx;
	}
	rwlock_runlock(&H.lock);
	return ctx;
}

static struct pixel *handle_remove(uint32_t handle) {
	struct handle_slot *slot;
	struct pixel *ctx;
	rwlock_wlock(&H.lock);
	slot = &H.slot[handle&(H.cap-1)];
	if (slot->handle != handle) {
		rwlock_wunlock(&H.lock);
		return 0;
	}
	if (slot->ref > 0) {
		rwlock_wunlock(&H.lock);
		return 0;
	}
	ctx = slot->ctx;
	slot->handle = 0;
	--H.n;
	rwlock_wunlock(&H.lock);
	return ctx;
}

struct pixel *handle_release(uint32_t handle) {
	handle &= 0xffffff;
	struct pixel *ctx = handle_release_ref(handle);
	if (!ctx) {
		ctx = handle_remove(handle);
		pixel_free(ctx);
		return 0;
	} else {
		return ctx;
	}
}

void handle_exit(void) {
	int i, n=0;
	rwlock_wlock(&H.lock);
	uint32_t handles[H.cap];
	for (i=0; i<H.cap; i++) {
		if (H.slot[i].handle) {
			handles[n++] = H.slot[i].handle;
		}
	}
	rwlock_wunlock(&H.lock);
	for (i=0; i<n; i++) {
		handle_release(handles[i]);
	}
}

uint32_t _query(const char *name) {
	uint32_t handle = 0;
	int beg = 0;
	int end;
	rwlock_rlock(&H.lock);
	end = H.name_count-1;
	while (beg <= end) {
		int mid = (beg+end)/2;
		struct handle_name *node = &H.names[mid];
		int c = strcmp(node->name, name);
		if (c == 0)	{
			handle = node->handle;
			break;
		}
		if (c < 0) {
			beg = mid+1;
		} else {
			end = mid-1;
		}		
	}
	rwlock_runlock(&H.lock);
	return handle;
}

static void _insert_before(char *name, uint32_t handle, int pos) {
	if (H.name_count >= H.name_cap) {
		int i;
		struct handle_name *n;
		H.name_cap *= 2;
		n = (struct handle_name *)pixel_alloc(0, H.name_cap*sizeof(struct handle_name));
		for (i=0; i<pos; i++) {
			n[i] = H.names[i];
		}
		for (i=pos; i<H.name_count; i++) {
			n[i+1] = H.names[i];
		}
		pixel_alloc(H.names, 0);
		H.names = n;		
	} else {
		int i;
		for (i=H.name_count; i>pos; i--) {
			H.names[i] = H.names[i-1];
		}
	}
	H.names[pos].name = name;
	H.names[pos].handle = handle;
	H.name_count++;
}

static uint32_t _insert(const char *name, uint32_t handle) {
	int beg = 0;
	int end;
	char *_name;
	rwlock_wlock(&H.lock);
	end = H.name_count-1;
	while (beg <= end) {
		int  mid = (beg+end)/2;
		struct handle_name *node = &H.names[mid];
		int c = strcmp(node->name, name);
		if (c == 0)	{
			rwlock_wunlock(&H.lock);
			return 0;
		}
		if (c < 0) {
			beg = mid+1;
		} else {
			end = mid-1;
		}		
	}
	_name = (char *)pixel_alloc(0, strlen(name)+1);
	strcpy(_name, name);
	_insert_before(_name, handle, beg);
	rwlock_wunlock(&H.lock);
	return handle;
}

uint32_t handle_name(const char *name, uint32_t handle) {
	if (handle == 0) {
		return _query(name);
	} else {
		return _insert(name, handle);
	}
}
