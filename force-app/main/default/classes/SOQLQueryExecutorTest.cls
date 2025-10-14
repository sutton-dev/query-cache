/**
 * Test class for SOQLQueryExecutor
 * Validates with sharing and without sharing enforcement
 */
@IsTest
private class SOQLQueryExecutorTest {

    @TestSetup
    static void setupTestData() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = 'Technology'
            ));
        }
        insert accounts;
    }

    @IsTest
    static void testExecuteWithSharing() {
        // Test that with sharing executes successfully
        String query = 'SELECT Id, Name FROM Account LIMIT 5';

        Test.startTest();
        List<SObject> results = SOQLQueryExecutor.executeWithSharing(query);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return 5 accounts with sharing');
    }

    @IsTest
    static void testExecuteWithoutSharing() {
        // Test that without sharing executes successfully
        String query = 'SELECT Id, Name FROM Account LIMIT 5';

        Test.startTest();
        List<SObject> results = SOQLQueryExecutor.executeWithoutSharing(query);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return 5 accounts without sharing');
    }

    @IsTest
    static void testSharingDifference() {
        // This test demonstrates the difference between with and without sharing
        // In a real org with sharing rules, the results would differ
        // In test context, both should return same results as test data is visible to test user

        String query = 'SELECT Id, Name FROM Account';

        Test.startTest();
        List<SObject> withSharingResults = SOQLQueryExecutor.executeWithSharing(query);
        List<SObject> withoutSharingResults = SOQLQueryExecutor.executeWithoutSharing(query);
        Test.stopTest();

        // In test context, both should see the same records
        System.assertEquals(5, withSharingResults.size(), 'With sharing should return all test accounts');
        System.assertEquals(5, withoutSharingResults.size(), 'Without sharing should return all test accounts');

        // Note: In production with actual sharing rules, withoutSharingResults might return more records
    }

    @IsTest
    static void testComplexQuery() {
        // Test with a more complex query
        String query = 'SELECT Id, Name, Industry FROM Account WHERE Industry = \'Technology\' ORDER BY Name';

        Test.startTest();
        List<SObject> results = SOQLQueryExecutor.executeWithSharing(query);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return all technology accounts');
        for (SObject acc : results) {
            System.assertEquals('Technology', ((Account)acc).Industry, 'All accounts should be Technology industry');
        }
    }

    @IsTest
    static void testEmptyResults() {
        // Test query that returns no results
        String query = 'SELECT Id, Name FROM Account WHERE Name = \'NonExistent\'';

        Test.startTest();
        List<SObject> results = SOQLQueryExecutor.executeWithSharing(query);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return 0 accounts');
    }
}
