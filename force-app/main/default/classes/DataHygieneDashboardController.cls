public with sharing class DataHygieneDashboardController {
    private static final Integer QUERY_LIMIT = 25;

    @AuraEnabled(cacheable=true)
    public static List<Lead> getDirtyLeads() {
        return [
            SELECT
                Id,
                FirstName,
                LastName,
                Name,
                Email,
                Phone,
                City,
                State,
                CreatedDate,
                Hygiene_Status__c,
                Hygiene_Score__c,
                Hygiene_Notes__c
            FROM Lead
            WHERE Hygiene_Status__c = 'Dirty' OR Hygiene_Status__c = NULL
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :QUERY_LIMIT
        ];
    }

    @AuraEnabled
    public static String cleanLeadRecord(Id leadId) {
        if (leadId == null) {
            return 'No Lead was selected. Please choose a record and try again.';
        }

        try {
            runHygieneFlow(leadId);

            Lead cleanedLead = [
                SELECT FirstName, LastName, Name, Hygiene_Status__c, Hygiene_Notes__c
                FROM Lead
                WHERE Id = :leadId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            String displayName = String.isNotBlank(cleanedLead.Name)
                ? cleanedLead.Name
                : 'Lead';
            return buildCleanMessage(displayName, cleanedLead.Hygiene_Status__c);
        } catch (Exception ex) {
            return 'Unable to clean this Lead: ' + ex.getMessage();
        }
    }

    @AuraEnabled
    public static String cleanAllDirtyLeads() {
        try {
            List<Lead> dirtyLeads = [
                SELECT Id
                FROM Lead
                WHERE Hygiene_Status__c = 'Dirty' OR Hygiene_Status__c = NULL
                WITH SECURITY_ENFORCED
                LIMIT 200
            ];

            if (dirtyLeads.isEmpty()) {
                return 'No dirty Leads found. Everything looks clean.';
            }

            Integer cleanedCount = 0;
            Integer reviewCount = 0;

            for (Lead dirtyLead : dirtyLeads) {
                runHygieneFlow(dirtyLead.Id);
            }

            for (Lead updatedLead : [
                SELECT Hygiene_Status__c
                FROM Lead
                WHERE Id IN :dirtyLeads
                WITH SECURITY_ENFORCED
            ]) {
                if (updatedLead.Hygiene_Status__c == 'Cleaned') {
                    cleanedCount++;
                } else if (updatedLead.Hygiene_Status__c == 'Needs Review') {
                    reviewCount++;
                }
            }

            return 'Cleaned ' +
                cleanedCount +
                ' Leads' +
                (reviewCount > 0 ? ', ' + reviewCount + ' marked as Needs Review.' : '.');
        } catch (Exception ex) {
            return 'Unable to clean all Leads: ' + ex.getMessage();
        }
    }

    public static void applyLeadDataHygiene(List<LeadHygieneFlowRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> leadIds = new Set<Id>();
        for (LeadHygieneFlowRequest request : requests) {
            if (request != null && request.leadId != null) {
                leadIds.add(request.leadId);
            }
        }

        if (leadIds.isEmpty()) {
            return;
        }

        List<Lead> leadsToProcess = [
            SELECT
                Id,
                FirstName,
                LastName,
                Email,
                Phone,
                City,
                State,
                Hygiene_Status__c,
                Hygiene_Notes__c,
                Hygiene_Score__c
            FROM Lead
            WHERE Id IN :leadIds
            WITH SECURITY_ENFORCED
        ];

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Lead leadRecord : leadsToProcess) {
            leadsToUpdate.add(buildCleanedLead(leadRecord));
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    private static void runHygieneFlow(Id leadId) {
        LeadDataHygieneFlowInput input = new LeadDataHygieneFlowInput();
        input.leadId = String.valueOf(leadId);
        LeadDataHygieneFlow.execute(new List<LeadDataHygieneFlowInput>{ input });
    }

    private static String buildCleanMessage(String displayName, String hygieneStatus) {
        if (hygieneStatus == 'Needs Review') {
            return 'Reviewed ' + displayName + '. Some fields need manual review.';
        }
        return 'Cleaned name and contact details for ' + displayName + '.';
    }

    @TestVisible
    private static Lead buildCleanedLead(Lead sourceLead) {
        HygieneResult result = applyHygieneRules(sourceLead);

        Lead updatedLead = new Lead(Id = sourceLead.Id);
        updatedLead.FirstName = result.firstName;
        updatedLead.LastName = result.lastName;
        updatedLead.Email = result.email;
        updatedLead.Phone = result.phone;
        updatedLead.City = result.city;
        updatedLead.State = result.state;
        updatedLead.Hygiene_Status__c = result.status;
        updatedLead.Hygiene_Notes__c = result.notes;
        updatedLead.Hygiene_Score__c = result.score;
        return updatedLead;
    }

    @TestVisible
    private static HygieneResult applyHygieneRules(Lead sourceLead) {
        HygieneResult result = new HygieneResult();
        List<String> changes = new List<String>();
        Boolean needsReview = false;

        result.firstName = toProperCase(trimValue(sourceLead.FirstName));
        result.lastName = toProperCase(trimValue(sourceLead.LastName));
        result.email = trimValue(sourceLead.Email)?.toLowerCase();
        result.city = toProperCase(trimValue(sourceLead.City));
        result.state = normalizeState(trimValue(sourceLead.State));

        if (valueChanged(sourceLead.FirstName, result.firstName)) {
            changes.add('First name normalized');
        }
        if (valueChanged(sourceLead.LastName, result.lastName)) {
            changes.add('Last name normalized');
        }
        if (valueChanged(sourceLead.Email, result.email)) {
            changes.add('Email trimmed and lowercased');
        }
        if (valueChanged(sourceLead.City, result.city)) {
            changes.add('City normalized');
        }
        if (valueChanged(sourceLead.State, result.state)) {
            changes.add('State normalized');
        }

        PhoneNormalization phoneResult = normalizePhone(trimValue(sourceLead.Phone));
        result.phone = phoneResult.formattedPhone;
        if (phoneResult.needsReview) {
            needsReview = true;
            changes.add('Phone could not be fully normalized');
        } else if (valueChanged(sourceLead.Phone, result.phone)) {
            changes.add('Phone standardized');
        }

        if (String.isBlank(result.email)) {
            needsReview = true;
            changes.add('Missing email');
        }
        if (String.isBlank(result.city)) {
            needsReview = true;
            changes.add('Missing city');
        }

        result.status = needsReview ? 'Needs Review' : 'Cleaned';
        result.score = calculateScore(sourceLead, result, needsReview);
        result.notes = changes.isEmpty()
            ? 'No changes were required. Record marked as Cleaned.'
            : String.join(changes, '; ') + '.';

        return result;
    }

    private static String trimValue(String value) {
        return value == null ? null : value.trim();
    }

    private static Boolean valueChanged(String originalValue, String cleanedValue) {
        String original = originalValue == null ? '' : originalValue.trim();
        String cleaned = cleanedValue == null ? '' : cleanedValue.trim();
        return original != cleaned;
    }

    private static String toProperCase(String value) {
        if (String.isBlank(value)) {
            return value;
        }

        List<String> words = value.toLowerCase().split('\\s+');
        List<String> formattedWords = new List<String>();
        for (String word : words) {
            if (String.isBlank(word)) {
                continue;
            }
            formattedWords.add(word.substring(0, 1).toUpperCase() + word.substring(1));
        }
        return String.join(formattedWords, ' ');
    }

    private static String normalizeState(String stateValue) {
        if (String.isBlank(stateValue)) {
            return stateValue;
        }
        return stateValue.trim().toUpperCase();
    }

    private static PhoneNormalization normalizePhone(String phoneValue) {
        PhoneNormalization result = new PhoneNormalization();
        if (String.isBlank(phoneValue)) {
            result.formattedPhone = phoneValue;
            return result;
        }

        String digitsOnly = phoneValue.replaceAll('[^0-9]', '');
        if (digitsOnly.length() == 10) {
            result.formattedPhone =
                '+1 (' +
                digitsOnly.substring(0, 3) +
                ') ' +
                digitsOnly.substring(3, 6) +
                '-' +
                digitsOnly.substring(6);
            return result;
        }
        if (digitsOnly.length() == 11 && digitsOnly.startsWith('1')) {
            result.formattedPhone =
                '+1 (' +
                digitsOnly.substring(1, 4) +
                ') ' +
                digitsOnly.substring(4, 7) +
                '-' +
                digitsOnly.substring(7);
            return result;
        }

        result.formattedPhone = phoneValue.trim();
        result.needsReview = true;
        return result;
    }

    private static Decimal calculateScore(Lead sourceLead, HygieneResult result, Boolean needsReview) {
        Integer score = 100;
        if (needsReview) {
            score = 70;
        }
        if (String.isBlank(result.email)) {
            score -= 20;
        }
        if (String.isBlank(result.city)) {
            score -= 10;
        }
        if (valueChanged(sourceLead.Phone, result.phone) == false && String.isNotBlank(sourceLead.Phone)) {
            score = Math.max(score - 15, 40);
        }
        if (
            valueChanged(sourceLead.FirstName, result.firstName) ||
            valueChanged(sourceLead.LastName, result.lastName) ||
            valueChanged(sourceLead.Email, result.email)
        ) {
            score = Math.max(score, 80);
        }
        return score;
    }

    private class HygieneResult {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String city;
        public String state;
        public String status;
        public String notes;
        public Decimal score;
    }

    private class PhoneNormalization {
        public String formattedPhone;
        public Boolean needsReview = false;
    }
}
