package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;


public class Buffer {
    private final int maxSize;
    private LinkedList<Piece> buffer;
    private int o_ammount;
    private int x_ammount;

    public Buffer() {
        this(10);
    }

    public Buffer(int maxSize) {
        this.maxSize = maxSize;
        this.buffer = new LinkedList<Piece>();
    }

    public synchronized void add(Piece piece) throws InterruptedException {
        while (this.maxSize == buffer.size()) {
            buffer.wait();
        }

        if (piece.getType() == Piece.Type.X) {

            while (x_ammount == this.maxSize-2) {
                buffer.wait();
            }
            x_ammount++;
        }
        else {
            while (o_ammount == this.maxSize-1) {
                buffer.wait();
            }
            o_ammount++;
        }

        buffer.add(piece);
        this.notifyAll();
    }


    public synchronized void takeOXO(@Nonnull List<Piece> xList,
                                     @Nonnull List<Piece> oList) throws InterruptedException {

        while (o_ammount < 2 || x_ammount < 1) {
            this.wait();
        }

        int x_remaining = 1;
        int o_remaining = 2;

        Iterator<Piece> it = buffer.iterator();
        while (it.hasNext() && (o_remaining != 0 || x_remaining != 0)) {
            Piece item = it.next();
            if (item.getType() == Piece.Type.O && o_remaining != 0) {
                oList.add(item);
                it.remove();
                o_remaining--;
            } else if (item.getType() == Piece.Type.X && x_remaining != 0) {
                xList.add(item);
                it.remove();
                x_remaining--;
            }
        }

        o_ammount -= 2;
        x_ammount --;
        this.notifyAll();
    }
}
