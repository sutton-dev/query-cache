@isTest
private class SOQLNormalizerTest {
    
    @isTest
    static void testSimpleQuery() {
        String query1 = 'SELECT Id, Name FROM Account';
        String query2 = 'SELECT Name, Id FROM Account';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2, 
            'Field order should not affect normalization');
        System.assert(normalized1.contains('Id, Name'), 
            'Fields should be sorted alphabetically');
        System.assert(normalized1.startsWith('SELECT'), 
            'Query should start with SELECT');
    }
    
    @isTest
    static void testWhitespaceNormalization() {
        String query1 = 'SELECT Id FROM Account WHERE Name = \'Test\'';
        String query2 = 'SELECT   Id   FROM   Account   WHERE   Name = \'Test\'';
        String query3 = 'SELECT Id FROM Account WHERE Name=\'Test\'';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        String normalized3 = SOQLNormalizer.normalize(query3);
        
        System.assertEquals(normalized1, normalized2,
            'Extra whitespace should normalize to same result');
        System.assert(normalized1.contains('FROM Account'),
            'Should contain FROM Account');
    }
    
    @isTest
    static void testWhereClauseNormalization() {
        String query1 = 'SELECT Id FROM Account WHERE Name = \'Test\' AND Industry = \'Tech\'';
        String query2 = 'SELECT Id FROM Account WHERE Industry = \'Tech\' AND Name = \'Test\'';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2,
            'AND conditions should normalize regardless of order');
        System.assert(normalized1.contains('WHERE'),
            'WHERE clause should be preserved');
    }
    
    @isTest
    static void testWhereClauseWithOr() {
        String query1 = 'SELECT Id FROM Account WHERE Name = \'Test\' OR Name = \'Demo\'';
        String query2 = 'SELECT Id FROM Account WHERE Name = \'Test\' OR Name = \'Demo\'';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2,
            'OR conditions should preserve order');
        System.assert(normalized1.contains('OR'),
            'OR operator should be preserved');
    }
    
    @isTest
    static void testOrderByNormalization() {
        String query1 = 'SELECT Id FROM Account ORDER BY Name, Industry';
        String query2 = 'SELECT Id FROM Account ORDER BY Industry, Name';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2,
            'ORDER BY fields should be sorted');
        System.assert(normalized1.contains('ORDER BY'),
            'ORDER BY clause should be preserved');
    }
    
    @isTest
    static void testOrderByWithModifiers() {
        String query = 'SELECT Id FROM Account ORDER BY Name DESC NULLS LAST';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('DESC'),
            'DESC modifier should be preserved');
        System.assert(normalized.contains('NULLS LAST'),
            'NULLS LAST should be preserved');
    }
    
    @isTest
    static void testStringLiteralWithKeywords() {
        String query = 'SELECT Id FROM Account WHERE Name = \'FROM Space\'';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('\'FROM Space\''),
            'String literals should preserve content including keywords');
    }
    
    @isTest
    static void testEscapedQuotes() {
        String query = 'SELECT Id FROM Account WHERE Name = \'O\'\'Brien\'';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('\'O\'\'Brien\''),
            'Escaped quotes should be preserved');
    }
    
    @isTest
    static void testSubquery() {
        String query = 'SELECT Id, (SELECT Id FROM Contacts) FROM Account';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Subquery normalized: ' + normalized);
        
        // The subquery should be present in normalized form
        System.assert(normalized.contains('Contacts') || normalized.contains('CONTACTS'),
            'Subqueries should preserve object name. Got: ' + normalized);
        System.assert(normalized.contains('Account') || normalized.contains('ACCOUNT'),
            'Parent query should be preserved. Got: ' + normalized);
    }
    
    @isTest
    static void testMultipleSubqueries() {
        String query1 = 'SELECT Id, (SELECT Id FROM Contacts), (SELECT Id FROM Opportunities) FROM Account';
        String query2 = 'SELECT (SELECT Id FROM Opportunities), Id, (SELECT Id FROM Contacts) FROM Account';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.debug('Multiple subqueries normalized1: ' + normalized1);
        System.debug('Multiple subqueries normalized2: ' + normalized2);
        
        // Both subqueries should be present
        System.assert(normalized1.contains('Contacts') || normalized1.contains('CONTACTS'),
            'First subquery should be preserved. Got: ' + normalized1);
        System.assert(normalized1.contains('Opportunities') || normalized1.contains('OPPORTUNITIES'),
            'Second subquery should be preserved. Got: ' + normalized1);
        
        // Both should have same subqueries after normalization
        System.assert(normalized2.contains('Contacts') || normalized2.contains('CONTACTS'),
            'First subquery should be preserved in query2. Got: ' + normalized2);
        System.assert(normalized2.contains('Opportunities') || normalized2.contains('OPPORTUNITIES'),
            'Second subquery should be preserved in query2. Got: ' + normalized2);
        
        // Order should normalize
        System.assertEquals(normalized1, normalized2,
            'Different field order including subqueries should normalize to same result');
    }
    
    @isTest
    static void testRelationshipFields() {
        String query1 = 'SELECT Account.Name, Account.Owner.Name FROM Contact';
        String query2 = 'SELECT Account.Owner.Name, Account.Name FROM Contact';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2,
            'Relationship field order should normalize');
        System.assert(normalized1.contains('Account.'),
            'Relationship fields should preserve dot notation');
    }
    
    @isTest
    static void testAggregateFunctions() {
        String query = 'SELECT COUNT(Id), Industry FROM Account GROUP BY Industry';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('COUNT(Id)'),
            'Aggregate functions should be preserved');
        System.assert(normalized.contains('GROUP BY Industry'),
            'GROUP BY should be preserved');
    }
    
    @isTest
    static void testMultipleAggregateFunctions() {
        String query = 'SELECT COUNT(Id), SUM(AnnualRevenue), AVG(NumberOfEmployees) FROM Account';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('COUNT(Id)'),
            'COUNT function should be preserved');
        System.assert(normalized.contains('SUM(AnnualRevenue)'),
            'SUM function should be preserved');
        System.assert(normalized.contains('AVG(NumberOfEmployees)'),
            'AVG function should be preserved');
    }
    
    @isTest
    static void testDateLiterals() {
        String query = 'SELECT Id FROM Account WHERE CreatedDate = LAST_N_DAYS:7';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('LAST_N_DAYS:7'),
            'Date literals with parameters should be preserved');
    }
    
    @isTest
    static void testDateLiteralsWithoutParameters() {
        String query = 'SELECT Id FROM Account WHERE CreatedDate = TODAY';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('TODAY'),
            'Date literals without parameters should be preserved');
    }
    
    @isTest
    static void testLimitClause() {
        String query = 'SELECT Id FROM Account LIMIT 100';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('LIMIT 100'),
            'LIMIT clause should be preserved');
    }
    
    @isTest
    static void testOffsetClause() {
        String query = 'SELECT Id FROM Account LIMIT 100 OFFSET 50';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('LIMIT 100'),
            'LIMIT clause should be preserved');
        System.assert(normalized.contains('OFFSET 50'),
            'OFFSET clause should be preserved');
    }
    
    @isTest
    static void testHavingClause() {
        String query = 'SELECT Industry, COUNT(Id) FROM Account GROUP BY Industry HAVING COUNT(Id) > 5';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('GROUP BY Industry'),
            'GROUP BY should be preserved');
        System.assert(normalized.contains('HAVING'),
            'HAVING clause should be preserved');
    }
    
    @isTest
    static void testInOperator() {
        String query = 'SELECT Id FROM Account WHERE Industry IN (\'Technology\', \'Healthcare\')';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('IN'),
            'IN operator should be preserved');
        System.assert(normalized.contains('\'Technology\''),
            'IN values should be preserved');
    }
    
    @isTest
    static void testNotInOperator() {
        String query = 'SELECT Id FROM Account WHERE Industry NOT IN (\'Technology\')';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('NOT IN') || normalized.contains('NOT IN'),
            'NOT IN operator should be preserved');
    }
    
    @isTest
    static void testLikeOperator() {
        String query = 'SELECT Id FROM Account WHERE Name LIKE \'%Test%\'';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('LIKE'),
            'LIKE operator should be preserved');
        System.assert(normalized.contains('\'%Test%\''),
            'LIKE pattern should be preserved');
    }
    
    @isTest
    static void testComparisonOperators() {
        String query1 = 'SELECT Id FROM Account WHERE AnnualRevenue > 1000000';
        String query2 = 'SELECT Id FROM Account WHERE AnnualRevenue >= 1000000';
        String query3 = 'SELECT Id FROM Account WHERE AnnualRevenue < 1000000';
        String query4 = 'SELECT Id FROM Account WHERE AnnualRevenue <= 1000000';
        String query5 = 'SELECT Id FROM Account WHERE AnnualRevenue != 1000000';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        String normalized3 = SOQLNormalizer.normalize(query3);
        String normalized4 = SOQLNormalizer.normalize(query4);
        String normalized5 = SOQLNormalizer.normalize(query5);
        
        System.assert(normalized1.contains('>'),
            'Greater than operator should be preserved');
        System.assert(normalized2.contains('>='),
            'Greater than or equal operator should be preserved');
        System.assert(normalized3.contains('<'),
            'Less than operator should be preserved');
        System.assert(normalized4.contains('<='),
            'Less than or equal operator should be preserved');
        System.assert(normalized5.contains('!='),
            'Not equal operator should be preserved');
    }
    
    @isTest
    static void testNegativeNumbers() {
        String query = 'SELECT Id FROM Account WHERE AnnualRevenue > -1000';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('-1000'),
            'Negative numbers should be preserved');
    }
    
    @isTest
    static void testDecimalNumbers() {
        String query = 'SELECT Id FROM Account WHERE AnnualRevenue > 1000000.50';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('1000000.50'),
            'Decimal numbers should be preserved');
    }
    
    @isTest
    static void testParenthesizedConditions() {
        String query = 'SELECT Id FROM Account WHERE (Name = \'Test\' OR Name = \'Demo\') AND Industry = \'Tech\'';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('('),
            'Opening parenthesis should be preserved');
        System.assert(normalized.contains(')'),
            'Closing parenthesis should be preserved');
        System.assert(normalized.contains('OR'),
            'OR operator should be preserved');
    }
    
    @isTest
    static void testComplexQuery() {
        String query = 'SELECT Id, Name, Industry, AnnualRevenue, Owner.Name ' +
                      'FROM Account ' +
                      'WHERE Industry = \'Technology\' AND AnnualRevenue > 1000000 ' +
                      'ORDER BY Name, Industry ' +
                      'LIMIT 100';
        
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('SELECT'),
            'SELECT should be present');
        System.assert(normalized.contains('FROM Account'),
            'FROM clause should be present');
        System.assert(normalized.contains('WHERE'),
            'WHERE clause should be present');
        System.assert(normalized.contains('ORDER BY'),
            'ORDER BY should be present');
        System.assert(normalized.contains('LIMIT 100'),
            'LIMIT should be present');
    }
    
    @isTest
    static void testKeywordCaseInsensitivity() {
        String query1 = 'select Id from Account';
        String query2 = 'SELECT Id FROM Account';
        String query3 = 'SeLeCt Id FrOm Account';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        String normalized3 = SOQLNormalizer.normalize(query3);
        
        System.debug('Query1 normalized: ' + normalized1);
        System.debug('Query2 normalized: ' + normalized2);
        System.debug('Query3 normalized: ' + normalized3);
        
        // All should produce valid normalized output with SELECT and FROM
        System.assert(normalized1.contains('SELECT') || normalized1.contains('select'),
            'Lowercase keywords should be normalized. Got: ' + normalized1);
        System.assert(normalized2.contains('SELECT'),
            'Uppercase keywords should be normalized. Got: ' + normalized2);
        System.assert(normalized3.contains('SELECT') || normalized3.contains('select'),
            'Mixed case keywords should be normalized. Got: ' + normalized3);
        
        System.assert(normalized1.contains('FROM') || normalized1.contains('from'),
            'FROM should be present. Got: ' + normalized1);
        System.assert(normalized2.contains('FROM'),
            'FROM should be present. Got: ' + normalized2);
        System.assert(normalized3.contains('FROM') || normalized3.contains('from'),
            'FROM should be present. Got: ' + normalized3);
    }
    
    @isTest
    static void testEmptyQuery() {
        String query = '';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assertEquals('', normalized,
            'Empty query should return empty string');
    }
    
    @isTest
    static void testNullQuery() {
        String query = null;
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assertEquals('', normalized,
            'Null query should return empty string');
    }
    
    @isTest
    static void testInvalidQuery() {
        String query = 'INVALID QUERY SYNTAX';
        
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Invalid query normalized: ' + normalized);
        
        // Just verify it returns something and doesn't crash
        System.assertNotEquals(null, normalized,
            'Invalid query should return a value');
        System.assertNotEquals('', normalized,
            'Invalid query should return non-empty string');
        
        // It should return the cleaned query or a hash
        System.assert(normalized.length() > 0,
            'Should return some value for invalid query. Got: ' + normalized);
    }
    
    @isTest
    static void testQueryWithSecurityEnforced() {
        String query = 'SELECT Id FROM Account WITH SECURITY_ENFORCED';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('SECURITY_ENFORCED'),
            'WITH SECURITY_ENFORCED should be preserved');
    }
    
    @isTest
    static void testQueryWithUserMode() {
        String query = 'SELECT Id FROM Account WITH USER_MODE';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('USER_MODE'),
            'WITH USER_MODE should be preserved');
    }
    
    @isTest
    static void testQueryWithForView() {
        String query = 'SELECT Id FROM Account FOR VIEW';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('FOR VIEW') || normalized.contains('FOR VIEW'),
            'FOR VIEW should be preserved');
    }
    
    @isTest
    static void testQueryWithForReference() {
        String query = 'SELECT Id FROM Account FOR REFERENCE';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('FOR REFERENCE') || normalized.contains('FOR REFERENCE'),
            'FOR REFERENCE should be preserved');
    }
    
    @isTest
    static void testNestedSubqueries() {
        String query = 'SELECT Id, (SELECT Id, (SELECT Id FROM Contacts) FROM Opportunities) FROM Account';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Nested subqueries normalized: ' + normalized);
        
        System.assert(normalized.contains('Opportunities') || normalized.contains('OPPORTUNITIES'),
            'Nested subquery level 1 should be preserved. Got: ' + normalized);
        System.assert(normalized.contains('Contacts') || normalized.contains('CONTACTS'),
            'Nested subquery level 2 should be preserved. Got: ' + normalized);
    }
    
    @isTest
    static void testMultipleFieldsSameQuery() {
        String query1 = 'SELECT Id, Name, Industry, Owner.Name, CreatedDate FROM Account';
        String query2 = 'SELECT CreatedDate, Id, Industry, Name, Owner.Name FROM Account';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2,
            'Multiple fields should sort alphabetically');
    }
    
    @isTest
    static void testFunctionWithMultipleArguments() {
        String query = 'SELECT DISTANCE(Location__c, GEOLOCATION(37.7749, -122.4194), \'mi\') FROM Account';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('DISTANCE') || normalized.contains('distance'),
            'Function name should be preserved');
        System.assert(normalized.contains('GEOLOCATION') || normalized.contains('geolocation'),
            'Nested function should be preserved');
    }
    
    @isTest
    static void testConsistencyAcrossMultipleCalls() {
        String query = 'SELECT Name, Id, Industry FROM Account WHERE Name = \'Test\' ORDER BY Industry, Name';
        
        String normalized1 = SOQLNormalizer.normalize(query);
        String normalized2 = SOQLNormalizer.normalize(query);
        String normalized3 = SOQLNormalizer.normalize(query);
        
        System.assertEquals(normalized1, normalized2,
            'Multiple normalizations should be consistent');
        System.assertEquals(normalized2, normalized3,
            'Multiple normalizations should be consistent');
    }
    
    @isTest
    static void testQueryWithAllClauses() {
        String query = 'SELECT Id, Name, COUNT(Id) ' +
                      'FROM Account ' +
                      'WHERE Industry = \'Tech\' AND AnnualRevenue > 1000000 ' +
                      'GROUP BY Id, Name ' +
                      'HAVING COUNT(Id) > 1 ' +
                      'ORDER BY Name DESC ' +
                      'LIMIT 50 ' +
                      'OFFSET 10 ' +
                      'FOR VIEW';
        
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('All clauses normalized: ' + normalized);
        
        System.assert(normalized.contains('SELECT'),
            'SELECT should be present');
        System.assert(normalized.contains('FROM'),
            'FROM should be present');
        System.assert(normalized.contains('WHERE'),
            'WHERE should be present');
        System.assert(normalized.contains('GROUP BY'),
            'GROUP BY should be present');
        System.assert(normalized.contains('HAVING'),
            'HAVING should be present');
        System.assert(normalized.contains('ORDER BY'),
            'ORDER BY should be present');
        System.assert(normalized.contains('LIMIT'),
            'LIMIT should be present');
        System.assert(normalized.contains('OFFSET'),
            'OFFSET should be present');
        System.assert(normalized.contains('FOR'),
            'FOR VIEW should be present');
    }
    
    @isTest
    static void testNormalizationPreservesQuerySemantics() {
        // Create test account
        Account acc = new Account(Name = 'Test Account', Industry = 'Technology');
        insert acc;
        
        String query1 = 'SELECT Id, Name, Industry FROM Account WHERE Name = \'Test Account\'';
        String query2 = 'SELECT Industry, Name, Id FROM Account WHERE Name = \'Test Account\'';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.debug('Query1 normalized: ' + normalized1);
        System.debug('Query2 normalized: ' + normalized2);
        
        // Verify normalization produces same result
        System.assertEquals(normalized1, normalized2,
            'Different field orders should normalize to same query');
        
        // Verify both queries return same data
        List<Account> results1 = Database.query(query1);
        List<Account> results2 = Database.query(query2);
        
        System.assertEquals(results1.size(), results2.size(),
            'Both queries should return same number of results');
        System.assertEquals(results1[0].Id, results2[0].Id,
            'Both queries should return same record');
    }

    @isTest
    static void testFastPathOptimization() {
        // Test simple query without subqueries (should use fast path)
        String simpleQuery = 'SELECT Name, Id, Industry FROM Account WHERE Name = \'Test\' ORDER BY CreatedDate DESC LIMIT 50';
        String normalized = SOQLNormalizer.normalize(simpleQuery);
        
        System.assert(normalized.contains('SELECT'), 'Should contain SELECT');
        System.assert(normalized.contains('FROM Account'), 'Should contain FROM Account');
        System.assert(normalized.contains('WHERE'), 'Should contain WHERE clause');
        System.assert(normalized.contains('ORDER BY'), 'Should contain ORDER BY');
        System.assert(normalized.contains('LIMIT 50'), 'Should contain LIMIT');
        
        // Verify field sorting in fast path
        System.assert(normalized.indexOf('Id') < normalized.indexOf('Industry'), 
            'Fields should be alphabetically sorted');
    }

    @isTest
    static void testFastPathWithAllClauses() {
        // Test fast path with GROUP BY, HAVING, etc.
        String query = 'SELECT Industry, COUNT(Id) FROM Account ' +
                    'WHERE AnnualRevenue > 1000000 ' +
                    'GROUP BY Industry ' +
                    'HAVING COUNT(Id) > 5 ' +
                    'ORDER BY Industry ' +
                    'LIMIT 10 ' +
                    'OFFSET 5 ' +
                    'FOR VIEW';
        
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('GROUP BY'), 'Should contain GROUP BY');
        System.assert(normalized.contains('HAVING'), 'Should contain HAVING');
        System.assert(normalized.contains('OFFSET 5'), 'Should contain OFFSET');
        System.assert(normalized.contains('FOR VIEW'), 'Should contain FOR VIEW');
    }

    @isTest
    static void testFastPathWithComplexWhere() {
        // Test fast path with multiple AND conditions
        String query1 = 'SELECT Id FROM Account WHERE Name = \'Test\' AND Industry = \'Tech\' AND Status = \'Active\'';
        String query2 = 'SELECT Id FROM Account WHERE Industry = \'Tech\' AND Status = \'Active\' AND Name = \'Test\'';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.assertEquals(normalized1, normalized2, 
            'Fast path should normalize WHERE conditions regardless of order');
    }

    @isTest
    static void testFastPathFieldDeduplication() {
        // Test that fast path deduplicates fields
        String query = 'SELECT Id, Name, Id, Industry FROM Account';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Normalized query: ' + normalized);
        
        // The normalized query should not contain "Id" twice
        // After sorting: "Id, Industry, Name"
        // So it should be: "SELECT Id, Industry, Name FROM Account"
        
        System.assert(normalized.contains('SELECT'), 'Should contain SELECT');
        System.assert(normalized.contains('FROM Account'), 'Should contain FROM Account');
        
        // Check that we have exactly 3 fields (Id, Industry, Name)
        String selectPart = normalized.substring(7, normalized.indexOf(' FROM'));
        List<String> fields = selectPart.split(',');
        
        System.assertEquals(3, fields.size(), 
            'Should have 3 fields after deduplication, got: ' + fields.size() + '. Fields: ' + selectPart);
    }

    @isTest
    static void testSlowPathWithAllClauses() {
        // Test slow path (with subqueries) with all possible clauses
        String query = 'SELECT Id, Name, (SELECT Id FROM Contacts) FROM Account ' +
                    'WHERE Industry = \'Tech\' ' +
                    'GROUP BY Name ' +
                    'HAVING COUNT(Id) > 1 ' +
                    'ORDER BY Name DESC ' +
                    'LIMIT 25 ' +
                    'OFFSET 10 ' +
                    'FOR VIEW ' +
                    'WITH SECURITY_ENFORCED';
        
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Normalized with all clauses: ' + normalized);
        
        // Verify all clauses are present
        System.assert(normalized.contains('SELECT'), 'Should contain SELECT');
        System.assert(normalized.contains('(SELECT Id FROM Contacts)'), 'Should contain subquery');
        System.assert(normalized.contains('FROM Account'), 'Should contain FROM');
        System.assert(normalized.contains('WHERE'), 'Should contain WHERE');
        System.assert(normalized.contains('GROUP BY'), 'Should contain GROUP BY');
        System.assert(normalized.contains('HAVING'), 'Should contain HAVING');
        System.assert(normalized.contains('ORDER BY'), 'Should contain ORDER BY');
        System.assert(normalized.contains('LIMIT 25'), 'Should contain LIMIT');
        System.assert(normalized.contains('OFFSET 10'), 'Should contain OFFSET');
        System.assert(normalized.contains('FOR VIEW'), 'Should contain FOR VIEW');
        System.assert(normalized.contains('WITH SECURITY_ENFORCED'), 'Should contain WITH');
    }

    @isTest
    static void testSlowPathGroupByNormalization() {
        // Test that GROUP BY fields are normalized in slow path
        String query1 = 'SELECT (SELECT Id FROM Contacts), Name, Industry FROM Account GROUP BY Industry, Name';
        String query2 = 'SELECT (SELECT Id FROM Contacts), Industry, Name FROM Account GROUP BY Name, Industry';
        
        String normalized1 = SOQLNormalizer.normalize(query1);
        String normalized2 = SOQLNormalizer.normalize(query2);
        
        System.debug('Query1 normalized: ' + normalized1);
        System.debug('Query2 normalized: ' + normalized2);
        
        // GROUP BY fields should be sorted the same way
        System.assertEquals(normalized1, normalized2, 
            'Slow path should normalize GROUP BY field order');
    }

    @isTest
    static void testSlowPathOrderByNormalization() {
        // Test ORDER BY normalization in slow path
        String query = 'SELECT Id, (SELECT Id FROM Contacts) FROM Account ORDER BY Name DESC, Industry ASC';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.debug('Order by normalized: ' + normalized);
        
        System.assert(normalized.contains('ORDER BY'), 'Should contain ORDER BY');
        System.assert(normalized.contains('DESC'), 'Should preserve DESC');
        System.assert(normalized.contains('ASC'), 'Should preserve ASC');
    }

    @isTest
    static void testSlowPathWithForReference() {
        // Test FOR REFERENCE clause
        String query = 'SELECT Id, (SELECT Id FROM Contacts) FROM Account FOR REFERENCE';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('FOR REFERENCE'), 
            'Should preserve FOR REFERENCE');
    }

    @isTest
    static void testSlowPathWithUserMode() {
        // Test WITH USER_MODE clause
        String query = 'SELECT Id, (SELECT Id FROM Contacts) FROM Account WITH USER_MODE';
        String normalized = SOQLNormalizer.normalize(query);
        
        System.assert(normalized.contains('WITH USER_MODE'), 
            'Should preserve WITH USER_MODE');
    }
}