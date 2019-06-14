#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>
#include <time.h>
#include <stdlib.h>

FILE* out;

sem_t sem_a;
sem_t sem_b;

void *thread_a(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
    sem_wait(&sem_a);
    //      +---> arquivo (FILE*) destino
	//      |    +---> string a ser impressa
	//      v    v
        fprintf(out, "A");
        // Importante para que vocês vejam o progresso do programa
        // mesmo que o programa trave em um sem_wait().
    sem_post(&sem_b);
        fflush(stdout);
    }
    return NULL;
}

void *thread_b(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
        sem_wait(&sem_b);
        fprintf(out, "B");
        sem_post(&sem_a);
        fflush(stdout);
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Uso: %s iteraões\n", argv[0]);
        return 1;
    }
    int iters = atoi(argv[1]);
    srand(time(NULL));
    out = fopen("result.txt", "w");

    pthread_t ta, tb;

    // Cria threads

    // Os dois semaforos inicializados em 1 garantem que
    // a diferença nunca será maior que 2
    sem_init(&sem_a, 0, 1);
    sem_init(&sem_b, 0, 1);

    pthread_create(&ta, NULL, thread_a, &iters);
    pthread_create(&tb, NULL, thread_b, &iters);

    // Espera pelas threads
    pthread_join(ta, NULL);
    pthread_join(tb, NULL);

    sem_destroy(&sem_b);
    sem_destroy(&sem_a);
    // Imprime quebra de linha e fecha arquivo
    fprintf(out, "\n");
    fclose(out);
  
    return 0;
}
