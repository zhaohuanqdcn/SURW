#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define NUM_THREADS 2

int x = 0;

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
pthread_barrier_t bar;

// (x+1)*2*2*2*2+1+1+1+1 = (x*2*2+1+1+1+1+1)*2*2

void *thread1(void *arg) {
    pthread_barrier_wait(&bar);
    sched_yield();
    x = (x << 1);
    sched_yield();
    x = (x << 1);
    sched_yield();
    x = (x << 1);
    sched_yield();
    x = (x << 1);
    sched_yield();
    x = (x << 1);
    return NULL;
}

void *thread2(void *arg) {
    pthread_barrier_wait(&bar);
    sched_yield();
    x = (x << 1) + 1;
    sched_yield();
    x = (x << 1) + 1;
    sched_yield();
    x = (x << 1) + 1;
    sched_yield();
    x = (x << 1) + 1;
    sched_yield();
    x = (x << 1) + 1;
    return NULL;
}

int main() {
    pthread_t threads[NUM_THREADS];
    int i;
    pthread_barrier_init(&bar, NULL, 2);

    pthread_create(&threads[0], NULL, thread1, NULL);
    pthread_create(&threads[1], NULL, thread2, NULL);


    pthread_join(threads[0], NULL);
    pthread_join(threads[1], NULL);

    int value = x;
    FILE *file = fopen("dist.txt", "a");
    fprintf(file, "%d\n", value);

    // int success = 1 / (value != CRASH_VALUE);

    pthread_mutex_destroy(&mutex);
    pthread_cond_destroy(&cond);

    return 0;
}
