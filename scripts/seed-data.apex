List<Lead> messyLeads = new List<Lead>{
    new Lead(
        FirstName = ' jOhN ',
        LastName = 'SMITH',
        Company = 'Acme Widgets',
        Email = ' john.smith@example.com ',
        Phone = '5551234',
        City = 'new york',
        State = 'New York',
        Country = 'United States',
        Hygiene_Status__c = 'Dirty',
        Hygiene_Score__c = 35
    ),
    new Lead(
        FirstName = 'mARIA',
        LastName = 'LOPEZ',
        Company = 'Bright Path Consulting',
        Email = ' maria@example.com ',
        Phone = '(404)-555 8899',
        City = 'atlanta',
        State = 'Georgia',
        Country = 'United States',
        Hygiene_Status__c = 'Dirty',
        Hygiene_Score__c = 42
    ),
    new Lead(
        FirstName = '  robert  ',
        LastName = 'CHEN',
        Company = 'Northwind Traders',
        Email = 'ROBERT@EXAMPLE.COM',
        Phone = '2125559876',
        City = '  san francisco  ',
        State = 'California',
        Country = 'United States',
        Hygiene_Status__c = 'Dirty',
        Hygiene_Score__c = 38
    ),
    new Lead(
        FirstName = 'SARAH',
        LastName = '  o\'neill  ',
        Company = 'Summit Logistics',
        Email = 'sarah.oneill@example.com',
        Phone = '1-773-555-4422',
        City = 'chicago',
        State = 'Illinois',
        Country = 'United States',
        Hygiene_Status__c = null,
        Hygiene_Score__c = 30
    ),
    new Lead(
        FirstName = ' dave ',
        LastName = 'PATTERSON',
        Company = 'Red Oak Media',
        Email = 'dave@example.com',
        Phone = 'call-me-now',
        City = null,
        State = 'Texas',
        Country = 'United States',
        Hygiene_Status__c = 'Dirty',
        Hygiene_Score__c = 25
    ),
    new Lead(
        FirstName = '  lisa ',
        LastName = 'NGUYEN',
        Company = 'Harbor Health',
        Email = '  lisa.nguyen@example.com  ',
        Phone = '9876543210',
        City = 'miami',
        State = 'Florida',
        Country = 'United States',
        Hygiene_Status__c = null,
        Hygiene_Score__c = 40
    )
};

insert messyLeads;

System.debug('Seeded ' + messyLeads.size() + ' messy Lead records for Data Hygiene Dashboard.');
