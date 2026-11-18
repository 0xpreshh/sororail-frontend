---
title: Batch payout
description: Paying many recipients in one transaction — execute, execute_equal, preview, the recipient cap and chunking.
---

The batch payout contract sends tokens from a single funder to many recipients
in one transaction. It is **stateless and reusable**: unlike the stream,
vesting and escrow contracts, it holds no position and no funds, so a single
deployed address can serve all callers.

## execute vs execute_equal

There are two ways to pay a list of recipients:

| Method | When to use |
| --- | --- |
| `execute` | Each recipient gets a different amount (payroll, invoices). |
| `executeEqual` | Every recipient gets the same amount (dividends, rewards). |

`executeEqual` is cheaper to submit because the amount crosses the wire once
rather than once per line.

```ts
// Different amounts
await (await batch.execute({ funder, token, recipients: [
  { to: 'G...alice', amount: 1_000n },
  { to: 'G...bob',   amount: 500n  },
]})).signAndSend(signer);

// Same amount
await (await batch.executeEqual({ funder, token,
  recipients: ['G...alice', 'G...bob'],
  amountEach: 750n,
})).signAndSend(signer);
```

Both methods are **all-or-nothing**: if any transfer fails, the whole batch
reverts and nobody is paid. No partial success is possible.

## Dust amounts

Every amount is a `bigint` in the token's smallest unit. Zero and negative
amounts are rejected by the SDK before the transaction is built. There is no
minimum above zero, but paying a dust amount (a single stroop) may cost more
in fees than the payment is worth. Use `preview` to see the total before
deciding.

## Preview

`preview` runs the same validation as `execute` — including the recipient cap
and amount checks — but moves no funds. Use it on a confirmation screen before
asking the user for a signature.

```ts
const receipt = await batch.preview(payroll);
console.log(`${receipt.count} payments totalling ${formatAmount(receipt.total)}`);
```

A preview that succeeds means the batch will not be rejected for size, an
invalid amount, or an overflowing total. It does not guarantee sufficient
balance: the funder's balance is checked when the signed transaction executes.

## The recipient cap

The contract enforces a maximum number of recipients per batch. The cap is
derived from Soroban's ledger resource limits and may differ between
deployments.

Always read the cap rather than hardcoding it:

```ts
const cap = await batch.maxRecipients();
```

Submitting a batch that exceeds the cap fails with `BatchTooLarge`.

## Chunking an oversized payroll

When a payroll is larger than the cap, split it client-side with
`BatchPayoutClient.chunk` and send each chunk as a separate transaction:

```ts
const cap = await batch.maxRecipients();
const batches = BatchPayoutClient.chunk(payroll, cap);
for (const chunk of batches) {
  await (await batch.execute({ funder, token, recipients: chunk })).signAndSend(signer);
}
```

`chunk` is a pure function: it does not send anything and always produces
chunks of at most `maxRecipients` entries. It never drops a line; the flat
array of all chunks is exactly the original payroll.

Duplicates within a payroll are allowed on-chain: the same address can appear
more than once and will receive each listed payment independently. This is
intentional (one contractor with two invoices), but catch accidental duplicates
in your CSV import or preview screen if you do not want them.

## Relationship to the contract tests

The acceptance criteria for issue [#451](https://github.com/Sororail/sororail-frontend/issues/451)
require the chunking example to be verified. The `batch-payout.ts` example in
`packages/sdk/examples/` runs against a live testnet deployment, reads the
real cap, chunks a payroll that is one entry over two full batches, and asserts
that all three resulting chunks land correctly.
