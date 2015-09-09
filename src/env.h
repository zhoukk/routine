#ifndef _ENV_H_
#define _ENV_H_

#ifdef __cplusplus
extern "C" {
#endif

	void env_init(void);
	void env_unit(void);
	void env_set(const char *key, const char *val);
	const char *env_get(const char *key);

#ifdef __cplusplus
};
#endif

#endif // _ENV_H_
