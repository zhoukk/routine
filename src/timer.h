#ifndef _TIMER_H_
#define _TIMER_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

	typedef void (*timer_dispatch)(void *);
	typedef void *(*timer_alloc)(void *, int);
	void timer_init(timer_dispatch, timer_alloc);
	void timer_unit(void);
	void timer_timeout(int time, void *ud, int size);
	void timer_update(void);
	uint32_t timer_starttime(void);
	uint32_t timer_now(void);
	
#ifdef __cplusplus
};
#endif
#endif // _TIMER_H_
