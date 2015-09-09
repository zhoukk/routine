#include "queue.h"
#include "pixel.h"
#include "lock.h"

#include <assert.h>

#define QUEUE_SIZE 64
#define QUEUE_OVERLOAD 1024

struct queue {
	uint32_t handle;
	int cap;
	int head;
	int tail;
	int global;
	int release;
	int overload;
	int overload_threshold;
	struct spinlock lock;
	struct message *mqueue;
	struct queue *next;
};

struct queue_global {
	struct queue *head;
	struct queue *tail;
	struct spinlock lock;
};

static struct queue_global Q;

void queue_init(void) {
	Q.head = Q.tail = 0;
	spinlock_init(&Q.lock);
}

void queue_unit(void) {
	spinlock_unit(&Q.lock);
}

void queue_push_global(struct queue *q) {
	spinlock_lock(&Q.lock);
	if (Q.tail)	{
		Q.tail->next = q;
		Q.tail = q;
	} else {
		Q.head = Q.tail = q;
	}
	spinlock_unlock(&Q.lock);
}

struct queue *queue_pop_global(void) {
	struct queue *q;
	spinlock_lock(&Q.lock);
	q = Q.head;
	if (q) {
		Q.head = q->next;
		if (Q.head == 0) {
			Q.tail = 0;
		}
		q->next = 0;
	}
	spinlock_unlock(&Q.lock);
	return q;
}

static void _queue_expand(struct queue *q) {
	int i;
	struct message *newq = (struct message *)pixel_alloc(0, sizeof(struct message) * q->cap * 2);
	for (i=0; i<q->cap; i++) {
		newq[i] = q->mqueue[(q->head+i)%q->cap];
	}
	q->head = 0;
	q->tail = q->cap;
	q->cap *= 2;
	pixel_alloc(q->mqueue, 0);
	q->mqueue = newq;
}

void queue_push(struct queue *q, struct message *m) {
	spinlock_lock(&q->lock);
	q->mqueue[q->tail] = *m;
	if (++q->tail >= q->cap) {
		q->tail = 0;
	}
	if (q->head == q->tail) {
		_queue_expand(q);
	}
	if (q->global == 0) {
		q->global = 1;
		queue_push_global(q);
	}
	spinlock_unlock(&q->lock);
}

int queue_pop(struct queue *q, struct message *m) {
	int ret = 1;
	spinlock_lock(&q->lock);
	if (q->head != q->tail) {
		int len;
		ret = 0;
		*m = q->mqueue[q->head++];
		if (q->head >= q->cap) {
			q->head = 0;
		}
		len = q->tail - q->head;
		if (len < 0) {
			len += q->cap;
		}
		while (len > q->overload_threshold) {
			q->overload = len;
			q->overload_threshold *= 2;
		}
	} else {
		q->overload_threshold = QUEUE_OVERLOAD;
		q->global = 0;
	}
	spinlock_unlock(&q->lock);
	return ret;
}

struct queue *queue_new(uint32_t handle) {
	struct queue *q;
	q = (struct queue *)pixel_alloc(0, sizeof *q);
	q->handle = handle;
	q->cap = QUEUE_SIZE;
	q->global = 1;
	q->overload_threshold = QUEUE_OVERLOAD;
	q->mqueue = (struct message *)pixel_alloc(0, sizeof(struct message) * q->cap);
	return q;
}

static void _d_drop(struct message *m, void *ud) {
	if (m->data) {
		pixel_alloc(m->data, 0);
	}
}

static void _queue_drop(struct queue *q, void (*drop)(struct message *, void *), void *ud) {
	struct message m;
	if (!drop) {
		drop = _d_drop;
	}
	while (!queue_pop(q, &m)) {
		drop(&m, ud);
	}
}

void queue_free(struct queue *q, void (*drop)(struct message *, void *), void *ud) {
	spinlock_lock(&q->lock);
	if (q->release) {
		spinlock_unlock(&q->lock);
		_queue_drop(q, drop, ud);
		pixel_alloc(q->mqueue, 0);
		pixel_alloc(q, 0);
	} else {
		queue_push_global(q);
		spinlock_unlock(&q->lock);
	}
}

void queue_mark_free(struct queue *q) {
	spinlock_lock(&q->lock);
	assert(q->release == 0);
	q->release = 1;
	if (q->global == 0) {
		queue_push_global(q);
	}
	spinlock_unlock(&q->lock);
}

uint32_t queue_handle(struct queue *q) {
	return q->handle;
}

int queue_len(struct queue *q) {
	int head, tail, cap;
	spinlock_lock(&q->lock);
	head = q->head;
	tail = q->tail;
	cap = q->cap;
	spinlock_unlock(&q->lock);
	if (head <= tail) {
		return tail - head;
	}
	return tail + cap - head;
}

int queue_overload(struct queue *q) {
	if (q->overload) {
		int overload = q->overload;
		q->overload = 0;
		return overload;
	}
	return 0;
}
