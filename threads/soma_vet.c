#include <stdio.h>
#include <stdlib.h>

int main (int argc, char *argv[])
{
  int tam_vet;
  int i;
  int imprimir = 0;

  if(argc<2){
    printf("uso %s <tamanho vetores> [imprimir? 1=sim]\n", argv[0]);
    exit(1);
  }

  /* tamanho dos vetores */
  tam_vet = atoi(argv[1]);

  if(argc==3 && atoi(argv[2])==1)
    imprimir = 1;

  /* alocacao do vetor A */
  double *a = (double *) malloc(sizeof(double) * tam_vet);

  /* alocacao do vetor B */
  double *b = (double *) malloc(sizeof(double) * tam_vet);

  /* alocacao do vetor C */
  double *c = (double *) malloc(sizeof(double) * tam_vet);

  printf("Inicializando vetores A, B e C...\n");

  /* inicializacao dos vetores */
  for (i=0; i<tam_vet; i++)
    a[i] = i;

  for (i=0; i<tam_vet; i++)
    b[i] = i;

  for (i=0; i<tam_vet; i++)
    c[i] = 0;

  printf("Calculando...\n");

  /* soma dos vetores */
  for (i=0; i<tam_vet; i++)
    c[i] = a[i] + b[i];

  printf("Terminou!\n");

  if(imprimir)
  {
    /*** imprime os resultados ***/
    printf("******************************************************\n");
    printf("Vetor C:\n");
    for (i=0; i<tam_vet; i++)
      printf("%10.2f  ", c[i]);
    printf("\n");
    printf("******************************************************\n");
  }

  free(a);
  free(b);
  free(c);
}
