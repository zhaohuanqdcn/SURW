#include<pthread.h>
#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>

char* d = "exited!";
void create(void* args) {
  char *val = d;


  pthread_exit(val);
}

int main() {
  pthread_t id[2];
  int a1 = 3;
  pthread_create(&id[0], NULL, (void*)create, &a1);

  char* retval[2];
  pthread_join(id[0], (void**) &retval[0]);

  FILE *fptr;

  fptr = fopen(".test/test.log","w");

   if(fptr == NULL)
   {
      printf("Error!");
      exit(1);
   }


   // TODO why isn't this working?
   // fprintf(fptr,"%s\n", ((char*) (*retval[0])));
   fprintf(fptr,"done!\n");
   fclose(fptr);

}
