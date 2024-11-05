#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>
#include<stdbool.h>
#include "libzigsched.h"


pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond  = PTHREAD_COND_INITIALIZER;


void create(void* args) {
  abort();
}

int main() {
  pthread_t id[2];
  int a1 = 3;
  pthread_cond_init(&cond, NULL);
  pthread_create(&id[0], NULL, (void*)create, &a1);

  force_yield();

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
