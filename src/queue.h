#ifndef _QUEUE_H_
#define _QUEUE_H_

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MSG_TYPE_MASK (SIZE_MAX >> 8)
#define MSG_TYPE_SHIFT ((sizeof(size_t)-1) * 8)

	struct message {
		uint32_t source;
		int session;
		void *data;
		size_t size;
	};
	
	struct queue;
	void queue_init(void);
	void queue_unit(void);
	void queue_push_global(struct queue *q);
	struct queue *queue_pop_global(void);
	void queue_push(struct queue *q, struct message *m);
	int queue_pop(struct queue *q, struct message *m);
	struct queue *queue_new(uint32_t handle);
	void queue_free(struct queue *q, void (*drop)(struct message *, void *), void *ud);
	void queue_mark_free(struct queue *q);
	uint32_t queue_handle(struct queue *q);
	int queue_len(struct queue *q);
	int queue_overload(struct queue *q);

#ifdef __cplusplus
};
#endif

#endif // _QUEUE_H_
