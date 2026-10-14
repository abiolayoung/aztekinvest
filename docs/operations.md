# Operations and reconciliation

## What the ledger means

USD amounts are integer cents. Client cash, reserved cash, and invested cost are liabilities. Company custody cash and invested assets at cost are assets. Fee revenue is equity.

A healthy ledger has:

company custody cash + invested assets at cost = client liabilities + fee revenue

The operations overview shows the difference as the break. Unrealized market values are not in this equation. They live on holdings and valuation snapshots.

Posted ledger rows cannot be edited or deleted. A correction is a new compensating entry, with a client-facing description, an internal reason, and an evidence reference.

## Deposits

1. A client creates a request. Status is waiting for payment. Confirmed cash does not change.
2. The client may submit a transaction hash. That moves the request to review. It still does not credit cash.
3. An administrator checks asset, network, destination, amount, confirmations, and whether the hash is already used.
4. Approval posts one balanced ledger transaction and marks the deposit credited. The credited USD amount is the amount the reviewer enters, not automatically the amount the client typed.
5. Rejection stores a client-visible reason and posts no cash.

Underpayments, overpayments, and wrong-network transfers should be flagged rather than forced through approval. If the observed address does not match the instruction, approval is rejected by the database.

## Investments

An allocation debits client cash and credits invested cost for the same amount. It also moves company custody cash into invested assets at cost. The holding starts at that cost. Performance stays unavailable until a later verified valuation or a closing record exists.

Closing a holding removes the cost from invested assets and returns the stated proceeds to client cash. The realized result is proceeds minus cost. A loss can have zero proceeds.

Fees reduce confirmed cash and increase fee revenue. They do not create a deposit.

## Withdrawals

A request reserves the full amount immediately, so it cannot be withdrawn twice. Available cash falls. Account value does not fall until the payout is completed.

Rejecting, failing, or cancelling a request before payout releases the reservation. Completing a request requires a payout transaction hash and moves the reserved amount out of the client liability, with the fee going to fee revenue and the payout leaving custody cash.

Do not mark a withdrawal complete because it was approved. Approval is not payment.

## Access

Clients can read their own rows. They cannot write the ledger, investment records, or their own role. Staff permissions are separated: support can reply and send notices, compliance can review verification and read the audit log, portfolio managers can record investments, and only administrators can credit deposits, process withdrawals, change wallet configuration, and post cash adjustments.

Every one of those actions is a database function that checks the caller's role. Hiding a link is not the control.

## Before accepting real funds

Confirm legal authority, client eligibility, custody, tax, privacy, fee schedule, complaint handling, and the treatment of failed or misdirected payments. Do not publish a license, insurance statement, or guaranteed return that has not been verified. Leave wallet, contact, and legal values blank until they are real.
