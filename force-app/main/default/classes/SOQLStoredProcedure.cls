/**
 * Stored Procedure executor
 * Executes named queries from Custom Metadata with parameter binding
 */
public class SOQLStoredProcedure {
    
    /**
     * Execute a stored procedure by name
     */
    public static List<SObject> execute(String procedureName) {
        return execute(procedureName, new Map<String, Object>(), null);
    }
    
    /**
     * Execute a stored procedure with parameters
     */
    public static List<SObject> execute(String procedureName, Map<String, Object> params) {
        return execute(procedureName, params, null);
    }
    
    /**
     * Execute a stored procedure with parameters and cache options
     */
    public static List<SObject> execute(String procedureName, Map<String, Object> params, SOQLQueryCache.CacheOptions options) {
        // Load stored procedure from Custom Metadata
        SOQL_Stored_Procedure__mdt procedure = getStoredProcedure(procedureName);
        
        if (procedure == null) {
            throw new StoredProcedureException('Stored procedure not found: ' + procedureName);
        }
        
        if (!procedure.Active__c) {
            throw new StoredProcedureException('Stored procedure is inactive: ' + procedureName);
        }
        
        // Build query with parameter binding
        String query = buildQuery(procedure, params);
        
        // Use cache options from metadata if not provided
        if (options == null) {
            options = buildCacheOptions(procedure);
        }
        
        // Execute through cache using procedure name + params as cache key
        return queryWithCustomKey(procedureName, params, query, options);
    }
    
    /**
     * Get stored procedure metadata
     */
    private static SOQL_Stored_Procedure__mdt getStoredProcedure(String name) {
        List<SOQL_Stored_Procedure__mdt> procedures = [
            SELECT Id, DeveloperName, Label, Query__c, Description__c, 
                   Parameters__c, Cache_TTL__c, Active__c, Max_Results__c,
                   Cache_Storage__c, Enforce_Sharing__c
            FROM SOQL_Stored_Procedure__mdt
            WHERE DeveloperName = :name
            LIMIT 1
        ];
        
        return procedures.isEmpty() ? null : procedures[0];
    }
    
    /**
     * Build query with parameter binding
     */
    private static String buildQuery(SOQL_Stored_Procedure__mdt procedure, Map<String, Object> params) {
        String query = procedure.Query__c;
        
        if (String.isBlank(procedure.Parameters__c)) {
            return query;
        }
        
        // Parse parameter definitions (JSON array of parameter names)
        List<String> paramNames;
        try {
            paramNames = (List<String>)JSON.deserialize(procedure.Parameters__c, List<String>.class);
        } catch (Exception e) {
            throw new StoredProcedureException('Invalid parameter definition: ' + e.getMessage());
        }
        
        // Replace parameters in query
        for (String paramName : paramNames) {
            if (!params.containsKey(paramName)) {
                throw new StoredProcedureException('Missing required parameter: ' + paramName);
            }
            
            Object paramValue = params.get(paramName);
            String placeholder = ':' + paramName;
            
            // Handle different parameter types
            String replacement;
            if (paramValue instanceof String) {
                replacement = '\'' + String.escapeSingleQuotes((String)paramValue) + '\'';
            } else if (paramValue instanceof List<Object>) {
                List<String> values = new List<String>();
                for (Object val : (List<Object>)paramValue) {
                    if (val instanceof String) {
                        values.add('\'' + String.escapeSingleQuotes((String)val) + '\'');
                    } else {
                        values.add(String.valueOf(val));
                    }
                }
                replacement = '(' + String.join(values, ', ') + ')';
            } else {
                replacement = String.valueOf(paramValue);
            }
            
            query = query.replace(placeholder, replacement);
        }
        
        return query;
    }
    
    /**
     * Build cache options from metadata
     */
    private static SOQLQueryCache.CacheOptions buildCacheOptions(SOQL_Stored_Procedure__mdt procedure) {
        SOQLQueryCache.CacheOptions options = new SOQLQueryCache.CacheOptions();
        
        // Set TTL
        if (procedure.Cache_TTL__c != null) {
            options.setTTL(procedure.Cache_TTL__c.intValue());
        }
        
        // Set max results
        if (procedure.Max_Results__c != null) {
            options.setMaxResults(procedure.Max_Results__c.intValue());
        }
        
        // Set storage type
        if (String.isNotBlank(procedure.Cache_Storage__c)) {
            if (procedure.Cache_Storage__c == 'Platform Cache') {
                options.setStorage(SOQLQueryCache.CacheStorage.PLATFORM_CACHE);
            } else if (procedure.Cache_Storage__c == 'Both') {
                options.setStorage(SOQLQueryCache.CacheStorage.BOTH);
            } else {
                options.setStorage(SOQLQueryCache.CacheStorage.TRANSACTION_ONLY);
            }
        }
        
        // Set sharing enforcement
        if (procedure.Enforce_Sharing__c != null) {
            options.setEnforceSharing(procedure.Enforce_Sharing__c);
        }
        
        return options;
    }
    
    /**
     * Execute query with custom cache key (used by stored procedures)
     */
    private static List<SObject> queryWithCustomKey(String procedureName, Map<String, Object> params, String query, SOQLQueryCache.CacheOptions options) {
        // Build cache key from procedure name + sorted parameters
        String cacheKey = buildProcedureCacheKey(procedureName, params);
        
        return SOQLQueryCache.queryWithKey(query, cacheKey, options);
    }
    
    /**
     * Build cache key for stored procedure
     * Format: procedureName|param1=value1|param2=value2
     */
    private static String buildProcedureCacheKey(String procedureName, Map<String, Object> params) {
        List<String> keyParts = new List<String>{ 'SP:' + procedureName };
        
        if (params != null && !params.isEmpty()) {
            // Sort parameter names for consistent keys
            List<String> paramNames = new List<String>(params.keySet());
            paramNames.sort();
            
            for (String paramName : paramNames) {
                Object value = params.get(paramName);
                String valueStr;
                
                if (value instanceof List<Object>) {
                    // For lists, create a sorted string representation
                    List<String> listValues = new List<String>();
                    for (Object v : (List<Object>)value) {
                        listValues.add(String.valueOf(v));
                    }
                    listValues.sort();
                    valueStr = '[' + String.join(listValues, ',') + ']';
                } else {
                    valueStr = String.valueOf(value);
                }
                
                keyParts.add(paramName + '=' + valueStr);
            }
        }
        
        return String.join(keyParts, '|');
    }
    
    /**
     * Clear cached results for a specific stored procedure
     */
    public static void clearProcedureCache(String procedureName) {
        clearProcedureCache(procedureName, null);
    }
    
    /**
     * Clear cached results for a stored procedure with specific parameters
     */
    public static void clearProcedureCache(String procedureName, Map<String, Object> params) {
        String cacheKey = buildProcedureCacheKey(procedureName, params);
        SOQLQueryCache.clearCacheKey(cacheKey);
    }
    public static List<SOQL_Stored_Procedure__mdt> listProcedures() {
        return [
            SELECT Id, DeveloperName, Label, Description__c, Active__c
            FROM SOQL_Stored_Procedure__mdt
            WHERE Active__c = true
            ORDER BY Label
        ];
    }
    
    /**
     * Custom exception for stored procedure errors
     */
    public class StoredProcedureException extends Exception {}
}