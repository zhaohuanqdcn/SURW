#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <assert.h>

#define NUM_THREADS 2

int x = 0;

pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
pthread_barrier_t bar;

void *thread1(void *arg) {
    pthread_barrier_wait(&bar);
    for (int i = 0; i < 100000; i++) {
        pthread_mutex_lock(&mutex);
        x += 1;
        pthread_mutex_unlock(&mutex);
    }
    return NULL;
}

void *thread2(void *arg) {
    pthread_barrier_wait(&bar);
    for (int i = 0; i < 100000; i++) {
        pthread_mutex_lock(&mutex);
        x += 1;
        pthread_mutex_unlock(&mutex);
    }
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

    assert(x == 200000);

    pthread_mutex_destroy(&mutex);
    pthread_cond_destroy(&cond);

    return 0;
}
