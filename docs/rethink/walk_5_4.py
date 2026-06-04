# SPDX-License-Identifier: CC-BY-4.0
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>
# """Run the chapter §5.4 walk on the Phase-2 model (now with banks and the
# dense-with-holes forward index), then run a few adversarial checks that the
# isolation invariants actually trap. Letters A,B,... alias slots 0,1,..."""

from ce_core import Hart, CEError, InvariantError

ALIAS = {i: chr(ord('A') + i) for i in range(26)}

def show(h, title):
    print(f"\n{title}")
    for line in h.snapshot().splitlines():
        out = line
        for s, ch in sorted(ALIAS.items(), reverse=True):
            out = out.replace(f"slot {s}:", f"slot {s}({ch}):")
            out = out.replace(f"->{s}", f"->{s}({ch})")
            out = out.replace(f"owner={s} ", f"owner={s}({ch}) ")
            out = out.replace(f"current={s} ", f"current={s}({ch}) ")
        print(out)

def expect_trap(desc, fn):
    try:
        fn()
    except (CEError, InvariantError) as e:
        print(f"  TRAP (correct): {desc}\n        -> {type(e).__name__}: {e}")
        return
    print(f"  *** NO TRAP (WRONG): {desc} succeeded but should have failed")

print("=" * 70)
print("§5.4 worked walk — Phase 2 (banks + dense-with-holes forward index)")
print("=" * 70)

h = Hart(hart_id=0, n_slots=16, n_scalar_banks=8, n_vmt_banks=4)
show(h, "E0  boot — only root (A), which holds its own scalar bank (own-bank rule)")

vB = h.ec_ir()
h.bk_ie(vB, "scalar")                 # B will be a scheduler -> needs a bank
show(h, f"E1  A: ec.ir -> guest kernel B (vnum {vB}), given a scalar bank")

h.ec_ob(vB)
show(h, "E2  A: ec.ob 1 -> switch into B (B current, empty fwd)")

vC = h.ec_ir(); h.bk_ie(vC, "scalar")
vD = h.ec_ir(); h.bk_ie(vD, "scalar")
show(h, f"E3  B: ec.ir x2 -> threads C (vnum {vC}), D (vnum {vD}), each banked")

h.ec_ob(vC); h.switch_to_parent()
h.ec_ob(vD); h.switch_to_parent()
show(h, "E4  B: ec.ob 1/2 -> fast-path switch among C,D (no structural change)")

vE = h.ec_ir(); h.bk_ie(vE, "scalar")
show(h, f"E5  B: ec.ir -> thread E (vnum {vE}); only B's index changed")

h.switch_to_parent()
show(h, "E6a switch out to A — A.fwd regenerates to {1->B}, valid all along")
vF = h.ec_ir(); h.bk_ie(vF, "scalar")
show(h, f"E6b A: ec.ir -> second guest F (vnum {vF})")

freed = h.ec_ot(vB)
show(h, f"E7  A: ec.ot on child {vB} (B) -> freed {freed} ECIDs (B,C,D,E); banks reclaimed")

print(f"\nE8  F still has vnum {vF}; A.fwd shows a hole at 1 (not renumbered).")

print("\n" + "=" * 70)
print("Adversarial checks — the isolation invariants must TRAP")
print("=" * 70)
# We're currently at root A, with child F (vnum 2) and a hole at vnum 1.
expect_trap("switch to vnum 0 (self)", lambda: h.ec_ob(0))
expect_trap("switch to the hole at vnum 1 (torn-down B)", lambda: h.ec_ob(1))
expect_trap("switch to a never-existed vnum 99", lambda: h.ec_ob(99))
expect_trap("tear down a vnum we don't own (99)", lambda: h.ec_ot(99))
# F exists (vnum 2) but switching needs a bank — give F none and try:
# (F was given a bank in E6b, so this one should SUCCEED — sanity, not a trap)
try:
    h.ec_ob(vF)
    print(f"  OK (correct): switch into F (vnum {vF}) succeeded — it owns a bank")
    h.switch_to_parent()
except (CEError, InvariantError) as e:
    print(f"  *** WRONG: switch into banked F failed: {e}")

print("\nAll structural invariants held after every operation (checker ran each time).")
