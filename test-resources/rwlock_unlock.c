#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>

int glob = 0;
void create(void* args) {
  pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
  pthread_rwlock_init(&lock, NULL);
  pthread_rwlock_rdlock(&lock);
  glob += 1;
  pthread_rwlock_unlock(&lock);



  pthread_exit(NULL);
}

int main() {
  pthread_t id[2];
  int a1 = 3;
  pthread_create(&id[0], NULL, (void*)create, &a1);

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
