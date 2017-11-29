/*This exercise's objective is to purposefully generate a race condition*/

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

int global_count = 0;

void* worker_thread() {
    for (int i = 0; i < 100; ++i) {
        ++global_count;
    }
    pthred_exit(NULL);
    return 0;
}

int main(int argc, char** argv) {
    int n_threads = atoi(argv[1]);
    pthread_t threads[n_threads];
    // int thread_id[n_threads];

    for (int i = 0; i < n_threads; ++i) {
        // thread_id[i] = i;
        pthread_create(&threads[i], NULL, worker_thread, NULL);
    }
    for (int i = 0; i < n_threads; ++i) {
        pthread_join(threads[i], NULL);
    }
    printf("Expected value: %d\nActual value: %d\n", (100 * n_threads), global_count);


    return 0;
}
