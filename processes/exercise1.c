#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>

int main(int arcg, char** argv) {
    fork();

    printf("Novo processo criado\n");
}
