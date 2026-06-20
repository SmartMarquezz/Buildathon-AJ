import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getDirtyLeads from '@salesforce/apex/DataHygieneDashboardController.getDirtyLeads';
import cleanLeadRecord from '@salesforce/apex/DataHygieneDashboardController.cleanLeadRecord';
import cleanAllDirtyLeads from '@salesforce/apex/DataHygieneDashboardController.cleanAllDirtyLeads';

export default class DataHygieneDashboard extends LightningElement {
    @track leads = [];
    @track selectedLead = null;
    @track isLoading = true;
    @track isCleaning = false;
    @track resultMessage = null;
    @track stats = {
        recordsScanned: 0,
        dirtyRecords: 0,
        cleanedToday: 0
    };
    sessionCleanedCount = 0;

    _wiredLeadsResult;

    @wire(getDirtyLeads)
    wiredLeads(result) {
        this._wiredLeadsResult = result;
        this.isLoading = true;

        if (result.data) {
            this.leads = result.data;
            this.computeStats(result.data);
            this.syncSelectedLead(result.data);
            this.isLoading = false;
        } else if (result.error) {
            this.leads = [];
            this.computeStats([]);
            this.isLoading = false;
            this.showToast('Error', this.reduceError(result.error), 'error');
        }
    }

    get hasLeads() {
        return this.leads.length > 0;
    }

    get hasSelectedLead() {
        return this.selectedLead !== null;
    }

    get recordsScanned() {
        return this.stats.recordsScanned;
    }

    get dirtyRecords() {
        return this.stats.dirtyRecords;
    }

    get cleanedToday() {
        return this.stats.cleanedToday;
    }

    get leadsWithClasses() {
        return this.leads.map((lead) => ({
            ...lead,
            cardClass: this.buildCardClass(lead.Id),
            statusClass: this.buildStatusClass(lead.Hygiene_Status__c),
            statusLabel: lead.Hygiene_Status__c || 'Dirty',
            locationLabel: this.buildLocationLabel(lead),
            hasScore: lead.Hygiene_Score__c !== null && lead.Hygiene_Score__c !== undefined
        }));
    }

    get selectedStatusClass() {
        return this.buildStatusClass(this.selectedLead?.Hygiene_Status__c);
    }

    get selectedStatusLabel() {
        return this.selectedLead?.Hygiene_Status__c || 'Dirty';
    }

    get selectedLeadHasScore() {
        return (
            this.selectedLead?.Hygiene_Score__c !== null &&
            this.selectedLead?.Hygiene_Score__c !== undefined
        );
    }

    get issuesDescription() {
        if (!this.selectedLead) {
            return '';
        }
        if (this.selectedLead.Hygiene_Notes__c) {
            return this.selectedLead.Hygiene_Notes__c;
        }
        return this.buildIssueSummary(this.selectedLead);
    }

    handleLeadSelect(event) {
        const leadId = event.currentTarget.dataset.id;
        this.selectedLead = this.leads.find((lead) => lead.Id === leadId) || null;
        this.resultMessage = null;
    }

    async handleCleanSelected() {
        if (!this.selectedLead || this.isCleaning) {
            return;
        }

        this.isCleaning = true;
        this.resultMessage = null;

        try {
            const message = await cleanLeadRecord({ leadId: this.selectedLead.Id });
            this.resultMessage = message;
            this.sessionCleanedCount += 1;
            this.showToast('Success', message, 'success');
            await this.refreshLeads();
        } catch (error) {
            const errorMessage = this.reduceError(error);
            this.resultMessage = errorMessage;
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isCleaning = false;
        }
    }

    async handleCleanAll() {
        if (this.isCleaning) {
            return;
        }

        this.isCleaning = true;
        this.resultMessage = null;

        try {
            const message = await cleanAllDirtyLeads();
            this.resultMessage = message;
            this.sessionCleanedCount += this.leads.length;
            this.showToast('Success', message, 'success');
            this.selectedLead = null;
            await this.refreshLeads();
        } catch (error) {
            const errorMessage = this.reduceError(error);
            this.resultMessage = errorMessage;
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isCleaning = false;
        }
    }

    async handleRefresh() {
        this.selectedLead = null;
        this.resultMessage = null;
        await this.refreshLeads();
    }

    async refreshLeads() {
        this.isLoading = true;
        await refreshApex(this._wiredLeadsResult);
        this.isLoading = false;
    }

    computeStats(leadRecords) {
        const dirtyCount = leadRecords.length;
        this.stats = {
            recordsScanned: dirtyCount + this.sessionCleanedCount,
            dirtyRecords: dirtyCount,
            cleanedToday: this.sessionCleanedCount
        };
    }

    syncSelectedLead(leadRecords) {
        if (!this.selectedLead) {
            return;
        }
        this.selectedLead = leadRecords.find((lead) => lead.Id === this.selectedLead.Id) || null;
    }

    buildCardClass(leadId) {
        return this.selectedLead?.Id === leadId ? 'record-card active' : 'record-card';
    }

    buildStatusClass(statusValue) {
        if (statusValue === 'Cleaned') {
            return 'badge badge-cleaned';
        }
        if (statusValue === 'Needs Review') {
            return 'badge badge-review';
        }
        return 'badge badge-dirty';
    }

    buildLocationLabel(lead) {
        const city = lead.City || '';
        const state = lead.State || '';
        if (city && state) {
            return `${city} / ${state}`;
        }
        return city || state || 'No location';
    }

    buildIssueSummary(lead) {
        const issues = [];
        if (!lead.Email || lead.Email.trim() !== lead.Email) {
            issues.push('Email needs trimming or is missing');
        }
        if (!lead.Phone) {
            issues.push('Phone is missing');
        } else if (!lead.Phone.includes('+1 (')) {
            issues.push('Phone format is inconsistent');
        }
        if (!lead.City) {
            issues.push('City is missing');
        }
        if (lead.FirstName && lead.FirstName !== lead.FirstName.trim()) {
            issues.push('First name has extra whitespace');
        }
        if (lead.LastName && lead.LastName === lead.LastName.toUpperCase()) {
            issues.push('Last name casing looks inconsistent');
        }
        return issues.length
            ? issues.join('; ') + '.'
            : 'Record flagged as dirty and ready for cleanup.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
