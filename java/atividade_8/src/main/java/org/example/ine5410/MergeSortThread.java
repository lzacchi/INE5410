package org.example.ine5410;

import javax.annotation.Nonnull;
import java.util.ArrayList;
import java.util.List;

public class MergeSortThread<T extends Comparable<T>> implements MergeSort<T> {
    @Nonnull
    @Override
    public ArrayList<T> sort(@Nonnull final List<T> list) {
        //1. Há duas sub-tarefas, execute-as em paralelo usando threads
        //  (Para pegar um retorno da thread filha faça ela escrever em um ArrayList)

        if (list.size() <= 1)
            return new ArrayList<>(list);

        int mid = list.size() / 2;
        List<T> left = null;

        /* ~~~~ Execute essa linha paralelamente! ~~~~ */
        // left = sort(list.subList(0, mid));
        Worker worker = new Worker(list.subList(0, mid));
        Thread left_thread = new Thread(worker);

        left_thread.start();

        try {
            left_thread.join();
        } catch(InterruptedException e) {
            throw new RuntimeException(e);
        }

        left = worker.output;
        ArrayList<T> right = sort(list.subList(mid, list.size()));

        return MergeSortHelper.merge(left, right);
    }

    public class Worker implements Runnable{
        List<T> input;
        List<T> output;

        public Worker (List<T> input) {
            this.input = input;
        }
        public void run() {
            output = sort(input);
        }
    }
}
