#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <time.h>
#include <semaphore.h>

int produzir(int value);    // < definida em helper.c
void consumir(int produto); // < definida em helper.c
void *produtor_func(void *arg);
void *consumidor_func(void *arg);

int indice_produtor, indice_consumidor, tamanho_buffer;
int* buffer;

sem_t sem_prod;
sem_t sem_cons;

pthread_mutex_t mutex_prod;
pthread_mutex_t mutex_cons;

// Você deve fazer as alterações necessárias nesta função e na função
// consumidor_func para que usem semáforos para coordenar a produção
// e consumo de elementos do buffer.
void *produtor_func(void *arg) {
    // arg contem o número de itens a serem produzidos
    int max = *((int*)arg);
    for (int i = 0; i <= max; ++i) {
        int produto;
        if (i == max)
            // produto = -1;          // envia produto sinlizando FIM
            break;
        else 
            produto = produzir(i); // produz um elemento normal
        sem_wait(&sem_prod);
        pthread_mutex_lock(&mutex_prod);
        indice_produtor = (indice_produtor + 1) % tamanho_buffer; // calcula posição próximo elemento
        buffer[indice_produtor] = produto; // adiciona o elemento produzido à lista
        pthread_mutex_unlock(&mutex_prod);
        sem_post(&sem_cons);
    }
    return NULL;
}

void *consumidor_func(void *arg) {
    int n_itens = *((int*) arg);
    int i = 0;
    while (i != n_itens) {
        i++;
        sem_wait(&sem_cons);
        pthread_mutex_lock(&mutex_cons);
        indice_consumidor = (indice_consumidor + 1) % tamanho_buffer; //Calcula o próximo item a consumir
        int produto = buffer[indice_consumidor]; //obtém o item da lista
        pthread_mutex_unlock(&mutex_cons);
        sem_post(&sem_prod);
        //Podemos receber um produto normal ou um produto especial
        consumir(produto); //Consome o item obtido.
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 5) {
        printf("Uso: %s tamanho_buffer itens_produzidos n_produtores n_consumidores \n", argv[0]);
        return 0;
    }

    tamanho_buffer = atoi(argv[1]);
    int itens = atoi(argv[2]);
    int n_produtores = atoi(argv[3]);
    int n_consumidores = atoi(argv[4]);
    printf("itens=%d, n_produtores=%d, n_consumidores=%d\n",
	   itens, n_produtores, n_consumidores);

    // Iniciando buffer
    indice_produtor = 0;
    indice_consumidor = 0;
    buffer = malloc(sizeof(int) * tamanho_buffer);

    // Crie threads e o que mais for necessário para que n_produtores
    // threads criem cada uma n_itens produtos e o n_consumidores os
    // consumam.
    pthread_t producers[n_produtores];
    pthread_t consumers[n_consumidores];
    
    sem_init(&sem_prod, 0, tamanho_buffer);
    sem_init(&sem_cons, 0, 0);

    pthread_mutex_init(&mutex_prod, NULL);
    pthread_mutex_init(&mutex_cons, NULL);


    for (int i = 0; i < n_produtores; ++i) {
        pthread_create(&producers[i], NULL, produtor_func, (void*)&itens);
    }

    int buffer_itens = itens * n_produtores;  // numero de itens que serão produzidos
    int thread_itens = buffer_itens / n_consumidores;  // parametro dos consumidores

    int cons_params[n_consumidores];

    for (int i = 0; i < n_consumidores; i++) {
        cons_params[i] = thread_itens;
        if (i == n_consumidores - 1)
            cons_params[i] += buffer_itens % n_consumidores; 
        pthread_create(&consumers[i], NULL, consumidor_func, &cons_params[i]);
    }

    for (int i = 0; i < n_produtores; ++i) {
        pthread_join(producers[i], NULL);
    }
    
    for (int i = 0; i < n_consumidores; ++i) {
        pthread_join(consumers[i], NULL);
    }

    pthread_mutex_destroy(&mutex_cons);
    pthread_mutex_destroy(&mutex_prod);


    sem_destroy(&sem_prod);
    sem_destroy(&sem_cons);
    // ....
    
    // Libera memória do buffer
    free(buffer);

    return 0;
}
