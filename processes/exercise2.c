#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>

int main(int argc, char** argv) {
    pid_t pid;

    for (int i = 0; i < 4; ++i) {
        pid = fork();
        if (pid == 0)
            break;
    }

    if (pid >= 0) {
        if (pid == 0) {
            printf("Processo pai %d criou processo filho %d\n", getppid(), getpid());
            // printf("Processo filho %d\n", getpid()); 
        }
        else {
            wait(NULL);
        }
    }
    return 0;
}
