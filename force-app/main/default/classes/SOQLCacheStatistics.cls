/**
 * Cache statistics tracker
 */
public class SOQLCacheStatistics {
    private Integer totalQueries = 0;
    private Integer cacheHits = 0;
    private Integer cacheMisses = 0;
    private Integer transactionHits = 0;
    private Integer platformHits = 0;
    
    public void incrementTotalQueries() {
        totalQueries++;
    }
    
    public void incrementHits() {
        cacheHits++;
    }
    
    public void incrementMisses() {
        cacheMisses++;
    }
    
    public void incrementTransactionHits() {
        transactionHits++;
    }
    
    public void incrementPlatformHits() {
        platformHits++;
    }
    
    public Integer getTotalQueries() {
        return totalQueries;
    }
    
    public Integer getCacheHits() {
        return cacheHits;
    }
    
    public Integer getCacheMisses() {
        return cacheMisses;
    }
    
    public Integer getTransactionHits() {
        return transactionHits;
    }
    
    public Integer getPlatformHits() {
        return platformHits;
    }
    
    public Decimal getHitRate() {
        if (totalQueries == 0) {
            return 0;
        }
        return (Decimal)cacheHits / (Decimal)totalQueries * 100;
    }
    
    public String getSummary() {
        return String.format(
            'Total: {0}, Hits: {1}, Misses: {2}, Hit Rate: {3}%, Transaction: {4}, Platform: {5}',
            new List<Object>{
                totalQueries,
                cacheHits,
                cacheMisses,
                getHitRate().setScale(2),
                transactionHits,
                platformHits
            }
        );
    }
}
