#define LIBDL 1

#include "stdlib.c"
#include <dlfcn.h>

#define RED "\33[31m"
#define OFF "\33[0m"

typedef size_t (*schedule_memop_t)(const void *, const void *, size_t, bool);
static schedule_memop_t schedule_memop_fn = NULL;

void mem_wri(const void *instr_addr, const void *mem_addr, size_t size)
{
    dlcall(schedule_memop_fn, instr_addr, mem_addr, size, true);
}


void mem_ri(const void *instr_addr, const void *mem_addr, size_t size)
{
    dlcall(schedule_memop_fn, instr_addr, mem_addr, size, false);
}

void mem_wi(const void *instr_addr, const void *mem_addr, size_t size)
{
    dlcall(schedule_memop_fn, instr_addr, mem_addr, size, true);
}

void init(int argc, const char **argv, char **envp, void *dynp)
{
    environ = envp;

    const char *filename = getenv("LD_PRELOAD");
    if (filename == NULL)
    {
        fprintf(stderr, RED "error" OFF ": LD_PRELOAD should be set to "
                            "\"$PWD/libsched.so\"\n");
        abort();
    }
    dlinit(dynp);
    void *handle = dlopen(filename, RTLD_NOW);
    if (handle == NULL)
    {
        fprintf(stderr, RED "error" OFF ": failed to open file \"%s\"\n",
                filename);
        abort();
    }

    const char *funcname = "schedule_memop";
    schedule_memop_fn = dlsym(handle, funcname);
    if (schedule_memop_fn == NULL)
    {
        fprintf(stderr, RED "error" OFF ": failed to find function \"%s\"\n",
                funcname);
        abort();
    }
}

