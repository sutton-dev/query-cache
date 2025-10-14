/**
 * Main SOQL Query Cache
 * Provides caching layer for SOQL queries with configurable storage
 */
public class SOQLQueryCache {
    
    // Static (transaction-scoped) cache
    private static Map<String, CachedResult> transactionCache = new Map<String, CachedResult>();
    
    // Cache statistics
    private static SOQLCacheStatistics statistics = new SOQLCacheStatistics();
    
    // Platform Cache partition name (configure in Custom Metadata)
    private static final String PLATFORM_CACHE_PARTITION = 'SOQLCache';
    
    /**
     * Cache storage options
     */
    public enum CacheStorage {
        TRANSACTION_ONLY,  // Static map, lives for current transaction only
        PLATFORM_CACHE,    // Platform Cache, survives across transactions
        BOTH              // Two-tier: check transaction first, then platform
    }
    
    /**
     * Query options for caching behavior
     */
    public class CacheOptions {
        public CacheStorage storage = CacheStorage.TRANSACTION_ONLY;
        public Integer ttlSeconds = 0; // 0 = transaction-scoped only
        public Boolean bypassCache = false;
        public Integer maxResults = 50000; // Salesforce SOQL limit
        public Boolean enforceSharing = true;
        
        public CacheOptions setStorage(CacheStorage storage) {
            this.storage = storage;
            return this;
        }
        
        public CacheOptions setTTL(Integer seconds) {
            this.ttlSeconds = seconds;
            return this;
        }
        
        public CacheOptions setBypassCache(Boolean bypass) {
            this.bypassCache = bypass;
            return this;
        }
        
        public CacheOptions setMaxResults(Integer max) {
            this.maxResults = max;
            return this;
        }
        
        public CacheOptions setEnforceSharing(Boolean enforce) {
            this.enforceSharing = enforce;
            return this;
        }
    }
    
    /**
     * Cached result wrapper
     */
    private class CachedResult {
        public List<SObject> results;
        public Long timestamp;
        public Integer ttlSeconds;
        
        public CachedResult(List<SObject> results, Integer ttlSeconds) {
            this.results = results;
            this.timestamp = System.currentTimeMillis();
            this.ttlSeconds = ttlSeconds;
        }
        
        public Boolean isExpired() {
            if (ttlSeconds == 0) {
                return false; // Never expires (transaction-scoped)
            }
            Long elapsed = (System.currentTimeMillis() - timestamp) / 1000;
            return elapsed > ttlSeconds;
        }
    }
    
    /**
     * Execute a SOQL query with default caching (transaction-only)
     */
    public static List<SObject> query(String soql) {
        return query(soql, new CacheOptions());
    }
    
    /**
     * Execute a SOQL query with custom cache options
     */
    public static List<SObject> query(String soql, CacheOptions options) {
        // Normalize the query for consistent cache keys
        String cacheKey = SOQLNormalizer.normalize(soql);

        // Fallback to hash if normalization returns empty/null (required for Platform Cache)
        if (String.isBlank(cacheKey)) {
            cacheKey = generateHashKey(soql);
        }

        return queryWithKey(soql, cacheKey, options);
    }
    
    /**
     * Execute a SOQL query with a custom cache key (internal use)
     */
    public static List<SObject> queryWithKey(String soql, String cacheKey, CacheOptions options) {
        statistics.incrementTotalQueries();
        
        // Check if cache should be bypassed
        if (options.bypassCache) {
            statistics.incrementMisses();
            return executeQuery(soql, options);
        }
        
        // Check cache based on storage option
        CachedResult cached = null;
        
        if (options.storage == CacheStorage.TRANSACTION_ONLY || options.storage == CacheStorage.BOTH) {
            cached = transactionCache.get(cacheKey);
            if (cached != null && !cached.isExpired()) {
                statistics.incrementHits();
                statistics.incrementTransactionHits();
                return cached.results;
            }
        }
        
        if (options.storage == CacheStorage.PLATFORM_CACHE || options.storage == CacheStorage.BOTH) {
            cached = getPlatformCacheResult(cacheKey);
            if (cached != null && !cached.isExpired()) {
                statistics.incrementHits();
                statistics.incrementPlatformHits();
                
                // Promote to transaction cache if using BOTH
                if (options.storage == CacheStorage.BOTH) {
                    transactionCache.put(cacheKey, cached);
                }
                
                return cached.results;
            }
        }
        
        // Cache miss - execute query
        statistics.incrementMisses();
        List<SObject> results = executeQuery(soql, options);
        
        // Store in cache
        CachedResult newCached = new CachedResult(results, options.ttlSeconds);
        
        if (options.storage == CacheStorage.TRANSACTION_ONLY || options.storage == CacheStorage.BOTH) {
            // Check transaction cache size before adding
            if (transactionCache.size() < 100) {
                transactionCache.put(cacheKey, newCached);
            }
        }
        
        if (options.storage == CacheStorage.PLATFORM_CACHE || options.storage == CacheStorage.BOTH) {
            putPlatformCacheResult(cacheKey, newCached);
        }
        
        return results;
    }
    
