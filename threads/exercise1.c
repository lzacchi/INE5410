#include <stdio.h>
#include <pthread.h>

void* worker() {
    printf("New thread %ld created!\n", pthread_self());
    return 0;
}
int main() {
    pthread_t worker_thread;
    printf("is it working?\n");
    pthread_create(&worker_thread, NULL, worker, NULL);
    pthread_join(worker_thread, NULL);

    return 0;
}
