# elytro-agent (CLI shim)

An agent-facing CLI for the [elytro-core](../README.md) agent-native smart account. The human delegates once; the agent then operates autonomously **within on-chain realized-value caps**, and escalates when an action falls outside its envelope. Deterministic JSON output, for agents.

## Install

```bash
cd cli && bun install        # or: npm install
```

## Config (env or flags)

| Env | Meaning |
|---|---|
| `ELYTRO_RPC` | RPC URL (required) |
| `ELYTRO_FACTORY` | AgentAccountFactory address |
| `ELYTRO_ENTRYPOINT` | EntryPoint (default `0x4337…F108`, v0.8) |
| `ELYTRO_OWNER_KEY` | owner (root) key — used by `create`/`grant`, and as the UserOp submitter |
| `ELYTRO_AGENT_KEY` | agent session key — signs UserOps for `send` |
| `ELYTRO_CHAIN_ID` | chain id (default `73571`) |

Every flag (`--rpc`, `--factory`, `--owner-key`, `--agent-key`, …) overrides its env var.

## The agent contract (output)

```json
{ "success": true, "result": { ... } }
{ "success": false, "error": { "code": -32010, "message": "...", "decision": "escalate", "suggestion": "..." } }
```

`decision: "allow"` → the agent may act autonomously. `decision: "escalate"` → out of the delegated envelope; get human approval or a larger grant. `send` runs the same preflight as `check` and **refuses to submit** an out-of-envelope action (`-32010`).

## Commands

```bash
# counterfactual account address
elytro-agent address --owner 0xOwner --salt myacct

# deploy the account (owner)
elytro-agent create --salt myacct

# human delegates a scoped cap to an agent
elytro-agent grant --account 0xAcct --agent 0xAgent --token 0xUSDC \
  --per-tx 100000000 --total 300000000 --expires-in 2592000

# agent asks: may I do this autonomously?
elytro-agent check --account 0xAcct --agent 0xAgent --token 0xUSDC --amount 50000000

# agent acts: capped transfer via a UserOp through the EntryPoint
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
