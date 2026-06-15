# elytro-agent (CLI shim)

An agent-facing CLI for the [elytro-core](../README.md) agent-native smart account. The human delegates once; the agent then operates autonomously **within on-chain realized-value caps**, and escalates when an action falls outside its envelope. Deterministic JSON output, for agents.

## Install

```bash
npm i -g @elytro/agent-cli      # provides the `elytro-agent` command
```

The Cleave **testnet** (chain `73571`, EntryPoint v0.8, free faucet, no real money) is baked in as the default RPC + factory, so a fresh install works with no config. From source: `cd cli && npm install && node build.mjs`.

## Config (env or flags)

| Env | Meaning |
|---|---|
| `ELYTRO_RPC` | RPC URL (default: Cleave testnet) |
| `ELYTRO_FACTORY` | AgentAccountFactory address (default: Cleave testnet) |
| `ELYTRO_ENTRYPOINT` | EntryPoint (default `0x4337…F108`, v0.8) |
| `ELYTRO_OWNER_KEY` | owner (root) key (**human only**), used by `create`/`grant`. The agent must never hold this. |
| `ELYTRO_AGENT_KEY` | agent session key: signs **and self-submits** UserOps for `send`. Generate with `keygen` (stored at `~/.elytro-agent/agent.key`). |
| `ELYTRO_CHAIN_ID` | chain id (default `73571`) |

The agent **self-submits** its own UserOp (acts as its own bundler), so `send` never needs the owner key, only the agent key plus a little ETH for base gas (refunded to the agent). Every flag (`--rpc`, `--factory`, `--owner-key`, `--agent-key`, …) overrides its env var.

## The agent contract (output)

```json
{ "success": true, "result": { ... } }
{ "success": false, "error": { "code": -32010, "message": "...", "decision": "escalate", "suggestion": "..." } }
```

`decision: "allow"` → the agent may act autonomously. `decision: "escalate"` (`-32010`) → out of the delegated envelope; get human approval or adjust the grant. `-32012` → the action would fail to execute (funding / token). `send` runs the same simulation as `check`/`simulate` and **refuses to submit** (no gas spent) anything out of envelope.

Claim a transfer succeeded **only** when `result.executed === true` and `result.userOpSuccess === true`. Never infer success from `result.status` (the bundle tx status is `"success"` even when the EntryPoint caught an inner revert and the contract refused the operation).

## Commands

```bash
# (agent) once: generate + store the agent session key, print the agent address
elytro-agent keygen
elytro-agent whoami                       # reprint the agent address anytime

# counterfactual account address
elytro-agent address --owner 0xOwner --salt myacct

# (human/owner) deploy the account
elytro-agent create --salt myacct

# (human/owner) delegate a scoped cap to an agent
elytro-agent grant --account 0xAcct --agent 0xAgent --token 0xUSDC \
  --per-tx 100000000 --total 300000000 --expires-in 2592000

# (agent) dry-run end to end: what would move, would it revert, remaining budget (no broadcast)
elytro-agent simulate --account 0xAcct --token 0xUSDC --to 0xBob --amount 50000000

# (agent) may I do this autonomously? allow | escalate
elytro-agent check --account 0xAcct --agent 0xAgent --token 0xUSDC --amount 50000000 --to 0xBob

# (agent) act: capped transfer via a UserOp through the EntryPoint (add --dry-run to preview)
elytro-agent send --account 0xAcct --token 0xUSDC --to 0xBob --amount 50000000

# read owner, cap, balance
elytro-agent status --account 0xAcct --agent 0xAgent --token 0xUSDC
```

## Verified live (Cleave testnet, chain 73571, real EntryPoint v0.8)

End-to-end through this CLI against real mainnet USDC (`0xA0b8…eB48`):

- `create` → account `0xE951eBac98C103e581707198AD9E3c2682A8A41d`
- `grant` → agent cap 100/tx, 300 total
- `check 50` → `allow`; `check 150` → `escalate (exceeds per-tx cap)`
- `send 50` → **executed** (tx `0x6fabae79…`), bob +50 USDC, `spentTotal` 50
- `send 150` → **refused** by the agent's own preflight (`-32010`), nothing submitted

The realized-value cap is enforced on-chain regardless; the CLI's preflight just saves a doomed transaction.
