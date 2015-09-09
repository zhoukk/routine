#ifndef _MONITOR_H_
#define _MONITOR_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

	struct monitor {
		int version;
		int check_version;
		uint32_t source;
		uint32_t destination;
	};
	void monitor_trigger(struct monitor *m, uint32_t source, uint32_t destination);
	void monitor_check(struct monitor *m);

#ifdef __cplusplus
};
#endif
#endif // _MONITOR_H_
