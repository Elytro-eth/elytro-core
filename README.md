# elytro-core

A from-first-principles, **agent-native** Ethereum smart account. Clean-room rebuild — not derived from the existing Elytro CLI/contracts.

## Thesis

An AI agent should be able to operate a wallet on a human's behalf, but its authority must be bounded by **the contract refusing**, not by an LLM obeying prose or a backend staying honest.

The one hard invariant:

> A compromised agent can move at most its remaining per-tx / per-period / total budget of each protected asset, and nothing else — **regardless of how the value is routed.**

## The novel mechanism: realized-value enforcement

Every "agent spending limit" people ship tries to *decode the agent's calldata* to estimate how much value it moves. That is unsound: a router, a `multicall`, or an obfuscated/malicious token can move arbitrary value the decoder never sees. Allowlisting one DEX router authorizes unbounded movement.

`AgentAccount` does the opposite. Before the agent's calls it **snapshots the account's protected-asset balances**, executes, then asserts the **realized outflow** (balance delta) against the agent's caps. Value is bounded by what actually left, so the bound holds through any router, swap, or DeFi path.

The headline test, [`test_RealizedValueBeatsLyingCalldata`](test/AgentAccount.t.sol): a token whose `transfer(to, 1)` actually moves `1000` is still capped at `100` and reverts. A calldata-decoding limit would wave it through.

## Principals (on-chain-distinct)

| Principal | Authority | Enforcement |
|---|---|---|
| **owner (root)** | Anything. The human's cold key. Manages agents, caps, protected assets, recovery. Sole ERC-1271 signer. | `executeAsOwner` (onlyOwner); management `onlyOwnerOrSelf`. |
| **agent** | Only allowlisted `(target, selector)` calls, bounded by realized-value caps. Never the account itself, never ERC-20 approvals, never ERC-1271. | `executeAsAgent`: allowlist + forbidden-surface checks + realized-value charge. |

Why the agent restrictions matter:
- **No self-calls** → an agent can never reach an owner-management function.
- **No approvals** → no standing allowance, the canonical approve-then-drain primitive (a future pull the realized-value check wouldn't see).
- **Excluded from ERC-1271** → an agent that could sign off-chain (Permit / Permit2 / EIP-3009) would bypass every on-chain cap with zero on-chain footprint.
- **Uncapped protected asset must not decrease** → fail-safe: if the owner allowlists a token but forgets a cap, the account refuses rather than leaking.

## Recovery: agent drives, guardians authorize

`src/GuardianRecovery.sol` proves the other half of the goal — **recover by agent**:

> The agent can *drive* recovery (assemble guardian signatures off-chain and submit the permissionless on-chain txs) but can never *authorize* it — only a threshold of distinct guardians can, after a time-delay during which the owner or any guardian may veto.

- `scheduleRecovery` is permissionless (the agent is a courier); it requires ≥ threshold distinct guardian signatures over an EIP-712 digest binding the full params (account, newOwner, nonce, delay).
- `cancelRecovery` (owner or any guardian) bumps a nonce, invalidating the scheduled recovery *and* any collected signatures.
- `executeRecovery` is permissionless after the delay; it rotates the owner via the account's `recoverOwner`, callable only by the wired module.

A successful owner rotation is total control, so the entire safety budget lives in (unforgeable cross-guardian sigs) + (delay) + (reachable veto). Tests cover courier-not-authorizer, below-threshold, duplicate-signer, delay, owner/guardian veto, replay-invalidation, and post-recovery control.

## Status

✅ **29/29 tests pass** (`forge test`) — `AgentAccount` (19) + `GuardianRecovery` (10).

This is the on-chain core (blueprint Phases 1 + 3): caps and recovery that hold even if every off-chain Elytro service is gone.

### Honest limitations (next)
- **Protected-set boundary:** realized-value covers native + the owner-declared protected ERC-20s. A token outside that set, if the agent is allowlisted to touch it, is not value-bounded. The owner must enumerate holdings. (Blueprint open risk #1.)
- **Fixed-window period cap** (resets when the window elapses), not a true sliding window.
- **`GuardianRecovery.setGuardians` does not clear the prior set** on reconfigure (shrinking a guardian set requires a fresh module). Constructor set is exact.
- **Compromised (not lost) owner key** can still veto a guardian rescue — an acknowledged tension; the blueprint's answer is step-up on high value + caps, not yet built here.
- Not yet: ERC-4337 EntryPoint integration, passkey (P256) root, the on-chain capability as a 4337 validator, USD-denominated caps.

## Run

```bash
forge test -vv
```
