@isTest
public class AccountSalesHelperTest {
    @isTest
    static void testUpdateSalesGuidance() {
        // Create test accounts
        Account acc1 = new Account(Name = 'Big Revenue Account', AnnualRevenue = 2000000);
        Account acc2 = new Account(Name = 'Medium Revenue Account', AnnualRevenue = 750000);
        Account acc3 = new Account(Name = 'Small Revenue Account', AnnualRevenue = 300000);
        insert new List<Account> { acc1, acc2, acc3 };

        // Create opportunities to simulate recent activity
        Opportunity recentOpenOpp = new Opportunity(
            Name = 'Open Deal',
            AccountId = acc2.Id,
            StageName = 'Negotiation',
            CloseDate = Date.today().addDays(-30),
            Amount = 50000
        );

        Opportunity recentClosedWonOpp = new Opportunity(
            Name = 'Closed Won Deal',
            AccountId = acc3.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-120),
            Amount = 10000
        );

        insert new List<Opportunity> { recentOpenOpp, recentClosedWonOpp };

        // Query accounts after insertion
        List<Account> accounts = [SELECT Id, Name, AnnualRevenue FROM Account];

        // Call the updated method
        Test.startTest();
        AccountSalesHelper.updateSalesGuidance(accounts);
        update accounts;
        Test.stopTest();

        // Re-query to check results
        accounts = [SELECT Id, Priority_Level__c, Next_Best_Action__c FROM Account];

        // Assert priority levels
        System.assertEquals('High', accounts[0].Priority_Level__c, 'High revenue should be High priority');
        System.assertEquals('High', accounts[1].Priority_Level__c, 'Recent open opp should make it High priority');
        System.assertEquals('Low', accounts[2].Priority_Level__c, 'Low revenue and no open opp should be Low priority');

        // Assert next best actions
        System.assertEquals('Schedule a follow-up meeting', accounts[0].Next_Best_Action__c, 'High priority should have follow-up meeting');
        System.assertEquals('Schedule a follow-up meeting', accounts[1].Next_Best_Action__c, 'High priority due to recent opp should also have follow-up meeting');
        System.assertEquals('Send a thank-you email', accounts[2].Next_Best_Action__c, 'Recent closed-won opp should trigger thank-you email');
    }
}