#define LIBDL 1

#include "stdlib.c"
#include <dlfcn.h>

#define RED "\33[31m"
#define OFF "\33[0m"

typedef size_t (*schedule_memop_t)(const void *, const void *, size_t, bool);
static schedule_memop_t schedule_memop_fn = NULL;

void mem_wri(const void *instr_addr, const void *mem_addr, size_t size)
{
    sched_yield();
}


void mem_ri(const void *instr_addr, const void *mem_addr, size_t size)
{
    sched_yield();
}

void mem_wi(const void *instr_addr, const void *mem_addr, size_t size)
{
    sched_yield();
}

