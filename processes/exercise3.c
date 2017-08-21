#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>

int main(int argc, char** argv) {
    pid_t pid, pid2;

    for (int i = 0u; i < 2; ++i) {
        pid = fork();
        if (pid == 0) {
            for (int j = 0; j < 2; ++j) {
                pid2 = fork();
                if (pid2 == 0) break;
            }
            printf("Processo %d filho de %d\n", getpid(), getppid());
            break;
        }
            
    }

    while(wait(NULL) > 0);  // Faz com que todos os processos esperem seus filhos. 1 para 1
    return 0;
}
