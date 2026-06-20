@IsTest
private class DataHygieneDashboardControllerTest {
    @TestSetup
    static void setupData() {
        PermissionSet accessSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Data_Hygiene_Dashboard_Access'
            LIMIT 1
        ];
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :accessSet.Id] == 0) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = accessSet.Id
            );
        }

        List<Lead> messyLeads = new List<Lead>{
            buildLead(' jOhN ', 'SMITH', ' john.smith@example.com ', '5551234', 'new york', 'ny', 'Dirty'),
            buildLead('mARIA', 'GONZALEZ', ' maria@example.com ', '(404)-555 8899', 'atlanta', 'ga', 'Dirty'),
            buildLead('  bob  ', 'LEE', null, '123', null, 'ca', null),
            buildLead('SUE', 'PARK', 'sue@example.com', '9876543210', 'chicago', 'il', 'Dirty')
        };
        insert messyLeads;
    }

    @IsTest
    static void testGetDirtyLeadsReturnsRecords() {
        Test.startTest();
        List<Lead> dirtyLeads = DataHygieneDashboardController.getDirtyLeads();
        Test.stopTest();

        System.assert(!dirtyLeads.isEmpty(), 'Expected dirty Leads to be returned.');
        System.assertEquals(4, dirtyLeads.size(), 'Expected all seeded dirty Leads.');
    }

    @IsTest
    static void testCleanLeadRecordSuccess() {
        Lead targetLead = [
            SELECT Id
            FROM Lead
            WHERE LastName = 'SMITH'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Test.startTest();
        String message = DataHygieneDashboardController.cleanLeadRecord(targetLead.Id);
        Test.stopTest();

        System.assert(message.contains('John'), 'Expected cleaned name in response message.');

        Lead cleanedLead = [
            SELECT FirstName, LastName, Hygiene_Status__c, Hygiene_Score__c, Hygiene_Notes__c
            FROM Lead
            WHERE Id = :targetLead.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        System.assertEquals('John', cleanedLead.FirstName);
        System.assertEquals('Smith', cleanedLead.LastName);
        System.assertNotEquals(null, cleanedLead.Hygiene_Status__c);
        System.assertNotEquals(null, cleanedLead.Hygiene_Score__c);
    }

    @IsTest
    static void testCleanLeadRecordNullId() {
        Test.startTest();
        String message = DataHygieneDashboardController.cleanLeadRecord(null);
        Test.stopTest();

        System.assert(message.contains('No Lead was selected'), 'Expected friendly null-id message.');
    }

    @IsTest
    static void testCleanAllDirtyLeads() {
        Test.startTest();
        String summary = DataHygieneDashboardController.cleanAllDirtyLeads();
        Test.stopTest();

        System.assert(summary.contains('Cleaned'), 'Expected summary to mention cleaned records.');

        Integer remainingDirty = [
            SELECT COUNT()
            FROM Lead
            WHERE Hygiene_Status__c = 'Dirty' OR Hygiene_Status__c = NULL
            WITH SECURITY_ENFORCED
        ];
        System.assertEquals(0, remainingDirty, 'Expected all dirty Leads to be processed.');
    }

    @IsTest
    static void testApplyHygieneRulesMarksNeedsReviewForBadPhone() {
        Lead messyLead = buildLead(' ann ', 'TAYLOR', 'ann@example.com', 'call-me', 'boston', 'ma', 'Dirty');
        insert messyLead;

        Test.startTest();
        LeadHygieneFlowRequest request = new LeadHygieneFlowRequest();
        request.leadId = messyLead.Id;
        DataHygieneDashboardController.applyLeadDataHygiene(
            new List<LeadHygieneFlowRequest>{ request }
        );
        Test.stopTest();

        Lead updatedLead = [
            SELECT Hygiene_Status__c, Hygiene_Notes__c, Phone
            FROM Lead
            WHERE Id = :messyLead.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        System.assertEquals('Needs Review', updatedLead.Hygiene_Status__c);
        System.assert(updatedLead.Hygiene_Notes__c.contains('Phone'), 'Expected phone note.');
    }

    @IsTest
    static void testBuildCleanedLeadDirectly() {
        Lead sourceLead = new Lead(
            FirstName = '  amy  ',
            LastName = 'WONG',
            Email = ' AMY@EXAMPLE.COM ',
            Phone = '2125550199',
            City = 'san francisco',
            State = 'ca',
            Company = 'Test Co'
        );

        Lead cleanedLead = DataHygieneDashboardController.buildCleanedLead(sourceLead);

        System.assertEquals('Amy', cleanedLead.FirstName);
        System.assertEquals('Wong', cleanedLead.LastName);
        System.assertEquals('amy@example.com', cleanedLead.Email);
        System.assertEquals('San Francisco', cleanedLead.City);
        System.assertEquals('CA', cleanedLead.State);
        System.assertEquals('Cleaned', cleanedLead.Hygiene_Status__c);
    }

    private static Lead buildLead(
        String firstName,
        String lastName,
        String email,
        String phone,
        String city,
        String state,
        String hygieneStatus
    ) {
        Lead leadRecord = new Lead(
            FirstName = firstName,
            LastName = lastName,
            Email = email,
            Phone = phone,
            City = city,
            State = state,
            Company = 'Hygiene Test Co'
        );
        leadRecord.Hygiene_Status__c = hygieneStatus;
        return leadRecord;
    }
}
