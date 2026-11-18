---
title: TTL and state archival
description: Why contract state has a time-to-live, how to extend it, and how to restore archived entries.
---

Every piece of state on Soroban has a **time-to-live (TTL)**: a number of
ledgers after which the network is free to archive it. Archived state is not
destroyed, but it cannot be read or written until it is explicitly restored.
Understanding TTL is essential if your users hold long-running positions —
streams, vesting grants, escrow agreements — because a position whose TTL
expires becomes inaccessible until it is restored.

## Two kinds of state

Soroban distinguishes two storage types with different TTL rules:

| Storage type | Typical use | TTL behaviour |
| --- | --- | --- |
| **Instance** | Contract code, global config, counters. | One TTL for the whole contract instance. If instance state archives, the contract cannot be invoked at all. |
| **Persistent** | Per-user positions, grants, agreements. | Each entry has its own TTL. An archived persistent entry blocks reads and writes for that entry only. |

The SoroRail contracts store positions in persistent storage. If a user's
vesting grant, stream or escrow entry archives, that position is inaccessible
until it is restored — but other users' entries on the same contract are
unaffected.

## What determines the TTL

When an entry is created or last written, the network sets its TTL to the
network's current **minimum TTL** (also called the minimum persistence ledger
count). As of the current network settings, persistent entries have a minimum
TTL of roughly 30 days of ledger closes at the normal 5-second pace; the exact
ledger count is a network-level parameter that can change with governance.

An entry whose TTL reaches zero moves to the **archived** state at the next
ledger close.

## Extending the TTL with bump

Call `bump` to extend an entry's TTL before it expires. The network will not
close the TTL below the value you request; if the current TTL is already higher
than the requested extension, the call is a no-op and costs only the base fee.

The SoroRail contracts expose a `bump` entry point that extends both the
contract instance and the caller's persistent entry in one call:

```ts
const call = await client.bump();
await call.signAndSend(signer);
```

**When to call it:**
- After creating a long-running position (stream, grant, escrow): bump immediately
  to set the TTL to the amount of time the position is expected to live.
- As part of a periodic keep-alive job for active positions.
- Before any interaction with a position that may be close to expiry.

**Cost:** `bump` pays only the ledger rent for the TTL extension. The fee is
proportional to the number of ledgers you are extending by and the size of the
entry. Extending a small persistent entry for 30 days costs a fraction of a
stroop; extending for years at once is cheaper than extending in monthly
increments because there is one base fee instead of twelve.

## How to tell if an entry has archived

A read or write to an archived entry fails with a contract error. The SDK
surfaces this as a `ContractError` whose `variant` is `ArchivedEntry` (the
exact variant name depends on the contract version; check
`packages/sdk/src/errors/codes.ts` for the current mapping).

You can also query the entry's TTL out of band through an RPC call to the
network's `getLedgerEntries` endpoint, though the SDK does not currently wrap
this in a typed helper.

## Restoring an archived entry

An archived entry must be restored before it can be used. Restoration is a
Soroban host-level operation (`restore_footprint_preamble`) that you submit as
a transaction separate from the operation that needs the entry.

The Stellar SDK's `SorobanRpc.Server` class provides the low-level tools, but
the typical flow from the SoroRail SDK is:

1. Simulate the failing operation. The simulation response includes a
   `restorePreamble` when the operation requires a restoration.
2. Submit the restore transaction from the preamble.
3. Re-submit the original operation.

```ts
// Step 1 – simulate and detect the need to restore.
const call = await client.claim();
const sim = await call.simulate();

if (sim.restorePreamble) {
  // Step 2 – restore the archived entry.
  const restoreTx = /* build restore transaction from sim.restorePreamble */;
  await rpcServer.sendTransaction(restoreTx);

  // Step 3 – re-submit the original call.
  await call.signAndSend(signer);
}
```

After restoration the entry's TTL is reset to the network's minimum TTL. Bump
it immediately to avoid falling back into archival.

## Cost guidance

| Action | Cost driver |
| --- | --- |
| Creating a persistent entry | Ledger rent for the minimum TTL, paid up front. |
| `bump` by N ledgers | Rent for N ledgers × entry size bytes. |
| Restoration | Rent for the minimum TTL, plus a fixed restoration fee. |
| Reading or writing a live entry | Base simulation and submission fee only; no rent. |

Extending TTL aggressively at creation is cheaper overall than letting entries
archive and paying restoration fees repeatedly. For a one-year vesting grant,
bump to at least one year at creation rather than relying on monthly keep-alive
jobs.

## Relationship to the contracts

The acceptance criteria for issue [#452](https://github.com/Sororail/sororail-frontend/issues/452)
require this guide to be reviewed against the contracts' TTL constants. The
Rust contracts in [Sororail/sororail-contracts](https://github.com/Sororail/sororail-contracts)
define the bump amounts they request in their `bump` entry points; this guide
describes the behaviour those constants produce at the network level.
