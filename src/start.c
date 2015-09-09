#include "pixel.h"
#include "pixel_impl.h"
#include "timer.h"
#include "socket.h"
#include "module.h"
#include "queue.h"
#include "handle.h"
#include "harbor.h"
#include "monitor.h"

#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct watcher {
	struct monitor *m;
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	int count;
	int sleep;
	int quit;	
};

struct worker_param {
	struct watcher *watcher;
	int id;
};

static void *_monitor(void *param) {
	struct watcher *watcher = (struct watcher *)param;
	int i;
	int n = watcher->count;
	for (;;) {
		if (pixel_total() == 0)
			break;
		for (i=0; i<n; i++)
			monitor_check(&watcher->m[i]);
		for (i=0; i<5; i++) {
			if (pixel_total() == 0)
				break;
			sleep(1);
		}
	}
	return 0;
}

static void *_timer(void *param) {
	struct watcher *watcher = (struct watcher *)param;
	int err;
	for (;;) {
		timer_update();
		if (pixel_total() == 0)
			break;
		if (watcher->sleep >= 1) {
			err = pthread_cond_signal(&watcher->cond);
			if (err)
				pixel_log(0, "pthread_cond_signal: %s\n", strerror(err));
		}
		usleep(2500);
	}
	socket_exit();
	pthread_mutex_lock(&watcher->mutex);
	watcher->quit = 1;
	pthread_cond_broadcast(&watcher->cond);
	pthread_mutex_unlock(&watcher->mutex);
	return 0;
}

static void *_socket(void *param) {
	struct watcher *watcher = (struct watcher *)param;
	for (;;) {
		int ret = socket_poll();
		if (ret == SOCKET_EXIT)
			break;
		if (watcher->sleep >= watcher->count) {
			int err = pthread_cond_signal(&watcher->cond);
			if (err)
				pixel_log(0, "pthread_cond_signal: %s\n", strerror(err));
		}
	}
	return 0;
}

static void *_worker(void *param) {
	struct worker_param *wp = (struct worker_param *)param;
	struct watcher *watcher = wp->watcher;
	int id = wp->id;
	struct queue *q = 0;
	while (!watcher->quit) {
		q = pixel_dispatch(q, &watcher->m[id]);
		if (!q) {
			if (pthread_mutex_lock(&watcher->mutex) == 0) {
				++watcher->sleep;
				if (!watcher->quit) {
					pthread_cond_wait(&watcher->cond, &watcher->mutex);
					--watcher->sleep;
					pthread_mutex_unlock(&watcher->mutex);
				}
			}
		}
	}
	return 0;
}

static int _start(int thread) {
	int i, err;
	pthread_t pid[thread+3];
	struct monitor m[thread];
	struct worker_param wp[thread];
	struct watcher watcher;
	watcher.count = thread;
	watcher.sleep = 0;
	watcher.quit = 0;
	memset(m, 0, thread*sizeof(struct monitor));
	watcher.m = m;
	err = pthread_mutex_init(&watcher.mutex, 0);
	if (err) {
		pixel_log(0, "pthread_mutex_init: %s\n", strerror(err));
		return -1;
	}
	err = pthread_cond_init(&watcher.cond, 0);
	if (err) {
		pixel_log(0, "pthread_cond_init: %s\n", strerror(err));
		return -1;
	}
	err = pthread_create(&pid[0], 0, _monitor, &watcher);
	if (err) {
		pixel_log(0, "pthread_create: %s\n", strerror(err));
		return -1;
	}
	err = pthread_create(&pid[1], 0, _timer, &watcher);
	if (err) {
		pixel_log(0, "pthread_create: %s\n", strerror(err));
		return -1;
	}
	err = pthread_create(&pid[2], 0, _socket, &watcher);
	if (err) {
		pixel_log(0, "pthread_create: %s\n", strerror(err));
		return -1;
	}
	for (i=0; i<thread; i++) {
		wp[i].watcher = &watcher;
		wp[i].id = i;
		err = pthread_create(&pid[i+3], 0, _worker, &wp[i]);
		if (err) {
			pixel_log(0, "pthread_create: %s\n", strerror(err));
			continue;
		}
	}
	for (i=0; i<thread+3; i++)
		pthread_join(pid[i], 0);
	pthread_mutex_destroy(&watcher.mutex);
	pthread_cond_destroy(&watcher.cond);
	return 0;
}

static int bootstrap(const char *bootstrap) {
	int size = strlen(bootstrap);
	char name[size+1];
	char param[size+1];
	strcpy(name, "");
	strcpy(param, "");
	sscanf(bootstrap, "%s %s", name, param);
	if (!pixel_new(name, param)) {
		pixel_log(0, "bootstrap [%s] failed\n", bootstrap);
		return -1;
	}
	return 0;
}

void pixel_start(struct pixel_config *cfg) {
	struct pixel *log;
	timer_init(pixel_timer_dispatch, pixel_alloc);
	queue_init();
	module_init(cfg->module_path);
	socket_init(pixel_socket_dispatch, pixel_alloc);
	handle_init(cfg->harbor);
	harbor_init(cfg->harbor);
	log = pixel_new("log", cfg->logfile);
	if (!log) {
		pixel_log(0, "can not launch log server\n");
		exit(0);
	}
	pixel_setlog(log);
	if (bootstrap(cfg->bootstrap))
		goto failed;
	if (_start(cfg->thread))
		goto failed;
	return;
failed:
	pixel_dispatchall(log);
	exit(0);
}
