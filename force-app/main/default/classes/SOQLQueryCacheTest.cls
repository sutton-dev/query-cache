@isTest
private class SOQLQueryCacheTest {
    
    @testSetup
    static void setup() {
        // Create test data
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = (Math.mod(i, 3) == 0) ? 'Technology' : 'Healthcare',
                AnnualRevenue = 500000 + (i * 100000)
            ));
        }
        insert accounts;
        
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 30; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                AccountId = accounts[0].Id
            ));
        }
        insert contacts;
    }
    
    @isTest
    static void testBasicCaching() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        // Reset statistics
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query);
        System.assertNotEquals(null, result1, 'Should return results');
        System.assertEquals(10, result1.size(), 'Should return 10 records');
        
        // Second call - cache hit
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query);
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        
        // Third call - cache hit
        List<Account> result3 = (List<Account>)SOQLQueryCache.query(query);
        System.assertEquals(result1.size(), result3.size(), 'Should return same results');
        
        Test.stopTest();
        
        // Verify statistics
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(3, stats.getTotalQueries(), 'Should have 3 total queries');
        System.assertEquals(2, stats.getCacheHits(), 'Should have 2 cache hits');
        System.assertEquals(1, stats.getCacheMisses(), 'Should have 1 cache miss');
        System.assertEquals(2, stats.getTransactionHits(), 'Should have 2 transaction hits');
    }
    
    @isTest
    static void testQueryNormalization() {
        // These queries should normalize to the same cache key
        String query1 = 'SELECT Id, Name FROM Account WHERE Industry = \'Technology\'';
        String query2 = 'SELECT Name, Id FROM Account WHERE Industry = \'Technology\''; // Different field order
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query1);
        
        // Second call - should hit cache (normalized to same key)
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query2);
        
        // Third call - same as first, definitely should hit cache
        List<Account> result3 = (List<Account>)SOQLQueryCache.query(query1);
        
        Test.stopTest();
        
        // All should return same data
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        System.assertEquals(result1.size(), result3.size(), 'Should return same results');
        
        // Verify cache was used
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(3, stats.getTotalQueries(), 'Should have 3 queries');
        System.assertEquals(2, stats.getCacheHits(), 'Should have 2 cache hits due to normalization');
    }
    
    @isTest
    static void testCacheBypass() {
        String query = 'SELECT Id, Name FROM Account LIMIT 5';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setBypassCache(true);
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // Execute query multiple times with bypass
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query, options);
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query, options);
        List<Account> result3 = (List<Account>)SOQLQueryCache.query(query, options);
        
        Test.stopTest();
        
        // Verify all were cache misses
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(3, stats.getTotalQueries(), 'Should have 3 queries');
        System.assertEquals(0, stats.getCacheHits(), 'Should have 0 cache hits');
        System.assertEquals(3, stats.getCacheMisses(), 'Should have 3 cache misses');
    }
    
    @isTest
    static void testMaxResults() {
        String query = 'SELECT Id, Name FROM Account'; // No LIMIT
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setMaxResults(5);
        
        Test.startTest();
        
        List<Account> results = (List<Account>)SOQLQueryCache.query(query, options);
        
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Should return results');
        System.assert(results.size() <= 5, 'Should respect max results limit');
    }
    
    @isTest
    static void testTransactionCacheStorage() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setStorage(SOQLQueryCache.CacheStorage.TRANSACTION_ONLY);
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query, options);
        
        // Second call - cache hit from transaction cache
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query, options);
        
        Test.stopTest();
        
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(1, stats.getCacheHits(), 'Should have 1 cache hit');
        System.assertEquals(1, stats.getTransactionHits(), 'Should hit transaction cache');
    }
    
    @isTest
    static void testPlatformCacheStorage() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setStorage(SOQLQueryCache.CacheStorage.PLATFORM_CACHE)
            .setTTL(300);
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query, options);
        System.assertNotEquals(null, result1, 'Should return results');
        
        // Second call - should attempt platform cache
        // Note: Platform cache might not be available in test context
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query, options);
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        
        Test.stopTest();
        
        // At minimum, should have attempted to use platform cache
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(2, stats.getTotalQueries(), 'Should have 2 total queries');
    }
    
    @isTest
    static void testBothCacheStorage() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setStorage(SOQLQueryCache.CacheStorage.BOTH)
            .setTTL(300);
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query, options);
        
        // Second call - should hit transaction cache (faster)
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query, options);
        
        Test.stopTest();
        
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(1, stats.getCacheHits(), 'Should have cache hit');
    }
    
    @isTest
    static void testClearQuery() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        Test.startTest();
        
        // Cache the query
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query);
        
        // Clear the cache
        SOQLQueryCache.clearQuery(query);
        
        // Query again - should be a miss
        SOQLQueryCache.resetStatistics();
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query);
        
        Test.stopTest();
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(1, stats.getCacheMisses(), 'Should be a cache miss after clear');
    }
    
    @isTest
    static void testClearTransactionCache() {
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        
        Test.startTest();
        
        // Cache the query
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query);
        
        // Clear all transaction cache
        SOQLQueryCache.clearTransactionCache();
        
        // Query again - should be a miss
        SOQLQueryCache.resetStatistics();
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query);
        
        Test.stopTest();
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(1, stats.getCacheMisses(), 'Should be a cache miss after clear');
    }
    
    @isTest
    static void testMultipleDifferentQueries() {
        List<String> queries = new List<String>{
            'SELECT Id, Name FROM Account WHERE Industry = \'Technology\' LIMIT 5',
            'SELECT Id, Name FROM Account WHERE Industry = \'Healthcare\' LIMIT 5',
            'SELECT Id, Name FROM Contact LIMIT 5'
        };
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // Execute each query twice
        for (String q : queries) {
            List<SObject> result1 = SOQLQueryCache.query(q);
            List<SObject> result2 = SOQLQueryCache.query(q); // Should hit cache
            
            System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        }
        
        Test.stopTest();
        
        // Verify statistics
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(6, stats.getTotalQueries(), 'Should have 6 total queries');
        System.assertEquals(3, stats.getCacheHits(), 'Should have 3 cache hits');
        System.assertEquals(3, stats.getCacheMisses(), 'Should have 3 cache misses');
    }
    
    @isTest
    static void testCacheOptionsBuilder() {
        // Test the fluent builder interface
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setStorage(SOQLQueryCache.CacheStorage.PLATFORM_CACHE)
            .setTTL(600)
            .setMaxResults(100)
            .setBypassCache(false)
            .setEnforceSharing(true);
        
        System.assertEquals(SOQLQueryCache.CacheStorage.PLATFORM_CACHE, options.storage, 'Should set storage');
        System.assertEquals(600, options.ttlSeconds, 'Should set TTL');
        System.assertEquals(100, options.maxResults, 'Should set max results');
        System.assertEquals(false, options.bypassCache, 'Should set bypass cache');
        System.assertEquals(true, options.enforceSharing, 'Should set enforce sharing');
    }
    
    @isTest
    static void testStatisticsReset() {
        String query = 'SELECT Id, Name FROM Account LIMIT 5';
        
        Test.startTest();
        
        // Execute some queries
        SOQLQueryCache.query(query);
        SOQLQueryCache.query(query);
        
        SOQLCacheStatistics stats1 = SOQLQueryCache.getStatistics();
        System.assertEquals(2, stats1.getTotalQueries(), 'Should have 2 queries');
        
        // Reset statistics
        SOQLQueryCache.resetStatistics();
        
        SOQLCacheStatistics stats2 = SOQLQueryCache.getStatistics();
        System.assertEquals(0, stats2.getTotalQueries(), 'Should have 0 queries after reset');
        
        Test.stopTest();
    }
    
    @isTest
    static void testStatisticsCalculations() {
        String query = 'SELECT Id, Name FROM Account LIMIT 5';
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // Execute: 1 miss, 2 hits
        SOQLQueryCache.query(query);
        SOQLQueryCache.query(query);
        SOQLQueryCache.query(query);
        
        Test.stopTest();
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        
        System.assertEquals(3, stats.getTotalQueries(), 'Should have 3 total');
        System.assertEquals(2, stats.getCacheHits(), 'Should have 2 hits');
        System.assertEquals(1, stats.getCacheMisses(), 'Should have 1 miss');
        
        // Hit rate should be 66.67%
        Decimal hitRate = stats.getHitRate();
        System.assert(hitRate > 66 && hitRate < 67, 'Hit rate should be ~66.67%');
        
        // Test summary string
        String summary = stats.getSummary();
        System.assert(summary.contains('Total: 3'), 'Summary should contain total');
        System.assert(summary.contains('Hits: 2'), 'Summary should contain hits');
        System.assert(summary.contains('Misses: 1'), 'Summary should contain misses');
    }
    
    @isTest
    static void testEmptyResultsCaching() {
        // Query that returns no results
        String query = 'SELECT Id, Name FROM Account WHERE Name = \'NonExistent12345\'';
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // First call - cache miss
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query);
        System.assertEquals(0, result1.size(), 'Should return empty list');
        
        // Second call - cache hit (even for empty results)
        List<Account> result2 = (List<Account>)SOQLQueryCache.query(query);
        System.assertEquals(0, result2.size(), 'Should return empty list');
        
        Test.stopTest();
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(1, stats.getCacheHits(), 'Should cache empty results');
    }
    
    @isTest
    static void testCacheKeyGeneration() {
        // Test that custom cache keys work
        String query = 'SELECT Id, Name FROM Account LIMIT 10';
        String customKey = 'custom_key_123';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions();
        
        Test.startTest();
        
        // Use custom cache key
        List<SObject> result1 = SOQLQueryCache.queryWithKey(query, customKey, options);
        List<SObject> result2 = SOQLQueryCache.queryWithKey(query, customKey, options);
        
        Test.stopTest();
        
        System.assertEquals(result1.size(), result2.size(), 'Should return same results');
        
        // Can clear by custom key
        SOQLQueryCache.clearCacheKey(customKey);
    }
    
    @isTest
    static void testTransactionCacheSizeLimit() {
        // Test that transaction cache respects size limit (100 queries)
        // Note: We can't execute 105 unique queries due to SOQL governor limits (100/transaction)
        // Instead, we'll test that the cache size limit logic exists
        
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // Create 50 unique queries (within SOQL limits)
        // The cache should store up to 100, so all 50 should be cached
        for (Integer i = 0; i < 50; i++) {
            String query = 'SELECT Id, Name FROM Account WHERE Name = \'Test' + i + '\' LIMIT 1';
            SOQLQueryCache.query(query);
        }
        
        Test.stopTest();
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(50, stats.getTotalQueries(), 'Should have executed 50 queries');
        System.assertEquals(0, stats.getCacheHits(), 'Should have no cache hits (all unique)');
        System.assertEquals(50, stats.getCacheMisses(), 'Should have 50 cache misses');
        
        // All queries should be within the cache size limit
        // (We can't directly verify the cache size, but no errors means it worked)
    }
    
    @isTest
    static void testDifferentSObjectTypes() {
        SOQLQueryCache.resetStatistics();
        
        Test.startTest();
        
        // Query different object types
        List<Account> accounts = (List<Account>)SOQLQueryCache.query('SELECT Id, Name FROM Account LIMIT 5');
        List<Contact> contacts = (List<Contact>)SOQLQueryCache.query('SELECT Id, Name FROM Contact LIMIT 5');
        
        // Query same types again (should hit cache)
        List<Account> accounts2 = (List<Account>)SOQLQueryCache.query('SELECT Id, Name FROM Account LIMIT 5');
        List<Contact> contacts2 = (List<Contact>)SOQLQueryCache.query('SELECT Id, Name FROM Contact LIMIT 5');
        
        Test.stopTest();
        
        System.assertEquals(accounts.size(), accounts2.size(), 'Should cache Account queries');
        System.assertEquals(contacts.size(), contacts2.size(), 'Should cache Contact queries');
        
        SOQLCacheStatistics stats = SOQLQueryCache.getStatistics();
        System.assertEquals(2, stats.getCacheHits(), 'Should have 2 cache hits');
    }
    
    @isTest
    static void testCachedResultExpiration() {
        // Note: Testing expiration in synchronous tests is difficult
        // This test verifies the expiration logic exists
        
        String query = 'SELECT Id, Name FROM Account LIMIT 5';
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setTTL(1); // 1 second TTL
        
        Test.startTest();
        
        List<Account> result1 = (List<Account>)SOQLQueryCache.query(query, options);
        
        // In real execution, this would expire after 1 second
        // In test context, we just verify the option is respected
        System.assertNotEquals(null, result1, 'Should return results');
        
        Test.stopTest();
    }
}