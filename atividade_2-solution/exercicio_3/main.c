#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/wait.h>

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

int main(int argc, char** argv) {
    printf("Processo pai iniciado\n");
    fflush(stdout);
    if (fork()) {
	while (wait(0) >= 0) ;
	
	pid_t child = fork();
	if (child) {
	    int stat;
	    do {
		waitpid(child, &stat, 0);
	    } while (!WIFEXITED(stat));
	    int code = WEXITSTATUS(stat);
	    printf("Grep retornou com código %d,%s encontrou adamantium\n", 
		   code, code ? "não" : "");
	} else {
	    printf("grep PID %d iniciado\n", getpid());
	    fflush(stdout);
	    execlp("grep", "grep", "adamantium", "text", NULL);
	}
    } else {
        printf("sed PID %d iniciado\n", getpid());
        fflush(stdout);
        execlp("sed", "sed", "-i", "s/silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g", "text", NULL);
    }
    
    return 0;
}
