#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define MAX_THREADS 20

void* worker(void* id) {
    int t_id = (*(int*)id);
    printf("Thread %d created!\n", t_id);
    return 0;
}

int main(int argc, char** argv) {
    // int MAX_THREADS = atoi(argv[1]);
    pthread_t threads[MAX_THREADS];
    int threads_id[MAX_THREADS];

    for (int i = 0; i < MAX_THREADS; ++i) {
        threads_id[i] = i;
        pthread_create(&threads[i], NULL, worker,(void*)&threads_id[i]);
    }

    for (int i = 0; i < MAX_THREADS; ++i) {
        pthread_join(threads[i], NULL);
    }

    return 0;
}
