#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>


//       (pai)      
//         |        
//    +----+----+
//    |         |   
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!


int main(int argc, char** argv) {
    int pid0 = fork();
    int pid1;
    if (pid0) {
        pid1 = fork();
    }

    if ((pid0 > 0) & (pid1 > 1)) {
        printf("Processo pai criou %d\n", pid0);
        printf("Processo pai criou %d\n", pid1);

        wait(NULL);
        printf("Processo pai finalizado!\n");
    } else if (pid0 == 0) {
        printf("Processo filho %d criado\n", getpid());
    } else if (pid1 == 0) {
        printf("Processo filho %d criado\n", getpid());
    }
    return 0;
}
