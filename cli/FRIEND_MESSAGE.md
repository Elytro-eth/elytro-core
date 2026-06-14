# Message to send a friend

Hey! I built an agent-native Ethereum wallet and I want your Claude Code to be able to use it.

The idea: you stay in control. You hold the root key (kept cold), but you delegate a spending cap to your Claude, and the cap is enforced on-chain by the contract. So your Claude can send/pay within the budget you set, fully autonomously, and literally cannot exceed it or touch your root key, even if it goes off the rails. Above the budget it just stops and asks you.

It's on a testnet (chain 73571), free faucet funds, zero real money at risk.

~5 minutes:

1. Install: `npm i -g @elytro/agent-cli`
2. Give your Claude the skill: copy SKILL.md from the package into `.claude/skills/elytro/` (find it at: `npm root -g` then `/@elytro/agent-cli/SKILL.md`).
3. One-time setup: have your Claude run `elytro-agent keygen`. It generates its own session key and prints an address. Then (with your owner key) you create an account, faucet it, and grant that address a cap. Full walkthrough in FRIEND_SETUP.md.
4. Use it: tell your Claude to check the wallet and send. It'll act within the cap and escalate above it.

It's open-source, fully audited, and formally verified. The spending cap is a machine-checked theorem, not just a hope.

Ping me and I'll walk you through the grant step; that's the only part that needs your root key.
