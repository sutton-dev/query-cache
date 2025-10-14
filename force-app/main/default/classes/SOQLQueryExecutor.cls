/**
 * Query executor with explicit sharing context
 * Used by SOQLQueryCache to enforce or bypass sharing rules
 */
public inherited sharing class SOQLQueryExecutor {

    /**
     * Execute query WITH sharing rules enforced
     */
    public static List<SObject> executeWithSharing(String soql) {
        return new WithSharingExecutor().execute(soql);
    }

    /**
     * Execute query WITHOUT sharing rules (respects user permissions, not sharing)
     */
    public static List<SObject> executeWithoutSharing(String soql) {
        return new WithoutSharingExecutor().execute(soql);
    }

    /**
     * Inner class with sharing enforced
     */
    private with sharing class WithSharingExecutor {
        public List<SObject> execute(String soql) {
            return Database.query(soql);
        }
    }

    /**
     * Inner class without sharing enforced
     */
    private without sharing class WithoutSharingExecutor {
        public List<SObject> execute(String soql) {
            return Database.query(soql);
        }
    }
}
