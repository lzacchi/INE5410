#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <string.h>

//        (pai)
//          |
//      +---+---+
//      |       |
//     sed    grep

// ~~~ printfs  ~~~
//        sed (ao iniciar): "sed PID %d iniciado\n"
//       grep (ao iniciar): "grep PID %d iniciado\n"
//          pai (ao iniciar): "Processo pai iniciado\n"
// pai (após filho terminar): "grep retornou com código %d,%s encontrou silver\n"
//                            , onde %s é
//                              - ""    , se filho saiu com código 0
//                              - " não" , caso contrário

// Obs:
// - processo pai deve esperar pelo filho
// - 1º filho deve trocar seu binário para executar "grep silver text"
//   + dica: use execlp(char*, char*...)
//   + dica: em "grep silver text",  argv = {"grep", "silver", "text"}
// - 2º filho, após o término do 1º deve trocar seu binário para executar
//   sed -i /silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g text
//   + dica: leia as dicas do grep

void grep_f() {
    printf("grep PID %d iniciado\n", getpid());
    fflush(stdout);
    execlp("grep", "grep", "adamantium", "text", (char*)NULL);
    exit(0);
}


void sed_f() {
    printf("sed PID %d iniciado\n", getpid());
    fflush(stdout);
    execlp("sed", "sed", "-i",
           "s/silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g",
           "text", (char*)NULL);
    exit(0);
}


int main(int argc, char** argv) {
    int status;
    pid_t grep;
    pid_t sed;
    char* string = "";
    
    sed = fork();
    if (sed) {
        wait(NULL);
        grep = fork();
    }
    if (!sed)
        sed_f();
    else if (!grep)
        grep_f();
    else if (grep & sed) {
        printf("Processo principal iniciado\n");
        while(wait(&status) > 0);
        int grep_status = WEXITSTATUS(status);
        if (grep_status) {
            string = " não";
        }
        printf("grep retornou com código %d,%s encontrou adamantium\n", grep_status, string);
    }

    return 0;
}
