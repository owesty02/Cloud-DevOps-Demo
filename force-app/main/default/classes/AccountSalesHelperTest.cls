
@isTest
private class AccountSalesHelperTest {

    /**
     * Utility method to create and insert a completed Task to set LastActivityDate on an Account.
     */
    private static Task createCompletedTaskForAccount(Id accountId) {
        Task t = new Task(
            WhatId   = accountId,
            Subject  = 'Completed Outreach',
            Status   = 'Completed',
            Priority = 'Normal'
        );
        insert t;
        return t;
    }

    /**
     * Test updateSalesGuidance with multiple Accounts to cover:
     * - Priority set due to recent open Opportunity (High)
     * - Priority set due to AnnualRevenue > 1,000,000 (High)
     * - Priority set due to AnnualRevenue > 500,000 (Medium)
     * - Default Priority (Low)
     * And Next_Best_Action__c scenarios:
     * - Recent Closed Won -> 'Send a thank-you email'
     * - LastActivityDate == null -> 'Reach out to establish contact'
     * - Priority High and has activity -> 'Schedule a follow-up meeting'
     * - Default -> 'Review account details and prepare for next steps'
     */
    @isTest
    static void testUpdateSalesGuidance_AllBranches() {
        // Create Accounts for scenarios
        Account accOpenOpp = new Account(Name = 'Acct - Open Opp', AnnualRevenue = 100);
        Account accClosedWon = new Account(Name = 'Acct - Closed Won', AnnualRevenue = 600000);
        Account accHighRevenue = new Account(Name = 'Acct - High Revenue', AnnualRevenue = 1500000);
        Account accLowDefault = new Account(Name = 'Acct - Low Default', AnnualRevenue = 1000);
        insert new List<Account>{ accOpenOpp, accClosedWon, accHighRevenue, accLowDefault };

        // Create a recent open opportunity (Stage not Closed Won/Lost) for accOpenOpp
        Opportunity oo = new Opportunity(
            Name = 'Open Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = accOpenOpp.Id
        );
        // Create a recent closed won opportunity for accClosedWon
        Opportunity cw = new Opportunity(
            Name = 'Closed Won Opp',
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-10),
            AccountId = accClosedWon.Id
        );
        insert new List<Opportunity>{ oo, cw };

        // Ensure LastActivityDate is not null for accOpenOpp and accLowDefault
        createCompletedTaskForAccount(accOpenOpp.Id);
        createCompletedTaskForAccount(accLowDefault.Id);
        // For accHighRevenue we intentionally do NOT create a Task to keep LastActivityDate null

        // Re-query accounts to populate LastActivityDate
        Map<Id, Account> refreshedAccs = new Map<Id, Account>([
            SELECT Id, Name, AnnualRevenue, LastActivityDate, Priority_Level__c, Next_Best_Action__c
            FROM Account
            WHERE Id IN :new Set<Id>{ accOpenOpp.Id, accClosedWon.Id, accHighRevenue.Id, accLowDefault.Id }
        ]);

        Account rOpenOpp     = refreshedAccs.get(accOpenOpp.Id);
        Account rClosedWon   = refreshedAccs.get(accClosedWon.Id);
        Account rHighRevenue = refreshedAccs.get(accHighRevenue.Id);
        Account rLowDefault  = refreshedAccs.get(accLowDefault.Id);

        Test.startTest();
        // Invoke the logic under test
        AccountSalesHelper.updateSalesGuidance(new List<Account>{ rOpenOpp, rClosedWon, rHighRevenue, rLowDefault });
        Test.stopTest();

        // Assertions for Priority_Level__c
        System.assertEquals('High',   rOpenOpp.Priority_Level__c,     'Open opp should force High priority.');
        System.assertEquals('Medium', rClosedWon.Priority_Level__c,   'AnnualRevenue 600k should set Medium priority when no open opp.');
        System.assertEquals('High',   rHighRevenue.Priority_Level__c, 'AnnualRevenue > 1,000,000 should be High.');
        System.assertEquals('Low',    rLowDefault.Priority_Level__c,  'Low revenue with no open opp should be Low.');

        // Assertions for Next_Best_Action__c
        System.assertEquals('Schedule a follow-up meeting', rOpenOpp.Next_Best_Action__c,
            'High priority with activity and no recent closed won should recommend scheduling a follow-up.');
        System.assertEquals('Send a thank-you email', rClosedWon.Next_Best_Action__c,
            'Recent closed won should recommend sending a thank-you email.');
        System.assertEquals('Reach out to establish contact', rHighRevenue.Next_Best_Action__c,
            'Null LastActivityDate should recommend to establish contact.');
        System.assertEquals('Review account details and prepare for next steps', rLowDefault.Next_Best_Action__c,
            'Default path for non-high priority with activity should recommend review/prep.');
    }

    /**
     * Test logAccountUpdates when there are NO changes between old and new records.
     * Ensures no DML is attempted (insert of logs) and method completes gracefully.
     */
    @isTest
    static void testLogAccountUpdates_NoChanges_NoDml() {
        // Prepare a single Account and its "old" clone state
        Account acc = new Account(Name = 'Acct - No Change', AnnualRevenue = 12345);
        insert acc;

        // Build old values map as a deep clone of the current state
        Account oldClone = acc.clone(true, true, false, false);
        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => oldClone };

        // No changes applied to 'acc', so no logs should be generated/inserted
        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        AccountSalesHelper.logAccountUpdates(new List<Account>{ acc }, oldMap);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(0, dmlAfter - dmlBefore, 'No DML should occur when no field values changed.');
    }

    /**
     * Test logAccountUpdates when there ARE changes.
     * - If Log__c exists in the org, we expect exactly one DML statement (a single list insert).
     * - If Log__c does not exist, the method should skip logging gracefully (0 DML statements).
     * This test validates the dynamic log creation path and non-blocking error handling.
     */
    @isTest
    static void testLogAccountUpdates_WithChanges_DmlAttemptedConditionally() {
        // Detect if Log__c is available in this org
        Boolean hasLogObject = Schema.getGlobalDescribe().containsKey('Log__c');

        // Create an Account and emulate old vs new values
        Account acc = new Account(Name = 'Acct - Has Changes');
        insert acc;

        // Old values snapshot (deep clone)
        Account oldClone = acc.clone(true, true, false, false);
        // Apply changes that should be detected by logAccountUpdates
        acc.Priority_Level__c = 'High';
        acc.Next_Best_Action__c = 'Schedule a follow-up meeting';

        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => oldClone };

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        AccountSalesHelper.logAccountUpdates(new List<Account>{ acc }, oldMap);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        // When Log__c exists, we expect a single DML statement (insert of the log list).
        // When it does not exist, no DML should occur.
        Integer expectedDmlStatementsDelta = hasLogObject ? 1 : 0;
        System.assertEquals(expectedDmlStatementsDelta, dmlAfter - dmlBefore,
            'Expected DML statements delta depends on the presence of Log__c.');
    }

    /**
     * Test updateSalesGuidance with an empty input list to ensure method exits gracefully.
     */
    @isTest
    static void testUpdateSalesGuidance_EmptyInput() {
        Test.startTest();
        // Should not throw any exception on empty input
        AccountSalesHelper.updateSalesGuidance(new List<Account>());
        Test.stopTest();

        // Nothing to assert functionally; success is the absence of exceptions.
        System.assert(true, 'Method should handle empty input without errors.');
    }
}
