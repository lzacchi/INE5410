#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

// Lê o conteúdo do arquivo filename e retorna um vetor E o tamanho dele
// Se filename for da forma "gen:%d", gera um vetor aleatório com %d elementos
//
// +-------> retorno da função, ponteiro para vetor malloc()ado e preenchido
// | 
// |         tamanho do vetor (usado <-----+
// |         como 2o retorno)              |
// v                                       v
double* load_vector(const char* filename, int* out_size);
void avaliar(double* a, double* b, int a_size, double result);

double *a, *b, *thread_result;

typedef struct {
    int id;
    int start;
    int end;
} param_t;


void* product(void* args) {
    param_t params = *(param_t*) args;

    for(int i = params.start; i < params.end; ++i) {
        thread_result[params.id] += a[i] * b[i];
    }
    pthread_exit(NULL);
}


int main(int argc, char* argv[]) {
    srand(time(NULL));

    //Temos argumentos suficientes?
    if(argc < 4) {
        printf("Uso: %s n_threads a_file b_file\n"
               "    n_threads    número de threads a serem usadas na computação\n"
               "    *_file       caminho de arquivo ou uma expressão com a forma gen:N,\n"
               "                 representando um vetor aleatório de tamanho N\n", 
               argv[0]);
        return 1;
    }
  
    // Quantas threads?
    int n_threads = atoi(argv[1]);
    if (!n_threads) {
        printf("Número de threads deve ser > 0\n");
        return 1;
    }

    // Lê números de arquivos para vetores alocados com malloc
    int a_size = 0, b_size = 0;
    a = load_vector(argv[2], &a_size);
    if (!a) {
        // load_vector não conseguiu abrir o arquivo
        printf("Erro ao ler arquivo %s\n", argv[2]);
        return 1;
    }
    
    b = load_vector(argv[3], &b_size);
    if (!b) {
        printf("Erro ao ler arquivo %s\n", argv[3]);
        return 1;
    }
    
    // Garante que entradas são compatíveis
    if (a_size != b_size) {
        printf("Vetores a e b tem tamanhos diferentes! (%d != %d)\n", a_size, b_size);
        return 1;
    }

    // Garante que não serão criadas mais threads que necessário
    if (n_threads > a_size)
        n_threads = a_size;

    thread_result = (double*) malloc(sizeof(double) * n_threads);

    pthread_t threads[n_threads];
    param_t params[n_threads];
    int thread_start = 0;
    int thread_size;

    for (int i = 0; i < n_threads; ++i) {
        if (i < a_size % n_threads)
            thread_size = a_size / n_threads + 1;
        else
            thread_size = a_size / n_threads;
        
        params[i].id = i;
        params[i].start = thread_start;
        params[i].end = thread_start + thread_size;

        pthread_create(&threads[i], NULL, product, (void*)&params[i]);
        thread_start += thread_size;
    }

    double result = 0;
    for (int i = 0; i < n_threads; ++i) {
        pthread_join(threads[i], NULL);
        result += thread_result[i];
    }

    
    
    // IMPORTANTE: avalia o resultado!
    avaliar(a, b, a_size, result);

    // Libera memória
    free(a);
    free(b);
    free(thread_result);

    return 0;
}
