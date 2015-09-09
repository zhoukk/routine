#include "module.h"
#include "pixel.h"
#include "lock.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <dlfcn.h>

#define MODULE_SIZE 64

typedef void *(*module_dl_new)(void);
typedef int (*module_dl_init)(void *, void *, const char *param);
typedef void (*module_dl_free)(void *);
typedef void (*module_dl_signal)(void *, int);

struct module {
	const char *name;
	void *dl;
	module_dl_new dl_new;
	module_dl_init dl_init;
	module_dl_free dl_free;
	module_dl_signal dl_signal;
};

struct module_global {
	const char *path;
	struct module modules[MODULE_SIZE];
	int count;
	struct spinlock lock;
};

static struct module_global M;

void module_init(const char *path) {
	char *_path;
	memset(&M, 0, sizeof M);
	_path = (char *)pixel_alloc(0, strlen(path)+1);
	strcpy(_path, path);
	M.path = _path;
	M.count = 0;
	spinlock_init(&M.lock);
}

static void _module_free(struct module *module) {
	pixel_alloc((void *)module->name, 0);
	if (dlclose(module->dl))
		pixel_log(0, "dlclose: %s\n", dlerror());
}

void module_unit(void) {
	int i;
	for (i=0;i<M.count;i++) {
		struct module *module = &M.modules[i];
		_module_free(module);
	}
	pixel_alloc((void *)M.path, 0);
	spinlock_unit(&M.lock);
}

static void *_module_open(const char *name) {
	char *p;
	void *dl = 0;
	char tmp[256] = {0};
	p = (char *)M.path;
	do {
		char *l, *s;
		int size;
		while (*p == ';') p++;
		if (*p == '\0') break;
		s = strchr(p, ';');
		if (!s)
			size = strlen(p);
		else
			size = s - p;
		l = strchr(p, '?');
		if (!l)	{
			pixel_log(0, "invalid module path:%s\n", M.path);
			exit(1);
		}
		strncpy(tmp, p, l-p);
		strcat(tmp, name);
		strncat(tmp, l+1, size-(l-p)-1);
		dl = dlopen(tmp, RTLD_NOW | RTLD_GLOBAL);
		if (s) p = s;
		else break;
	} while (!dl);
	if (!dl) {
		pixel_log(0, "dlopen: %s\n", dlerror());
	}
	return dl;
}

static int _module_sym(struct module *module) {
	int size = strlen(module->name);
	char tmp[size + 8];
	sprintf(tmp, "%s_new", module->name);
	module->dl_new = (module_dl_new)dlsym(module->dl, tmp);
	sprintf(tmp, "%s_init", module->name);
	module->dl_init = (module_dl_init)dlsym(module->dl, tmp);
	sprintf(tmp, "%s_free", module->name);
	module->dl_free = (module_dl_free)dlsym(module->dl, tmp);
	sprintf(tmp, "%s_signal", module->name);
	module->dl_signal = (module_dl_signal)dlsym(module->dl, tmp);
	if (!module->dl_init) {
		pixel_log(0, "dlsym: %s\n", dlerror());
		return -1;
	}
	return 0;
}

static struct module *_query(const char *name) {
	int i;
	for (i=0; i<M.count; i++) {
		if (strcmp(M.modules[i].name, name) == 0)
			return &M.modules[i];
	}
	return 0;
}

struct module *module_query(const char *name) {
	struct module *module = _query(name);
	if (module) return module;
	spinlock_lock(&M.lock);
	module = _query(name);
	if (!module && M.count < MODULE_SIZE) {
		void *dl = _module_open(name);
		if (dl) {
			module = &M.modules[M.count];
			module->name = (char *)name;
			module->dl = dl;
			if (_module_sym(module) == 0) {
				char *_name = (char *)pixel_alloc(0, strlen(name)+1);
				strcpy(_name, name);
				module->name = _name;
				M.count++;
			} else {
				module = 0;
			}
		}
	}
	spinlock_unlock(&M.lock);
	return module;
}

void *module_inst_new(struct module *module) {
	void *inst;
	if (module->dl_new)
		inst = module->dl_new();
	else
		inst = (void *)(~0);
	return inst;
}

int module_inst_init(struct module *module, void *inst, void *ud, const char *param) {
	return module->dl_init(inst, ud, param);
}

void module_inst_free(struct module *module, void *inst) {
	if (module->dl_free)
		module->dl_free(inst);
}

void module_inst_signal(struct module *module, void *inst, int signal) {
	if (module->dl_signal)
		module->dl_signal(inst, signal);
}