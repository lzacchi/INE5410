#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

//                 (main)      
//                    |
//    +----------+----+------------+
//    |          |                 |   
// worker_1   worker_2   ....   worker_n


// ~~~ argumentos (argc, argv) ~~~
// ./program n_threads

// ~~~ printfs  ~~~
// pai (ao criar filho): "Contador: %d\n"
// pai (ao criar filho): "Esperado: %d\n"

// Obs:
// - pai deve criar n_threds (argv[1]) worker threads 
// - cada thread deve incrementar contador_global n_threads*1000
// - pai deve esperar pelas worker threads  antes de imprimir!


int contador_global = 0;
// Declara um mutex. Isso apenas reserva um espaço na memória. 
// mtx ainda não pode ser usado
//pthread_mutex_t mtx;
// Para que mtx você imediatamente usável, ele precisaria ser inicializado:
pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;


void *ThreadFunc(void *arg) {
    int numOfLoops = *(int *)arg;
    int i;
    for (i = 0; i < numOfLoops; i++) {
        pthread_mutex_lock(&mtx);
        contador_global += 1;       // seção crítica
        pthread_mutex_unlock(&mtx);
        //É extremamente importante garantir que todo lock() tem um unlock() 
        //correspondente que sempre será executado. Se isso não for garantido
        //Nenhum novo lock() será realizado e o programa travrá.
    }
    pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("n_threads é obrigatório!\n");
        printf("Uso: %s n_threads\n", argv[0]);
        return 1;
    }

    int numOfThreads = atoi(argv[1]);
    int numOfLoops = 1000 * numOfThreads;
    pthread_t threads[numOfThreads];
    
    // Inicializa mtx, caso ele não tenha sido inicializado com 
    // = PTHREAD_MUTEX_INITIALIZER
    //pthread_mutex_init(&mtx, NULL);

    for (int i = 0; i < numOfThreads; i++)
        pthread_create(&threads[i], NULL, ThreadFunc, (void*)&numOfLoops);

    for (int i = 0; i < numOfThreads; i++)
        pthread_join(threads[i], NULL);

    // Destroy mtx. Qualquer uso futuro do mtx será um erro.
    pthread_mutex_destroy(&mtx);
    
    printf("Contador: %d\n", contador_global);
    printf("Esperado: %d\n", numOfThreads * numOfLoops);
    return 0;
}