#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    printf("Qual é o seu nome?\n");
    char* nome;
    scanf("%ms", &nome);

    printf("Quanto dinheiro você tem?\n");
    float dinheiro;
    scanf("%f", &dinheiro);
    int vezes = floor(dinheiro/1.5);

    printf("%s, você pode almoçar no RU %d vezes.\n", nome, vezes);

    free(nome);

    return 0;
}
