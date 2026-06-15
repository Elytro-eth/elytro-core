# elytro-core

A from-first-principles, **agent-native** Ethereum smart account. Clean-room rebuild — not derived from the existing Elytro CLI/contracts.

> **🤖 For AI agents:** read [**AGENTS.md**](AGENTS.md). To *operate* a wallet: `npm i -g @elytro/agent-cli` ([npm](https://www.npmjs.com/package/@elytro/agent-cli)), then `elytro-agent keygen`. The deterministic-JSON commands, trust model, and error codes are in AGENTS.md; the Claude Code skill is `SKILL.md` in that package. To *work on this repo*: build/test/conventions are in AGENTS.md too.

## Thesis

An AI agent should be able to operate a wallet on a human's behalf, but its authority must be bounded by **the contract refusing**, not by an LLM obeying prose or a backend staying honest.

The one hard invariant:

> A compromised agent can move at most its remaining per-tx / per-period / total budget of each protected asset, and nothing else — **regardless of how the value is routed.**

## The novel mechanism: realized-value enforcement

Every "agent spending limit" people ship tries to *decode the agent's calldata* to estimate how much value it moves. That is unsound: a router, a `multicall`, or an obfuscated/malicious token can move arbitrary value the decoder never sees. Allowlisting one DEX router authorizes unbounded movement.

`AgentAccount` does the opposite. It snapshots the account's protected-asset balances **immediately before each call**, executes, and accumulates the **gross realized outflow** (per-call balance decrease) against the agent's caps. Value is bounded by what actually left, through any router, swap, or DeFi path — and because accounting is *gross-per-call*, not net-per-batch, a later inflow / rebase / yield-claim can never retroactively mask an earlier outflow.

The headline test, [`test_RealizedValueBeatsLyingCalldata`](test/AgentAccount.t.sol): a token whose `transfer(to, 1)` actually moves `1000` is still capped at `100` and reverts. A calldata-decoding limit would wave it through.

## Principals (on-chain-distinct)

| Principal | Authority | Enforcement |
|---|---|---|
| **owner (root)** | Anything. The human's cold key. Manages agents, caps, protected assets, recovery. Sole ERC-1271 signer. | `executeAsOwner` (onlyOwner); management `onlyOwnerOrSelf`. |
| **agent** | Only allowlisted `(target, selector)` calls, bounded by realized-value caps. Never the account itself, never ERC-20 approvals, never ERC-1271. | `executeAsAgent`: allowlist + forbidden-surface checks + realized-value charge. |

Why the agent restrictions matter:
- **No self-calls** → an agent can never reach an owner-management function.
- **Protected tokens only, via measured movers** → an agent may move an ERC-20 only via a known value-mover (`transfer` / ERC-777 `send` / `transferAndCall`) on a token in the **protected set** (so every move is snapshotted + capped); those selectors revert on a non-protected token. It cannot grant any standing allowance: `approve` / `increaseAllowance` / `setApprovalForAll` / `permit` / DAI-`permit` / Permit2-`approve` / `transferFrom` are all forbidden — closing the approve-then-drain primitive. *Scope note:* the realized-value engine measures the protected set; the owner is responsible for not allowlisting an exotic value-mover on a token left outside it (audit M2).
- **Excluded from ERC-1271** → an agent that could sign off-chain (Permit / Permit2 / EIP-3009) would bypass every on-chain cap with zero on-chain footprint.
- **Uncapped protected asset must not decrease** → fail-safe: if the owner allowlists a token but forgets a cap, the account refuses rather than leaking.
- **Malformed (1-3 byte) calldata rejected** → a "native send" grant can't be turned into a fallback call.

## Recovery: agent drives, guardians authorize

`src/GuardianRecovery.sol` proves the other half of the goal — **recover by agent**:

> The agent can *drive* recovery (assemble guardian signatures off-chain and submit the permissionless on-chain txs) but can never *authorize* it — only a threshold of distinct guardians can, after a time-delay during which the owner or any guardian may veto.

- `scheduleRecovery` is permissionless (the agent is a courier); it requires ≥ threshold distinct guardian signatures over an EIP-712 digest binding the full params (account, newOwner, nonce, delay).
- `cancelRecovery` (owner or any guardian) bumps a nonce, invalidating the scheduled recovery *and* any collected signatures.
- `executeRecovery` is permissionless after the delay; it rotates the owner via the account's `recoverOwner`, callable only by the wired module.

A successful owner rotation is total control, so the entire safety budget lives in (unforgeable cross-guardian sigs) + (delay) + (reachable veto). Tests cover courier-not-authorizer, below-threshold, duplicate-signer, delay, owner/guardian veto, replay-invalidation, and post-recovery control.

## ERC-4337

`AgentAccount` implements `IAccount` (v0.7/0.8 `PackedUserOperation`), so an agent operates it as a real account-abstraction wallet — gasless `UserOps` through a bundler — and is *still* bounded by the realized-value engine:

- `validateUserOp` recovers the signer and classifies it: **owner** → unrestricted (validationData 0); **active agent** → validationData packs the agent's `validAfter`/`validUntil` for the EntryPoint to enforce; anyone else → `SIG_VALIDATION_FAILED`. It's ERC-7562-clean (only own-storage reads, no external calls bar the EntryPoint prefund), so the capability/value checks run at *execution*, not validation.
- A transient operator hand-off carries the classified principal from `validateUserOp` to `executeUserOp`; `executeUserOp` then routes through the same owner / agent-capability paths. A second same-sender op in one bundle reverts rather than reuse the first's authority.
- Tested against a faithful `MockEntryPoint`, **and against the canonical EntryPoint v0.8 (`0x4337…F108`) on a Base mainnet fork** ([`test/EntryPointFork.t.sol`](test/EntryPointFork.t.sol)): a real agent-signed UserOp through genuine `handleOps` executes a capped transfer; an over-cap UserOp reverts on the cap with no value moved. Run with `RUN_FORK_TESTS=true forge test --match-path test/EntryPointFork.t.sol`.

## Live on the Cleave testnet (real EntryPoint v0.8)

Deployed and exercised on the Cleave testnet (anvil mainnet fork, chain `73571`) against the canonical EntryPoint v0.8 — the agent operating via real `handleOps`, not a mock. Factory `0xd7D5f4A79c5042161324376F37Dd3Db7bd3E5C2F`; agent account `0x57871B921a9868A067E722Df6C2Dd0e81EDBA91C`.

| Live scenario | Result | Tx |
|---|---|---|
| Agent **in-cap** transfer, 50 mock TUSD (cap 100) | ✅ executed; bob +50, account 1000→950, `spentTotal`=50 | `0x3233e704…65a` |
| Agent **over-cap** transfer, 150 (> cap 100) | 🛑 refused on-chain (`PerTxCapExceeded(…,150,100)`), `success=false`, **no value moved** | `0xb3aafb62…259` |
| Agent **in-cap** transfer, **50 REAL mainnet USDC** (`0xA0b8…eB48`) | ✅ executed; bob +50 USDC, account 10,000→9,950 USDC | `0xf9c55eb9…4bc` |
| **Agent-driven recovery** (agent couriers 2 cross-class guardian sigs) | ✅ owner rotated on-chain `0xa0Ee…9720` → `0x9965…A4dc`; agent cannot forge sigs | account `0x12Eb…198b` |

The realized-value cap held end-to-end on a live chain through the genuine EntryPoint — with real USDC — and an agent drove a guardian recovery without being able to authorize it. Harness: `script/CleaveE2E.s.sol` (deploy + provision), `script/BuildOp.s.sol` (build/sign a UserOp → `cast send`), `script/CleaveRecovery.s.sol` (live recovery).

## Status

✅ **59/59 tests pass** (`forge test`) — `AgentAccount` (28) + `GuardianRecovery` (16, weighted + class-diverse) + `ERC4337` (7) + `AgentAccountFactory` (4) + an end-to-end `Lifecycle` capstone (1) + 3 fuzz **invariants** (128k calls each). Plus **6 machine-checked Lean obligations** (`tama audit` clean) and a live testnet matrix against the canonical EntryPoint v0.8.

The capstone ([`test/Lifecycle.t.sol`](test/Lifecycle.t.sol)) runs the whole story: counterfactual deploy → owner provisions an agent → agent operates via the EntryPoint within caps → over-cap UserOp refused → owner revokes → agent couriers guardian sigs to drive recovery → owner rotated → new owner operates.

This is the on-chain core (blueprint Phases 1 + 3 + the 4337 surface + a deploy factory): caps and recovery that hold even if every off-chain Elytro service is gone.

### Security review

A multi-agent adversarial red-team (4 attacker lenses → skeptic verification → synthesis) was run against this code. It surfaced 15 verified findings; the exploitable ones are **fixed and regression-tested**:

| ID | Sev | Issue | Fix |
|----|-----|-------|-----|
| C1 | HIGH | Net-per-batch accounting let an in-batch inflow/rebase mask an outflow (charge ≈0) | Gross **per-call** accounting |
| C2 | HIGH | Approval ban was a 2-selector blocklist; `permit`/`setApprovalForAll`/Permit2 bypassed it | Expanded forbidden set + protected-token `transfer`-only |
| C3 | HIGH | `setGuardians` never cleared old guardians → removed guardians kept authority | Store + clear the active set |
| C4 | MED | Value exfil through a token outside the protected set | Agent `transfer` requires a protected token |
| C5 | LOW | 1-3 byte calldata routed to fallback under a NATIVE grant | Reject malformed calldata |
| C6 | LOW | `scheduleRecovery` replay reset the delay clock | Block reschedule while pending |
| U2 | LOW | Absurd delay could truncate (uint64) to the past | `MAX_DELAY` bound |

### Invariant proof

`test/Invariant.t.sol` fuzzes arbitrary agent action sequences (in-cap, over-cap, batches, inflow-masking attempts) and asserts, after every step: spend never exceeds the total cap, the amount moved exactly equals the amount charged (no value escapes accounting), and the recipient is bounded by the cap — **3 invariants × 128k calls each, 0 failures.**

### Formal verification (Lean 4 / Verity / tama)

`verify/elytro-verity/` is a [tama](https://github.com/lfglabs-dev/verity)/Lean machine-checked model of the cap-accounting core of `_charge` — same toolchain and discipline as Cleave's `Series.sol` proofs. Six obligations, **proven over all symbolic inputs** (not fuzzed), `tama audit` clean (no `sorry`, no extra axioms):

| Obligation | Proves |
|---|---|
| `charge_total_ceiling` | after a successful charge, running spend ≤ the configured total cap (the hard ceiling) |
| `charge_accounting_exact` | spend increases by *exactly* the outflow — no loss, no inflation |
| `charge_frame` | a charge mutates only the running spend; cap config is never touched |
| `charge_over_pertx_reverts` | an over-per-tx outflow reverts with no state change |
| `charge_over_total_reverts` | an over-total outflow reverts with no state change |
| `charge_uncapped_reverts` | a protected asset with no cap cannot move (fail-safe) |

Run: `cd verify/elytro-verity && tama build && tama audit` (Lean 4.22, mathlib). Verified artifact is the model of the accounting core; external calls and the rolling-window leg are out of scope (stated in the model).

### Full audit (round 2)

A second multi-agent audit (5 expert lenses → adversarial verification → synthesis) covered all contracts incl. the factory, 4337 path, and weighted recovery. Result: **no critical, no theft-class issues.** Findings fixed + regression-tested: **H1** guardian-recovery censorship (a lone sub-threshold guardian could permanently block recovery → cancel is now owner-only); **M1** a sick protected token bricking all agent execution (→ non-fatal `balanceOf`, per-token skip + `MAX_PROTECTED_TOKENS`); **M2** value-mover gap on non-protected tokens (→ `send`/`transferAndCall` now require a protected token + scope note); **L1** zero-prefixed calldata under a NATIVE grant; **L3** `delay = 0` veto-window nullification (→ `MIN_DELAY`); **I1** owner/agent principal disjointness. Documented (by design / known): agent gas prefund outside the native cap (L2), single-op-per-bundle transient handoff (L4), cross-fork domain-separator (I2).

### Remaining (by design / documented)
- **Single-guardian veto** can grief recovery liveness (C7) — the deliberate veto tradeoff; harden with a veto quorum/cooldown later.
- **Fixed-window period cap** allows ~2× across a boundary (C8); the lifetime `total` cap bounds the worst case. A sliding window is the upgrade.
- **Compromised (not lost) owner key** can veto a guardian rescue — answered by step-up on high value, not yet built.

### Not yet (dependency / research / deploy-gated)
- **Passkey (P256/WebAuthn) root** — needs the RIP-7212 precompile (or a vendored verifier) and test vectors `vm.sign` can't produce. The ECDSA owner already serves as cold root, so this is an upgrade, not a gap.
- **Per-period gas / op-count budget** — windowed counters in `validateUserOp` violate ERC-7562 bundler rules (the blueprint's open problem); needs a stateless or off-critical-path design.
- **USD-denominated caps** — needs a price oracle (blueprint open risk); caps are token-native today.
- **Testnet deploy** — `script/Deploy.s.sol` is ready and the wallet is fork-proven against the canonical EntryPoint v0.8; the live deploy itself is the outward-facing gate (needs a funded deployer key + RPC).

## Run

```bash
forge test -vv          # 54 tests incl. invariants
forge test --no-match-test invariant   # fast (skip fuzz)
```
