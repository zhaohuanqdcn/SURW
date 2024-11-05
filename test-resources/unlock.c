#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>

int glob = 0;
void create(void* args) {
  pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_init(&lock, NULL);
  pthread_mutex_lock(&lock);
  glob = glob + 1;
  pthread_mutex_unlock(&lock);


  pthread_exit(NULL);
}

int main() {
  pthread_t id[2];
  int a1 = 3;
  pthread_create(&id[0], NULL, (void*)create, &a1);

  pthread_join(id[0], NULL);

  FILE *fptr;

  char* fname = getenv("PROG_LOG_FILE");

  fptr = fopen(fname, "w");

   if(fptr == NULL)
   {
      printf("Error!");
      exit(1);
   }

   fprintf(fptr,"done!\n");
   fclose(fptr);
}
