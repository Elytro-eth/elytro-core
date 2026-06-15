# AGENTS.md

Instructions for AI agents. This repo is an **agent-native Ethereum smart account**: it is built to be operated by an autonomous agent on a human's behalf, with the agent's authority bounded by the contract itself, not by prose. There are two kinds of agent who land here. Read the section that fits you.

- **Operating the wallet** (you are an agent that wants to hold/spend funds): start at [Use the wallet](#use-the-wallet).
- **Working on this codebase** (you are a coding agent asked to build/fix/review): start at [Develop this repo](#develop-this-repo).

---

## Use the wallet

You (the agent) are given a **scoped, expiring, on-chain-enforced spending capability**. You can act autonomously **within** it and must escalate to the human **outside** it. You can never exceed the cap, touch the owner key, raise your own cap, or rotate the owner. The contract refuses; you do not have to be trusted.

### 1. Install

```bash
npm i -g @elytro/agent-cli      # provides the `elytro-agent` command
```

The Cleave **testnet** (chain `73571`, EntryPoint v0.8, free faucet, no real money) is baked in as the default RPC + factory. Override with env (`ELYTRO_RPC`, `ELYTRO_FACTORY`, `ELYTRO_CHAIN_ID`, `ELYTRO_ENTRYPOINT`) or per-command flags.

### 2. The trust model (non-negotiable)

- **You hold the AGENT (session) key only.** Generate it yourself with `elytro-agent keygen` (stored at `~/.elytro-agent/agent.key`, mode 0600). Never ask for, store, or accept the owner/root key (`ELYTRO_OWNER_KEY`). If you find yourself with it, stop and tell the human: that breaks the model.
- **`create` and `grant` are the human's commands, not yours.** They need the owner key. If setup is missing, tell the human exactly which command to run and give them your agent address (from `keygen` / `whoami`).
- **Your worst case is bounded by the cap.** A compromised or mistaken agent can move at most the remaining per-tx / per-period / total budget of each protected asset, on allowlisted targets, and nothing else.

### 3. Commands you run

```bash
elytro-agent keygen                                   # once: make + store YOUR session key, prints your agent address
elytro-agent whoami                                   # reprint your agent address
elytro-agent status   --account 0xAcct --agent 0xYou --token 0xTok   # owner, your cap, spent, balance
elytro-agent simulate --account 0xAcct --token 0xTok --to 0xTo --amount 50000000   # dry-run, no broadcast
elytro-agent check    --account 0xAcct --agent 0xYou --token 0xTok --amount 50000000 --to 0xTo  # allow | escalate
elytro-agent send     --account 0xAcct --token 0xTok --to 0xTo --amount 50000000    # execute a capped transfer
elytro-agent send     ... --dry-run                   # preview a send without submitting
```

Commands the **human** runs (owner key): `create`, `grant`. Do not run these.

Amounts are **atomic units** (USDC has 6 decimals, so `50000000` = 50 USDC). Never guess a token's decimals or address; confirm with the human.

### 4. The output contract

Every command prints deterministic JSON. Parse it; do not scrape prose.

```json
{ "success": true,  "result": { ... } }
{ "success": false, "error": { "code": -32010, "message": "...", "decision": "escalate", "suggestion": "..." } }
```

| Code | Meaning | What you do |
|------|---------|-------------|
| `result.executed === true` **and** `result.userOpSuccess === true` | the transfer actually happened | report success |
| `-32010` (`decision: "escalate"`) | the contract refused on the cap/grant (per-tx, per-period, total, expiry, allowlist) | stop; ask the human to approve out of band or adjust the grant. Do not retry the same action |
| `-32012` (`decision: "failed"`) | the action would fail to execute (funding, sick token) | fix funding / token; not a grant problem |
| `-32001` | missing key / config | run `keygen` or set the env var named in the message |
| `-32602` | bad argument | fix the address/amount |

**Never infer success from `result.status`.** That is the bundle transaction status, which is `"success"` even when the EntryPoint caught an inner revert and the contract refused your operation. Use `executed && userOpSuccess`.

### 5. The right workflow

1. `simulate` (or `check`) first when unsure. `simulate` runs the real on-chain enforcement path and predicts `willMove`, `predictedError`, and remaining `headroom`. It is the honest predictor for a realized-value account.
2. If it says `allow` / `decision: "block": false`, `send`. Within the envelope, act without asking.
3. If it says `escalate` / `-32010`, do not broadcast. Tell the human: what you wanted, the cap, and ask them to approve or raise the grant.
4. On a new or unfamiliar recipient, confirm intent with the human even within cap.

### 6. Safety scope (be honest with your human)

This is **testnet-only** today. The per-tx and total caps are formally verified (Lean, machine-checked) and the contracts pass 59 tests incl. fuzz invariants plus two adversarial audits; but it is **not third-party audited**, and the per-period (rolling-window) cap sits **outside** the formal proof. Do not overstate the guarantees.

The Claude Code skill (consent model + rules) ships in the npm package as `SKILL.md`. Find it with `npm root -g` then `/@elytro/agent-cli/SKILL.md`, and drop it in `.claude/skills/elytro/SKILL.md`. Friend onboarding: [`cli/FRIEND_SETUP.md`](cli/FRIEND_SETUP.md).

---

## Develop this repo

A Foundry (Solidity) contract repo, a TypeScript agent CLI, and a Lean formal-verification project.

### Layout

| Path | What |
|------|------|
| `src/` | the contracts: `AgentAccount.sol` (the account + realized-value engine), `GuardianRecovery.sol`, `AgentAccountFactory.sol` |
| `test/` | Foundry tests incl. `Invariant.t.sol` (fuzz) and `EntryPointFork.t.sol` (opt-in fork) |
| `script/` | deploy + live-testnet harness scripts |
| `cli/` | the `@elytro/agent-cli` TypeScript CLI (viem + commander, bundled with esbuild) |
| `verify/elytro-verity/` | Lean 4 / Verity / tama machine-checked model of the cap-accounting core |

### Build & test

```bash
forge build
forge test                                   # 59 pass, 1 skipped (the opt-in fork test)
forge test --no-match-test invariant         # fast: skip the 128k-call fuzz invariants
RUN_FORK_TESTS=true forge test --match-path test/EntryPointFork.t.sol   # fork test vs canonical EntryPoint v0.8

# CLI
cd cli && npm install && node build.mjs       # -> dist/elytro.js (the published bin)
node dist/elytro.js --help

# Formal verification (needs ~/.tama/bin and ~/.elan/bin on PATH)
cd verify/elytro-verity && tama build && tama audit
```

### Conventions and guardrails

- **Do not weaken the agent invariants.** The whole thesis is that the agent is structurally incapable of the dangerous actions. Before changing `AgentAccount`, understand: realized per-call balance-delta accounting (gross, not net), the forbidden-selector set (no approve/permit/transferFrom/setApprovalForAll), no self-calls, exclusion from ERC-1271, and "uncapped protected asset must not decrease". Any change here needs a corresponding test.
- **The realized-value engine is the crown jewel.** See `test/AgentAccount.t.sol::test_RealizedValueBeatsLyingCalldata`. Keep it sound.
- **Never commit** `.lake/` (multi-GB Lean artifacts), `broadcast/`, `out/`, `cache/`, or any private key. They are gitignored; keep it that way.
- **CLI success semantics:** `send` must report the UserOperation outcome (EntryPoint `UserOperationEvent.success`), never the bundle tx status. Keep the deterministic JSON contract and error codes above stable; agents branch on them.
- **Commit messages** end with the trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Match the surrounding code's style and comment density.

### Where things are explained

The architecture, the principal model, the recovery design, the audit findings, the invariant proof, and the formal-verification obligations are all in [`README.md`](README.md). Read it before making non-trivial changes.
