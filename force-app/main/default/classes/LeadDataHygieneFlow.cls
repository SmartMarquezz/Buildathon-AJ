public with sharing class LeadDataHygieneFlow {
    @InvocableMethod(
        label='Apply Lead Data Hygiene Flow'
        description='Runs Lead data hygiene cleanup for the provided Lead Id.'
        category='Lead'
    )
    public static void execute(List<LeadDataHygieneFlowInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        List<LeadHygieneFlowRequest> requests = new List<LeadHygieneFlowRequest>();
        for (LeadDataHygieneFlowInput input : inputs) {
            if (input == null || String.isBlank(input.leadId)) {
                continue;
            }
            LeadHygieneFlowRequest request = new LeadHygieneFlowRequest();
            request.leadId = input.leadId;
            requests.add(request);
        }

        if (!requests.isEmpty()) {
            DataHygieneDashboardController.applyLeadDataHygiene(requests);
        }
    }
}
