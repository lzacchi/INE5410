package br.ufsc.atividade11;
import javax.annotation.Nonnull;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.locks.Condition;
// import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class Market {
    private Map<Product, Double> prices = new HashMap<>();
    private Map<Product, ReadWriteLock> locks = new  HashMap<>();
    private Map<Product, Condition> conditions = new HashMap<>();

    public Market() {
        for (Product product : Product.values()) {
            prices.put(product, 1.99);
            locks.put(product, new ReentrantReadWriteLock());
            conditions.put(product, locks.get(product).writeLock().newCondition());
        }
    }


    // Atribui um preço a um produto específico
    public void setPrice(@Nonnull Product product, double value) {
        ReadWriteLock product_lock = locks.get(product);
        // Condition set_price = locks.get(product).writeLock().newCondition();

        product_lock.writeLock().lock();
        try {
            prices.put(product, value);
            conditions.get(product).signalAll();
        } finally {
            product_lock.writeLock().unlock();
        }
    }


    // Pega um produto da gôndola e coloca na cesta.
    // O retorno é o valor do produto
    public double take(@Nonnull Product product) {
        ReadWriteLock take_lock = locks.get(product);

        take_lock.readLock().lock();

        return prices.get(product);
    }


    // Tira um produto da cesta e coloca de volta na gôndola
    public void putBack(@Nonnull Product product) {
        ReadWriteLock put_lock = locks.get(product);

        put_lock.readLock().unlock();
    }


    // Espera até que o preço do produto baixe para um valor
    // menor que maximumValue. Quando isso acontecer, coloca
    // o produto na cesta. O método retorna o valor do produto
    // colocado na cesta
    public double waitForOffer(@Nonnull Product product,
                               double maximumValue) throws InterruptedException {
        //deveria esperar até que prices.get(product) <= maximumValue
        ReadWriteLock wait_lock = locks.get(product);
        // Condition wait = locks.get(product).writeLock().newCondition();

        wait_lock.writeLock().lock();
        while (prices.get(product) > maximumValue) {
            conditions.get(product).await();
        }
        wait_lock.writeLock().unlock();
        take(product);
        return prices.get(product);
    }


    // Paga por um produto. O retorno é o valor pago, que deve
    // ser o mesmo retornado por waitForOffer() ou take()
    public double pay(@Nonnull Product product) {
        ReadWriteLock pay_lock = locks.get(product);

        pay_lock.readLock().unlock();
        return prices.get(product);
    }
}
