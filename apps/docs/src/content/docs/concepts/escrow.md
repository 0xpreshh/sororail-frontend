---
title: Escrow
description: States, roles, the dispute/arbiter model and how funds move through an escrow contract.
---

An escrow contract holds funds on behalf of two parties and releases them
according to a condition. The contract is the neutral holder: neither the
depositor nor the beneficiary can take the money unilaterally once it is
funded, except in the specific circumstances described below.

## Roles

| Role | Who | Abilities |
| --- | --- | --- |
| **Depositor** | The party putting up funds. | `init`, `fund`, `release`, `refund` after the deadline, `dispute`. |
| **Beneficiary** | The party receiving funds on success. | `dispute`. |
| **Arbiter** | Optional trusted third party. | `release`, `refund` at any time, `resolve` with any split. |

An escrow without an arbiter is simpler but less flexible: `dispute` and
`resolve` are unavailable, and the depositor can only get a refund after the
deadline has passed.

## State machine

```
              init
                │
            Created
                │
              fund
                │
            Funded ──── dispute ──► Disputed
           ╱       ╲                    │
       release    refund            resolve
         ╱           ╲                  │
     Released      Refunded         Resolved
```

Terminal states — `Released`, `Refunded`, `Resolved` — are final. No further
transitions are possible once the escrow reaches one of them.

| Transition | Who may call | From state |
| --- | --- | --- |
| `init` | Depositor | — (new instance) |
| `fund` | Depositor | Created |
| `release` | Depositor or Arbiter | Funded |
| `refund` | Depositor (after deadline), or Arbiter (any time) | Funded |
| `dispute` | Depositor or Beneficiary | Funded |
| `resolve` | Arbiter only | Disputed |

## The deadline

`deadline` is a ledger timestamp in seconds. It is enforced at the contract
level: a depositor calling `refund` before the deadline is rejected on-chain,
regardless of what the SDK or the application does.

The deadline does not expire the escrow. A funded escrow whose deadline has
passed remains in the `Funded` state; it does not automatically refund. The
depositor must call `refund` explicitly.

An arbiter, if present, can call `refund` at any time regardless of the
deadline.

## Dispute and resolution

Either the depositor or the beneficiary may call `dispute` on a funded escrow.
Once disputed, the escrow is frozen: neither `release` nor `refund` is
available until the arbiter resolves it.

The arbiter resolves with a split expressed in **basis points** (0–10 000).
The split is the beneficiary's share; the depositor receives the remainder.

```ts
// Give the beneficiary 60 %, the depositor 40 %.
const call = await escrow.resolve(6_000);
await call.signAndSend(arbiterSigner);
```

The two amounts are computed by integer arithmetic and always sum to exactly
the escrowed amount: no stroop is lost to rounding.

| `splitBps` | Beneficiary receives | Depositor receives |
| --- | --- | --- |
| `0` | 0 (full refund) | Total |
| `5_000` | 50 % | 50 % |
| `10_000` | Total (full release) | 0 |

## One agreement per contract

`init` claims the instance permanently. A second call fails with
`AlreadyInitialized`. Deploy one contract per escrow agreement rather than
reusing an address.

## Reading the state

`state()` is a cheap read that returns the current state name without sending
a transaction. `get()` returns the full agreement record.

```ts
const state = await escrow.state(); // "Created" | "Funded" | ...
const record = await escrow.get();  // depositor, beneficiary, amount, deadline, ...
```

## Relationship to the contract tests

The acceptance criteria for issue [#449](https://github.com/Sororail/sororail-frontend/issues/449)
require this diagram to match the contract's state machine. The
`escrow-lifecycle.ts` example in `packages/sdk/examples/` runs against a live
testnet deployment and asserts the full happy path.
