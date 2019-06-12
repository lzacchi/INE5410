package br.ufsc.atividade11;

import javax.annotation.Nonnull;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class Market {
    private Map<Product, Double> prices = new HashMap<>();
    private ReadWriteLock lock;
    // private Condition condition;

    private Lock readLock = lock.readLock();
    private Lock writeLock = lock.writeLock();
    private Condition condition = writeLock.newCondition();

    public Market() {
        for (Product product : Product.values()) {
            prices.put(product, 1.99);
        }
    }


    // Atribui um preço a um produto específico
    public void setPrice(@Nonnull Product product, double value) {
        writeLock.lock();
        prices.put(product, value);
        if (prices.get(product) > value) {
            condition.signalAll();
        }
        writeLock.unlock();
    }


    // Pega um produto da gôndola e coloca na cesta.
    // O retorno é o valor do produto
    public double take(@Nonnull Product product) {
        readLock.lock();
        return prices.get(product);
    }


    // Tira um produto da cesta e coloca de volta na gôndola
    public void putBack(@Nonnull Product product) {
        readLock.unlock();
    }


    // Espera até que o preço do produto baixe para um valor 
    // menor que maximumValue. Quando isso acontecer, coloca 
    // o produto na cesta. O método retorna o valor do produto 
    // colocado na cesta
    public double waitForOffer(@Nonnull Product product,
                               double maximumValue) throws InterruptedException {
        //deveria esperar até que prices.get(product) <= maximumValue
        writeLock.lock();
        while(prices.get(product) > maximumValue) {
            condition.await();
        }
        take(product);
        writeLock.unlock();
        return prices.get(product);
    }


    // Paga por um produto. O retorno é o valor pago, que deve 
    // ser o mesmo retornado por waitForOffer() ou take()
    public double pay(@Nonnull Product product) {
        readLock.unlock();
        return prices.get(product);
    }
}
// public class Market {
//     private Map<Product, Double> prices = new HashMap<>();
//     private Map<Product, ReentrantReadWriteLock> locks = new HashMap<>();
//     private Map<Product, Condition> conditions = new HashMap<>();
    
//     public Market() {
//         for (Product product : Product.values()) {
//             prices.put(product, 1.99);
//             ReentrantReadWriteLock rwlock = new ReentrantReadWriteLock();
//             locks.put(product, rwlock);
//             conditions.put(product, rwlock.writeLock().newCondition());
//         }
//     }

//     public void setPrice(@Nonnull Product product, double value) {
        
//         (locks.get(product)).writeLock().lock();
//         prices.put(product, value);
//         if (prices.get(product) > value)
//             conditions.get(product).signalAll();
//         (locks.get(product)).writeLock().unlock();
//     }

//     public double take(@Nonnull Product product) {
//         locks.get(product).readLock().lock();
//         return prices.get(product);
//     }

//     public void putBack(@Nonnull Product product) {
//         locks.get(product).readLock().unlock();
//     }

//     public double waitForOffer(@Nonnull Product product,
//                                double maximumValue) throws InterruptedException {
//         //deveria esperar até que prices.get(product) <= maximumValue
//         locks.get(product).writeLock().lock();
//         while (prices.get(product) <= maximumValue)
//             conditions.get(product).await();
//         take(product);
//         locks.get(product).writeLock().unlock();
//         return prices.get(product);
//     }

//     public double pay(@Nonnull Product product) {
//         locks.get(product).readLock().unlock();
//         return prices.get(product);
//     }
// }