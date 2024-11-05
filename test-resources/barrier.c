#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>

pthread_barrier_t bar;

void create(void* args) {
  pthread_barrier_wait(&bar);
  fprintf(stderr, "") ;  
}

int main() {

    FILE *fptr;

    char* fname = getenv("PROG_LOG_FILE");

    fptr = fopen(fname, "w");

    if(fptr == NULL) {
      fptr = stdout;
    }

  pthread_barrier_init(&bar, NULL, 2);

  pthread_t id[2];
  int a1 = 3;
  pthread_create(&id[0], NULL, (void*)create, &a1);
  pthread_barrier_wait(&bar);
  pthread_join(id[0], NULL);

  fprintf(fptr,"done!");
  fclose(fptr);
}
