#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>
#include<stdbool.h>

pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond  = PTHREAD_COND_INITIALIZER;

bool is_waiting = false;

void create(void* args) {
  while (!is_waiting) {
    pthread_mutex_lock(&lock);
    pthread_mutex_unlock(&lock);
    
  }
  pthread_cond_broadcast(&cond);

  pthread_exit(NULL);
}

int main() {
  pthread_t id[2];
  int a1 = 3;
  pthread_cond_init(&cond, NULL);
  pthread_create(&id[0], NULL, (void*)create, &a1);

  pthread_mutex_lock(&lock);
  is_waiting = true;
  pthread_cond_wait(&cond, &lock);

  pthread_join(id[0], NULL);

  FILE *fptr;

  fptr = fopen(".test/test.log","w");

   if(fptr == NULL)
   {
      printf("Error!");
      exit(1);
   }

   fprintf(fptr,"done!\n");
   fclose(fptr);
}