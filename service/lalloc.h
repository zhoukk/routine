#ifndef _LALLOC_H_
#define _LALLOC_H_

#include <stddef.h>

struct allocator;

struct allocator *allocator_new(void);
void allocator_free(struct allocator *);
void allocator_info(struct allocator *);

void *pixel_lalloc(void *ud, void *ptr, size_t osize, size_t nsize);

#endif // _LALLOC_H_
