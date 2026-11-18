---
title: Vesting
description: How token grants vest over time — cliffs, linear schedules, revocation and claiming.
---

A vesting grant releases tokens to a beneficiary on a schedule. The grantor
funds the contract up front; the contract releases tokens linearly between the
cliff and the end of the schedule, and the beneficiary claims what has vested
at any point.

## Spans, not timestamps

`cliff` and `duration` are **spans in seconds from `start`**, not absolute
timestamps.

```
start ──── cliff ──────────────── start + duration
              │                           │
              └─── linear release ────────┘
```

| Field | Meaning |
| --- | --- |
| `start` | Ledger timestamp when the grant begins (seconds). |
| `cliff` | Seconds from `start` before anything vests. |
| `duration` | Seconds from `start` when the grant is fully vested. |

The cliff span must be less than or equal to the duration span. Setting
`cliff === duration` creates an all-or-nothing unlock: nothing vests before
the cliff, then everything vests at once. Setting `cliff === 0n` creates a
linear schedule with no cliff.

## What the vested amount formula returns

Nothing vests before `start + cliff`. After the cliff, vesting is linear
until `start + duration`, when the whole grant is vested.

```
                 (now - start - cliff)
vested = total × ─────────────────────
                 (duration - cliff)
```

The result is a `bigint` truncated toward zero. Rounding is intentional: the
beneficiary never receives more than the linear fraction implies, and the
grantor never loses a stroop to rounding.

`vestedAmount(timestamp)` is a pure read — it does not cost a transaction:

```ts
const vested = await vesting.vestedAmount(now + 30n); // hypothetical future
```

## Claiming

`claimable()` returns the amount vested minus what has already been claimed.
The beneficiary calls `claim()` to pull that amount into their wallet. Claims
are additive: a beneficiary who waits until the schedule ends and then claims
once receives the full grant minus anything claimed earlier.

```ts
const amount = await vesting.claimable();
if (amount > 0n) {
  const call = await vesting.claim();
  await call.signAndSend(signer);
}
```

A claim on a revoked grant is still valid: vested tokens remain claimable
after revocation.

## Revocation

A grant is revocable only when `create` was called with `revocable: true`.
Revocation can be called at any time by the grantor:

1. The unvested portion is returned to the grantor immediately.
2. Whatever had already vested stays in the contract and remains claimable by
   the beneficiary.
3. `grant.revokedAt` is set to the ledger timestamp of the revocation call.
4. `grant.returned` records how many tokens came back.

```ts
// returned.result is the unvested amount the grantor got back.
const returned = await (await vesting.revoke()).signAndSend(signer);
console.log("returned to grantor:", fromStroops(returned.result));
```

Attempting to revoke a non-revocable grant, or revoking a grant that has
already been revoked, fails with a contract error.

## One grant per contract

Each deployed vesting contract holds exactly one grant. `create` claims the
instance permanently; a second call fails with `AlreadyInitialized`. Deploy a
fresh instance for every grant.

## Relationship to the contract tests

The acceptance criteria for issue [#448](https://github.com/Sororail/sororail-frontend/issues/448)
require this page to be accurate against the contract tests. The
`vesting-lifecycle.ts` example in `packages/sdk/examples/` runs against a live
testnet deployment and asserts the behaviour described here.
