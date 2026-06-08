public class AccountSalesHelper {
    public static void updateSalesGuidance(List<Account> accounts) {
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }

        // Query recent open opportunities (last 90 days) extra text
        Map<Id, Boolean> recentOpenOpps = new Map<Id, Boolean>();
        for (Opportunity opp : [
            SELECT AccountId FROM Opportunity 
            WHERE AccountId IN :accountIds 
            AND CloseDate >= LAST_N_DAYS:90 
            AND StageName NOT IN ('Closed Won', 'Closed Lost')
        ]) {
            recentOpenOpps.put(opp.AccountId, true);
        }

        // Query closed-won opportunities (last 6 months)
        Map<Id, Boolean> recentClosedWonOpps = new Map<Id, Boolean>();
        for (Opportunity opp : [
            SELECT AccountId FROM Opportunity 
            WHERE AccountId IN :accountIds 
            AND CloseDate >= LAST_N_DAYS:180 
            AND StageName = 'Closed Won'
        ]) {
            recentClosedWonOpps.put(opp.AccountId, true);
        }

        // Store old values for logging
        Map<Id, Account> oldAccountValues = new Map<Id, Account>();
        for (Account acc : accounts) {
            oldAccountValues.put(acc.Id, acc.clone(true, true, false, false));
        }

        // Apply new logic
        for (Account acc : accounts) {
            if (recentOpenOpps.containsKey(acc.Id)) {
                acc.Priority_Level__c = 'High';
            } else if (acc.AnnualRevenue > 1000000) {
                acc.Priority_Level__c = 'High';
            } else if (acc.AnnualRevenue > 500000) {
                acc.Priority_Level__c = 'Medium';
            } else {
                acc.Priority_Level__c = 'Low';
            }

            if (recentClosedWonOpps.containsKey(acc.Id)) {
                acc.Next_Best_Action__c = 'Send a thank-you email';
            } else if (acc.LastActivityDate == null) {
                acc.Next_Best_Action__c = 'Reach out to establish contact';
            } else if (acc.Priority_Level__c == 'High') {
                acc.Next_Best_Action__c = 'Schedule a follow-up meeting';
            } else {
                acc.Next_Best_Action__c = 'Review account details and prepare for next steps';
            }
        }

        // Log updates
        logAccountUpdates(accounts, oldAccountValues);
    }

    // New method to log changes to Priority_Level__c and Next_Best_Action__c
    public static void logAccountUpdates(List<Account> accounts, Map<Id, Account> oldAccountValues) {
        List<SObject> logs = new List<SObject>();
        for (Account acc : accounts) {
            Account oldAcc = oldAccountValues.get(acc.Id);
            
            // Log Priority_Level__c changes
            if (oldAcc.Priority_Level__c != acc.Priority_Level__c) {
                SObject log = createLogRecord(
                    acc.Id,
                    'Priority_Level__c',
                    oldAcc.Priority_Level__c,
                    acc.Priority_Level__c
                );
                if (log != null) {
                    logs.add(log);
                }
            }

            // Log Next_Best_Action__c changes
            if (oldAcc.Next_Best_Action__c != acc.Next_Best_Action__c) {
                SObject log = createLogRecord(
                    acc.Id,
                    'Next_Best_Action__c',
                    oldAcc.Next_Best_Action__c,
                    acc.Next_Best_Action__c
                );
                if (log != null) {
                    logs.add(log);
                }
            }
        }

        if (!logs.isEmpty()) {
            try {
                insert logs;
            } catch (Exception e) {
                // Log error to custom object or debug for audit (non-blocking)
                System.debug('Error inserting log records: ' + e.getMessage());
            }
        }
    }

    // Helper method to create a log record (dynamic to handle Log__c availability)
    private static SObject createLogRecord(Id accountId, String fieldName, String oldValue, String newValue) {
        // Check if Log__c object exists (for compilation safety)
        if (Schema.getGlobalDescribe().containsKey('Log__c')) {
            SObject log = Schema.getGlobalDescribe().get('Log__c').newSObject();
            log.put('Account__c', accountId);
            log.put('Field_Name__c', fieldName);
            log.put('Old_Value__c', oldValue);
            log.put('New_Value__c', newValue);
            log.put('Change_Date__c', DateTime.now());
            return log;
        } else {
            // Fallback for compilation if Log__c doesn't exist
            System.debug('Log__c object not found. Skipping log for Account: ' + accountId);
            return null;
        }
    }
}