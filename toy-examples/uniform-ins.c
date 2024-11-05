#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define NUM_THREADS 3

int x = 0;

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
pthread_barrier_t bar;

void *thread1(void *arg) {
    pthread_barrier_wait(&bar);
    sched_yield();
    x = 1;
    sched_yield();
    x = 2;
    sched_yield();
    x = 3;
    sched_yield();
    x = 4;
    sched_yield();
    x = 5;
    sched_yield();
    x = 6;
    return NULL;
}

void *thread2(void *arg) {
    pthread_barrier_wait(&bar);
    sched_yield();
    x = 7;
    sched_yield();
    x = 8;
    sched_yield();
    x = 9;
    sched_yield();
    x = 10;
    sched_yield();
    x = 11;
    sched_yield();
    x = 12;
    return NULL;
}

void *thread3(void *arg) {
    pthread_barrier_wait(&bar);
    sched_yield();
    x = 13;
    sched_yield();
    x = 14;
    sched_yield();
    x = 15;
    sched_yield();
    x = 16;
    sched_yield();
    x = 17;
    sched_yield();
    x = 18;
    return NULL;
}

int main() {
    pthread_t threads[NUM_THREADS];
    int i;
    pthread_barrier_init(&bar, NULL, 4);

    pthread_create(&threads[0], NULL, thread1, NULL);
    pthread_create(&threads[1], NULL, thread2, NULL);
    pthread_create(&threads[2], NULL, thread3, NULL);

    pthread_barrier_wait(&bar);
    sched_yield();
    int value = x;
    FILE *file = fopen("dist.txt", "a");
    fprintf(file, "%d\n", value);

    pthread_join(threads[0], NULL);
    pthread_join(threads[1], NULL);
    pthread_join(threads[2], NULL);

    // int success = 1 / (value != CRASH_VALUE);

    pthread_mutex_destroy(&mutex);
    pthread_cond_destroy(&cond);

    return 0;
}
