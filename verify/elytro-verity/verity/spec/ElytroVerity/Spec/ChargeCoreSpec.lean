import ElytroVerity.ChargeCore

namespace ElytroVerity.Spec.ChargeCoreSpec

open Verity
open ElytroVerity  -- brings `chargeOk` (the precondition predicate) into scope

-- Slots: 0 set, 1 perTx, 2 perPeriod, 3 period, 4 total,
--        5 spentPeriod, 6 periodStart, 7 spentTotal.

/-- HEADLINE: the lifetime cap is a hard ceiling. After a successful charge the
    running spend never exceeds the configured total. -/
def charge_total_ceiling (outflow : Uint256) (s s' : ContractState) : Prop :=
  chargeOk outflow s →
    (s'.storage 7).val ≤ (s.storage 4).val

/-- Accounting is exact: the running spend increases by exactly the outflow
    (no loss, no inflation). -/
def charge_accounting_exact (outflow : Uint256) (s s' : ContractState) : Prop :=
  chargeOk outflow s →
    (s'.storage 7).val = (s.storage 7).val + outflow.val

/-- Frame: a charge mutates only the running spend — the cap configuration
    (set, perTx, total) is never touched by the agent path. -/
def charge_frame (outflow : Uint256) (s s' : ContractState) : Prop :=
  chargeOk outflow s →
    s'.storage 0 = s.storage 0 ∧
    s'.storage 1 = s.storage 1 ∧
    s'.storage 4 = s.storage 4

/-- Refusal (per-tx): an outflow above the per-tx ceiling reverts with no state
    change — the cap refuses an over-budget agent. -/
def charge_over_pertx_reverts (outflow : Uint256) (s s' : ContractState) : Prop :=
  1 ≤ outflow.val →
  s.storage 0 = 1 →
  (s.storage 1).val < outflow.val →
    s' = s

/-- Refusal (total): an outflow that would push the running spend past the
    lifetime ceiling reverts with no state change. -/
def charge_over_total_reverts (outflow : Uint256) (s s' : ContractState) : Prop :=
  1 ≤ outflow.val →
  s.storage 0 = 1 →
  outflow.val ≤ (s.storage 1).val →
  (s.storage 7).val + outflow.val ≤ Verity.Stdlib.Math.MAX_UINT256 →
  (s.storage 4).val < (s.storage 7).val + outflow.val →
    s' = s

/-- Fail-safe: a protected asset with no configured cap cannot move — the
    charge reverts and the state is unchanged. -/
def charge_uncapped_reverts (outflow : Uint256) (s s' : ContractState) : Prop :=
  1 ≤ outflow.val →
  s.storage 0 ≠ 1 →
    s' = s

end ElytroVerity.Spec.ChargeCoreSpec
