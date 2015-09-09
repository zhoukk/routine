#include "monitor.h"
#include "pixel.h"
#include "lock.h"
#include "pixel_impl.h"

void monitor_trigger(struct monitor *m, uint32_t source, uint32_t destination) {
	m->source = source;
	m->destination = destination;
	atom_inc(&m->version);
}

void monitor_check(struct monitor *m) {
	if (m->version == m->check_version) {
		if (m->destination) {
			pixel_endless(m->destination);
			pixel_log(0, "message from [%u] to [%u] maybe in endless loop (version=%d)\n", m->source, m->destination, m->version);
		}
	} else {
		m->check_version = m->version;
	}
}
