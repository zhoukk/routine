#ifndef _MODULE_H_
#define _MODULE_H_

#ifdef __cplusplus
extern "C" {
#endif

	struct module;
	void module_init(const char *path);
	void module_unit(void);
	struct module *module_query(const char *name);
	void *module_inst_new(struct module *mod);
	int module_inst_init(struct module *mod, void *inst, void *ud, const char *param);
	void module_inst_free(struct module *mod, void *inst);
	void module_inst_signal(struct module *mod, void *inst, int signal);

#ifdef __cplusplus
};
#endif

#endif // _MODULE_H_
