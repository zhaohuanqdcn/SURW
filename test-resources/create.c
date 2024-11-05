#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>

void create(void* args) {
  fprintf(stderr, "") ;  
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


   fprintf(fptr,"done!");
   fclose(fptr);

}