    /**
     * Execute query with sharing enforcement
     */
    private static List<SObject> executeQuery(String soql, CacheOptions options) {
        // Apply max results limit
        String finalQuery = soql;
        if (!soql.toUpperCase().contains('LIMIT') && options.maxResults > 0) {
            finalQuery = soql + ' LIMIT ' + options.maxResults;
        }

        // Execute with or without sharing based on options
        if (options.enforceSharing) {
            return SOQLQueryExecutor.executeWithSharing(finalQuery);
        } else {
            return SOQLQueryExecutor.executeWithoutSharing(finalQuery);
        }
    }
    
    /**
     * Generate a hash-based cache key from a query string
     * Platform Cache requires alphanumeric keys only (no special characters)
     * Max length: 50 characters
     */
    private static String generateHashKey(String query) {
        if (String.isBlank(query)) {
            return 'Q' + String.valueOf(System.currentTimeMillis());
        }
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(query));
        // Use first 50 chars of hex hash (alphanumeric only, max 50 char limit)
        return EncodingUtil.convertToHex(hash).substring(0, 50);
    }

    /**
     * Sanitize cache key for Platform Cache (alphanumeric only, max 50 chars)
     * Platform Cache requires:
     * - Alphanumeric only (no spaces, underscores, or special chars)
     * - Maximum length of 50 characters
     */
    private static String sanitizePlatformCacheKey(String key) {
        if (String.isBlank(key)) {
            return generateHashKey(key);
        }

        // If key is too long or contains non-alphanumeric characters, hash it
        if (key.length() > 50 || !Pattern.matches('^[a-zA-Z0-9]+$', key)) {
            Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(key));
            return EncodingUtil.convertToHex(hash).substring(0, 50);
        }

        return key;
    }

    /**
     * Get result from Platform Cache
     */
    private static CachedResult getPlatformCacheResult(String key) {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition(PLATFORM_CACHE_PARTITION);
            String platformKey = sanitizePlatformCacheKey(key);
            return (CachedResult)orgPart.get(platformKey);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Platform Cache get failed: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Put result in Platform Cache
     */
    private static void putPlatformCacheResult(String key, CachedResult cached) {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition(PLATFORM_CACHE_PARTITION);

            // Calculate TTL for platform cache
            Integer ttl = cached.ttlSeconds > 0 ? cached.ttlSeconds : 300; // Default 5 min

            String platformKey = sanitizePlatformCacheKey(key);
            orgPart.put(platformKey, cached, ttl);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Platform Cache put failed: ' + e.getMessage());
        }
    }
    
    /**
     * Clear transaction cache
     */
    public static void clearTransactionCache() {
        transactionCache.clear();
    }
    
    /**
     * Clear platform cache
     */
    public static void clearPlatformCache() {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition(PLATFORM_CACHE_PARTITION);
            // Platform Cache doesn't have a clear all method
            // Would need to track keys separately or use a different approach
            System.debug('Platform Cache clear not implemented - keys must be removed individually');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Platform Cache clear failed: ' + e.getMessage());
        }
    }
    
    /**
     * Clear specific query from cache by cache key
     */
    public static void clearCacheKey(String cacheKey) {
        transactionCache.remove(cacheKey);

        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition(PLATFORM_CACHE_PARTITION);
            String platformKey = sanitizePlatformCacheKey(cacheKey);
            orgPart.remove(platformKey);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Platform Cache remove failed: ' + e.getMessage());
        }
    }
    
    /**
     * Clear specific query from cache by query string
     */
    public static void clearQuery(String soql) {
        String cacheKey = SOQLNormalizer.normalize(soql);
        clearCacheKey(cacheKey);
    }
    
    /**
     * Get cache statistics
     */
    public static SOQLCacheStatistics getStatistics() {
        return statistics;
    }
    
    /**
     * Reset statistics
     */
    public static void resetStatistics() {
        statistics = new SOQLCacheStatistics();
    }
}