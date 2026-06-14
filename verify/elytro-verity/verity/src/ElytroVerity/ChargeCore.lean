import Contracts.Common

namespace ElytroVerity

open Verity hiding pure bind
open Contracts hiding blockTimestamp mulDivDown
open Verity.EVM.Uint256
open Verity.Stdlib.Math

/-!
`ChargeCore` is a Verity port of the security-relevant path of
`AgentAccount._charge` — the realized-value accounting that bounds what a
delegated agent can move per protected asset.

Solidity (`src/AgentAccount.sol`, `_charge`):

    if (outflow == 0) return;                 // no realized outflow — noop
    Cap storage c = _caps[agent][asset];
    if (!c.set) revert UncappedProtectedAssetMoved(asset);
    if (c.perTx != 0 && outflow > c.perTx) revert PerTxCapExceeded(...);
    // (rolling-window period sub-logic omitted in this scoped model)
    if (c.total != 0 && c.spentTotal + outflow > c.total) revert TotalCapExceeded(...);
    c.spentTotal += outflow;                  // checked add (Solidity 0.8)

Modeling scope (stated as assumptions, in the Cleave-Verity style):
  * One (agent, asset) capability, its `Cap` fields held in flat slots that
    mirror the struct order (set 0, perTx 1, perPeriod 2, period 3, total 4,
    spentPeriod 5, periodStart 6, spentTotal 7).
  * We model a CONFIGURED, BOUNDED cap (perTx ≠ 0, total ≠ 0) — exactly the
    case the cap-soundness property is about. The `== 0` "unlimited" sentinels
    are a convenience with no ceiling to prove.
  * The rolling-window period leg is out of scope here; the per-tx and total
    ceilings (the hard caps an agent can never exceed) are what is proven.
  * `requireSomeUint (safeAdd …)` is the exact emulation of Solidity 0.8's
    checked `c.spentTotal + outflow`: it reverts on the same overflow.
-/
verity_contract ChargeCore where
  storage
    setSlot : Uint256 := slot 0          -- 1 = cap configured
    perTxSlot : Uint256 := slot 1        -- per-tx ceiling (modeled ≠ 0)
    perPeriodSlot : Uint256 := slot 2    -- (unused in this scoped model)
    periodSlot : Uint256 := slot 3       -- (unused)
    totalSlot : Uint256 := slot 4        -- lifetime ceiling (modeled ≠ 0)
    spentPeriodSlot : Uint256 := slot 5  -- (unused)
    periodStartSlot : Uint256 := slot 6  -- (unused)
    spentTotalSlot : Uint256 := slot 7   -- running lifetime spend

  -- Charge one realized outflow against the cap. Reverts unless the cap is
  -- configured and the outflow is within both the per-tx and lifetime ceilings.
  function charge (outflow : Uint256) : Unit := do
    require (outflow >= 1) "Nothing to charge"
    let isSet ← getStorage setSlot
    require (isSet == 1) "Uncapped protected asset"
    let perTx ← getStorage perTxSlot
    require (outflow <= perTx) "Per-tx cap exceeded"
    let total ← getStorage totalSlot
    let spent ← getStorage spentTotalSlot
    let newSpent ← requireSomeUint (safeAdd spent outflow) "Spend overflow"
    require (newSpent <= total) "Total cap exceeded"
    setStorage spentTotalSlot newSpent

/-- Success preconditions for `charge` (a predicate, NOT a spec obligation):
    a configured cap, a within-bounds outflow, and the checked-add not
    overflowing (implied by `spent + outflow ≤ total ≤ MAX`). -/
def chargeOk (outflow : Uint256) (s : ContractState) : Prop :=
  1 ≤ outflow.val ∧
  s.storage 0 = 1 ∧
  outflow.val ≤ (s.storage 1).val ∧
  (s.storage 7).val + outflow.val ≤ Verity.Stdlib.Math.MAX_UINT256 ∧
  (s.storage 7).val + outflow.val ≤ (s.storage 4).val
