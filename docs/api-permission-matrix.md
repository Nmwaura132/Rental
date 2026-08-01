# API permission matrix

This matrix is the launch authorization contract. “Assigned” means the resource belongs to a property where the user is the configured caretaker. Every endpoint also requires authentication unless it is explicitly a login, password-reset, or verified payment-provider webhook.

| Capability | Landlord | Caretaker | Tenant |
|---|---:|---:|---:|
| View properties and units | Owned | Assigned | Active lease only |
| Create/update/delete properties, units, and charges | Yes | No | No |
| View tenants and leases | Owned portfolio | Assigned portfolio | Own |
| Register tenants and manage leases | Owned portfolio | Assigned portfolio | No |
| View invoices and payments | Owned portfolio | Assigned portfolio | Own |
| Create/edit/cancel invoices | Yes | No | No |
| Record cash or bank payments | Yes | No | No |
| Start M-Pesa STK payment | No | No | Own invoice |
| View dashboard | Owned portfolio | Assigned portfolio | Own |
| Generate reports | Owned portfolio | Assigned portfolio | Own ledger only |
| Create/update maintenance requests | Owned portfolio | Assigned portfolio | Own lease |
| Upload tenant ID and lease documents | Owned portfolio | Assigned portfolio | No |
| Manage bank notifications or payment-provider setup | Yes | No | No |

Financial mutation endpoints use explicit landlord permissions. Querysets independently scope object access, so knowing another portfolio’s numeric identifier does not grant access.
