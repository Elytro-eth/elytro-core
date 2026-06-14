import ElytroVerity.Spec.ChargeCoreSpec
import Verity.Proofs.Stdlib.Automation

/-!
Dischargers for the `ChargeCore` spec obligations. Tama discovers each theorem
by its conclusion (a spec application). The model is the security-relevant path
of `AgentAccount._charge`; these prove the cap is a hard ceiling, the accounting
is exact, the config is framed, and out-of-bound / uncapped charges revert with
no state change.
-/

namespace ElytroVerity.Proof.ChargeCoreProof

open Verity
open Verity.EVM.Uint256
open ElytroVerity
open ElytroVerity.Spec.ChargeCoreSpec
open ElytroVerity.ChargeCore

-- ── word/Nat bridging helpers (conclusions are not spec applications) ──

theorem lt_modulus_of_le_max {x : Nat}
    (h : x ≤ Verity.Stdlib.Math.MAX_UINT256) :
    x < Verity.Core.Uint256.modulus := by
  have hm := Verity.Core.Uint256.max_uint256_succ_eq_modulus
  simp only [Verity.Stdlib.Math.MAX_UINT256] at h
  omega

theorem val_add_rev (a b : Verity.Uint256)
    (h : (a : Nat) + (b : Nat) ≤ Verity.Stdlib.Math.MAX_UINT256) :
    ((b + a : Verity.Uint256) : Nat) = (a : Nat) + (b : Nat) := by
  have hlt : (b : Nat) + (a : Nat) < Verity.Core.Uint256.modulus :=
    lt_modulus_of_le_max (by omega)
  rw [Verity.Core.Uint256.add_eq_of_lt hlt]
  omega

-- ── revert obligations (cap refuses) ──

theorem charge_uncapped_reverts_after_run (outflow : Uint256) (s : ContractState) :
    charge_uncapped_reverts outflow s (((charge outflow).run s).snd) := by
  unfold charge_uncapped_reverts
  intro h1 hset
  have hb : ((s.storage 0) == (1 : Uint256)) = false := by
    simp only [beq_eq_false_iff_ne]; exact hset
  simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
    Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
    h1, hb]

theorem charge_over_pertx_reverts_after_run (outflow : Uint256) (s : ContractState) :
    charge_over_pertx_reverts outflow s (((charge outflow).run s).snd) := by
  unfold charge_over_pertx_reverts
  intro h1 hset hlt
  have hnot : ¬ (outflow.val ≤ (s.storage 1).val) := by omega
  simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
    Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
    h1, hset, hnot]

theorem charge_over_total_reverts_after_run (outflow : Uint256) (s : ContractState) :
    charge_over_total_reverts outflow s (((charge outflow).run s).snd) := by
  unfold charge_over_total_reverts
  intro h1 hset hpertx hov hlt
  have hovn : ¬ (Verity.Stdlib.Math.MAX_UINT256 < (s.storage 7).val + outflow.val) := by omega
  have hsum : ((outflow + s.storage 7 : Uint256) : Nat) = (s.storage 7).val + outflow.val :=
    val_add_rev (s.storage 7) outflow hov
  have hnot : ¬ ((s.storage 7).val + outflow.val ≤ (s.storage 4).val) := by omega
  simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
    Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
    h1, hset, hpertx, hovn, hsum, hnot]

-- ── success obligations ──

theorem charge_accounting_exact_after_run (outflow : Uint256) (s : ContractState) :
    charge_accounting_exact outflow s (((charge outflow).run s).snd) := by
  unfold charge_accounting_exact chargeOk
  intro h
  obtain ⟨h1, hset, hpertx, hov, htot⟩ := h
  have hovn : ¬ (Verity.Stdlib.Math.MAX_UINT256 < (s.storage 7).val + outflow.val) := by omega
  have hsum : ((outflow + s.storage 7 : Uint256) : Nat) = (s.storage 7).val + outflow.val :=
    val_add_rev (s.storage 7) outflow hov
  have hfin : ((outflow + s.storage 7 : Uint256)).val ≤ (s.storage 4).val := by
    rw [hsum]; omega
  simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
    Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
    h1, hset, hpertx, hovn, htot, hsum]

theorem charge_total_ceiling_after_run (outflow : Uint256) (s : ContractState) :
    charge_total_ceiling outflow s (((charge outflow).run s).snd) := by
  unfold charge_total_ceiling chargeOk
  intro h
  obtain ⟨h1, hset, hpertx, hov, htot⟩ := h
  have hovn : ¬ (Verity.Stdlib.Math.MAX_UINT256 < (s.storage 7).val + outflow.val) := by omega
  have hsum : ((outflow + s.storage 7 : Uint256) : Nat) = (s.storage 7).val + outflow.val :=
    val_add_rev (s.storage 7) outflow hov
  have hfin : ((outflow + s.storage 7 : Uint256)).val ≤ (s.storage 4).val := by
    rw [hsum]; omega
  simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
    Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
    h1, hset, hpertx, hovn, htot, hsum]

theorem charge_frame_after_run (outflow : Uint256) (s : ContractState) :
    charge_frame outflow s (((charge outflow).run s).snd) := by
  unfold charge_frame chargeOk
  intro h
  obtain ⟨h1, hset, hpertx, hov, htot⟩ := h
  have hovn : ¬ (Verity.Stdlib.Math.MAX_UINT256 < (s.storage 7).val + outflow.val) := by omega
  have hsum : ((outflow + s.storage 7 : Uint256) : Nat) = (s.storage 7).val + outflow.val :=
    val_add_rev (s.storage 7) outflow hov
  have hfin : ((outflow + s.storage 7 : Uint256)).val ≤ (s.storage 4).val := by
    rw [hsum]; omega
  refine ⟨?_, ?_, ?_⟩ <;>
    simp [charge, setSlot, perTxSlot, totalSlot, spentTotalSlot, getStorage, setStorage,
      Contract.run, ContractResult.snd, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
      Verity.require, Verity.Stdlib.Math.requireSomeUint, Verity.Stdlib.Math.safeAdd,
      h1, hset, hpertx, hovn, hfin]

end ElytroVerity.Proof.ChargeCoreProof
