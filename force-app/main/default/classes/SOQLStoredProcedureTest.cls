@isTest
private class SOQLStoredProcedureTest {
    
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
        
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 30; i++) {
            opps.add(new Opportunity(
                Name = 'Test Opp ' + i,
                AccountId = accounts[0].Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = 10000 + (i * 1000)
            ));
        }
        insert opps;
    }
    
    @isTest
    static void testExecuteStoredProcedureNotFound() {
        Test.startTest();
        
        try {
            SOQLStoredProcedure.execute('NonExistentProcedure');
            System.assert(false, 'Should throw exception for non-existent procedure');
        } catch (SOQLStoredProcedure.StoredProcedureException e) {
            System.assert(e.getMessage().contains('not found'), 'Should indicate procedure not found');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteWithParameters() {
        Test.startTest();
        
        // Test execute with parameters - will throw not found since no metadata exists
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology'
        };
        
        try {
            SOQLStoredProcedure.execute('TestProcedure', params);
            System.assert(false, 'Should throw exception for non-existent procedure');
        } catch (SOQLStoredProcedure.StoredProcedureException e) {
            System.assert(e.getMessage().contains('not found'), 'Should indicate procedure not found');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteWithParametersAndOptions() {
        Test.startTest();
        
        // Test execute with parameters and custom options
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology'
        };
        
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions()
            .setStorage(SOQLQueryCache.CacheStorage.PLATFORM_CACHE)
            .setTTL(300);
        
        try {
            SOQLStoredProcedure.execute('TestProcedure', params, options);
            System.assert(false, 'Should throw exception for non-existent procedure');
        } catch (SOQLStoredProcedure.StoredProcedureException e) {
            System.assert(e.getMessage().contains('not found'), 'Should indicate procedure not found');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testListProcedures() {
        Test.startTest();
        
        List<SOQL_Stored_Procedure__mdt> procedures = SOQLStoredProcedure.listProcedures();
        
        Test.stopTest();
        
        // Should return list (may be empty if no metadata configured)
        System.assertNotEquals(null, procedures, 'Should return list of procedures');
        
        // If procedures exist, verify they are active only
        for (SOQL_Stored_Procedure__mdt proc : procedures) {
            System.assertEquals(true, proc.Active__c, 'Should only return active procedures');
        }
    }
    
    @isTest
    static void testBuildProcedureCacheKey() {
        // Test cache key generation with no parameters
        String key1 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', null);
        System.assert(key1.startsWith('SP:TestProc'), 'Should start with SP:procedureName');
        
        // Test cache key with single parameter
        Map<String, Object> params1 = new Map<String, Object>{
            'industry' => 'Technology'
        };
        String key2 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params1);
        System.assert(key2.contains('industry=Technology'), 'Should include parameter');
        
        // Test cache key with multiple parameters (should be sorted)
        Map<String, Object> params2 = new Map<String, Object>{
            'industry' => 'Technology',
            'minRevenue' => 1000000
        };
        String key3 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params2);
        System.assert(key3.contains('industry=Technology'), 'Should include industry parameter');
        System.assert(key3.contains('minRevenue=1000000'), 'Should include minRevenue parameter');
    }
    
    @isTest
    static void testBuildProcedureCacheKeyWithList() {
        // Test cache key with list parameter
        Map<String, Object> params = new Map<String, Object>{
            'industries' => new List<String>{'Technology', 'Healthcare'}
        };
        
        String key = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params);
        System.assert(key.contains('industries='), 'Should include list parameter');
        System.assert(key.contains('['), 'Should format as list');
    }
    
    @isTest
    static void testBuildProcedureCacheKeyConsistency() {
        // Same parameters in different order should produce same key
        Map<String, Object> params1 = new Map<String, Object>{
            'industry' => 'Technology',
            'minRevenue' => 1000000
        };
        
        Map<String, Object> params2 = new Map<String, Object>{
            'minRevenue' => 1000000,
            'industry' => 'Technology'
        };
        
        String key1 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params1);
        String key2 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params2);
        
        System.assertEquals(key1, key2, 'Parameters in different order should produce same cache key');
    }
    
    @isTest
    static void testBuildQueryWithNoParameters() {
        // Create mock procedure
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account LIMIT 10',
            null
        );
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, new Map<String, Object>());
        
        System.assertEquals('SELECT Id, Name FROM Account LIMIT 10', query, 
            'Should return query unchanged when no parameters');
    }
    
    @isTest
    static void testBuildQueryWithStringParameter() {
        // Create mock procedure with parameter placeholder
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE Industry = :industry',
            '["industry"]'
        );
        
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology'
        };
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, params);
        
        System.assert(query.contains('\'Technology\''), 'Should replace parameter with value');
        System.assert(!query.contains(':industry'), 'Should not contain placeholder');
    }
    
    @isTest
    static void testBuildQueryWithNumericParameter() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE AnnualRevenue > :minRevenue',
            '["minRevenue"]'
        );
        
        Map<String, Object> params = new Map<String, Object>{
            'minRevenue' => 1000000
        };
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, params);
        
        System.assert(query.contains('1000000'), 'Should include numeric value');
        System.assert(!query.contains(':minRevenue'), 'Should not contain placeholder');
    }
    
    @isTest
    static void testBuildQueryWithListParameter() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE Industry IN :industries',
            '["industries"]'
        );
        
        Map<String, Object> params = new Map<String, Object>{
            'industries' => new List<String>{'Technology', 'Healthcare'}
        };
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, params);
        
        System.assert(query.contains('('), 'Should have opening parenthesis for list');
        System.assert(query.contains('\'Technology\''), 'Should include first list item');
        System.assert(query.contains('\'Healthcare\''), 'Should include second list item');
    }
    
    @isTest
    static void testBuildQueryWithMultipleParameters() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE Industry = :industry AND AnnualRevenue > :minRevenue',
            '["industry", "minRevenue"]'
        );
        
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology',
            'minRevenue' => 1000000
        };
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, params);
        
        System.assert(query.contains('\'Technology\''), 'Should replace industry parameter');
        System.assert(query.contains('1000000'), 'Should replace minRevenue parameter');
        System.assert(!query.contains(':industry'), 'Should not contain placeholders');
        System.assert(!query.contains(':minRevenue'), 'Should not contain placeholders');
    }
    
    @isTest
    static void testBuildQueryMissingParameter() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE Industry = :industry',
            '["industry"]'
        );
        
        Map<String, Object> params = new Map<String, Object>(); // Missing required parameter
        
        try {
            String query = SOQLStoredProcedure.buildQuery(mockProc, params);
            System.assert(false, 'Should throw exception for missing parameter');
        } catch (SOQLStoredProcedure.StoredProcedureException e) {
            System.assert(e.getMessage().contains('Missing required parameter'), 
                'Should indicate missing parameter');
        }
    }
    
    @isTest
    static void testBuildQueryWithSQLInjectionProtection() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id, Name FROM Account WHERE Name = :accountName',
            '["accountName"]'
        );
        
        // Test with single quotes (potential SQL injection)
        Map<String, Object> params = new Map<String, Object>{
            'accountName' => 'Test\' OR \'1\'=\'1'
        };
        
        String query = SOQLStoredProcedure.buildQuery(mockProc, params);
        
        // Single quotes should be escaped
        System.assert(query.contains('\\\''), 'Should escape single quotes');
    }
    
    @isTest
    static void testBuildCacheOptionsFromMetadata() {
        SOQL_Stored_Procedure__mdt mockProc = new SOQL_Stored_Procedure__mdt(
            DeveloperName = 'TestProc',
            Query__c = 'SELECT Id FROM Account',
            Cache_TTL__c = 600,
            Max_Results__c = 100,
            Cache_Storage__c = 'Platform Cache',
            Enforce_Sharing__c = true
        );
        
        SOQLQueryCache.CacheOptions options = SOQLStoredProcedure.buildCacheOptions(mockProc);
        
        System.assertEquals(600, options.ttlSeconds, 'Should set TTL from metadata');
        System.assertEquals(100, options.maxResults, 'Should set max results from metadata');
        System.assertEquals(SOQLQueryCache.CacheStorage.PLATFORM_CACHE, options.storage, 
            'Should set storage type from metadata');
        System.assertEquals(true, options.enforceSharing, 'Should set enforce sharing from metadata');
    }
    
    @isTest
    static void testBuildCacheOptionsStorageTypes() {
        // Test Transaction Only
        SOQL_Stored_Procedure__mdt proc1 = new SOQL_Stored_Procedure__mdt(
            Cache_Storage__c = 'Transaction Only'
        );
        SOQLQueryCache.CacheOptions opts1 = SOQLStoredProcedure.buildCacheOptions(proc1);
        System.assertEquals(SOQLQueryCache.CacheStorage.TRANSACTION_ONLY, opts1.storage);
        
        // Test Both
        SOQL_Stored_Procedure__mdt proc2 = new SOQL_Stored_Procedure__mdt(
            Cache_Storage__c = 'Both'
        );
        SOQLQueryCache.CacheOptions opts2 = SOQLStoredProcedure.buildCacheOptions(proc2);
        System.assertEquals(SOQLQueryCache.CacheStorage.BOTH, opts2.storage);
        
        // Test null/empty (should default to Transaction Only)
        SOQL_Stored_Procedure__mdt proc3 = new SOQL_Stored_Procedure__mdt();
        SOQLQueryCache.CacheOptions opts3 = SOQLStoredProcedure.buildCacheOptions(proc3);
        System.assertEquals(SOQLQueryCache.CacheStorage.TRANSACTION_ONLY, opts3.storage);
    }
    
    @isTest
    static void testClearProcedureCache() {
        Test.startTest();
        
        // Clear by procedure name only
        SOQLStoredProcedure.clearProcedureCache('TestProcedure');
        
        // Clear by procedure name with parameters
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology'
        };
        SOQLStoredProcedure.clearProcedureCache('TestProcedure', params);
        
        Test.stopTest();
        
        // Should not throw exceptions
        System.assert(true, 'Clear operations should complete successfully');
    }
    
    @isTest
    static void testInvalidParameterDefinition() {
        SOQL_Stored_Procedure__mdt mockProc = createMockProcedure(
            'SELECT Id FROM Account',
            'invalid json'  // Invalid JSON
        );
        
        try {
            String query = SOQLStoredProcedure.buildQuery(mockProc, new Map<String, Object>());
            System.assert(false, 'Should throw exception for invalid parameter definition');
        } catch (SOQLStoredProcedure.StoredProcedureException e) {
            System.assert(e.getMessage().contains('Invalid parameter definition'), 
                'Should indicate invalid parameter definition');
        }
    }
    
    @isTest
    static void testExecuteWithInactiveProcedure() {
        // This test validates the logic for inactive procedures
        // In a real scenario, this would query actual metadata
        
        Test.startTest();
        
        // Since we can't create inactive procedures in test context,
        // we test that the listProcedures method filters correctly
        List<SOQL_Stored_Procedure__mdt> procedures = SOQLStoredProcedure.listProcedures();
        
        for (SOQL_Stored_Procedure__mdt proc : procedures) {
            System.assertEquals(true, proc.Active__c, 
                'listProcedures should only return active procedures');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testQueryWithCustomKeyIntegration() {
        // Test that stored procedures use custom cache keys
        String procName = 'TestProc';
        Map<String, Object> params = new Map<String, Object>{
            'industry' => 'Technology'
        };
        
        // Build the cache key that would be used
        String cacheKey = SOQLStoredProcedure.buildProcedureCacheKey(procName, params);
        
        System.assert(cacheKey.contains('SP:TestProc'), 'Should use procedure-based cache key');
        System.assert(cacheKey.contains('industry=Technology'), 'Should include parameters in key');
    }
    
    @isTest
    static void testParameterOrdering() {
        // Parameters in different order should produce same cache key
        Map<String, Object> params1 = new Map<String, Object>();
        params1.put('param1', 'value1');
        params1.put('param2', 'value2');
        params1.put('param3', 'value3');
        
        Map<String, Object> params2 = new Map<String, Object>();
        params2.put('param3', 'value3');
        params2.put('param1', 'value1');
        params2.put('param2', 'value2');
        
        String key1 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params1);
        String key2 = SOQLStoredProcedure.buildProcedureCacheKey('TestProc', params2);
        
        System.assertEquals(key1, key2, 'Different parameter order should produce same key');
    }
    
    // ========== Helper Methods ==========
    
    /**
     * Create a mock procedure for testing (can't insert custom metadata in tests)
     */
    private static SOQL_Stored_Procedure__mdt createMockProcedure(String query, String parameters) {
        return new SOQL_Stored_Procedure__mdt(
            DeveloperName = 'TestProcedure',
            Query__c = query,
            Parameters__c = parameters,
            Active__c = true,
            Cache_TTL__c = 300,
            Max_Results__c = 1000,
            Cache_Storage__c = 'Transaction Only',
            Enforce_Sharing__c = true
        );
    }
}