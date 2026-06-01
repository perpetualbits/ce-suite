# Design-Loop Protocol — Converge, Red-Team, Freeze

*Optional module. Use it when a project has a fragile design **core** — a small set of
principles and rules that must be exactly right and self-consistent before anything is
built on them. It runs in the lab (see the firewall in `methodology.md`); its output
is a frozen core the build-loop then ports into the canon.*

---

## What a "core" is

Two layers:

- **Tenets** — a short, fixed list of non-negotiable principles. Changing one is a
  deliberate, dated act.
- **Invariants** — concrete rules every operation must preserve and every
  configuration must satisfy. The tenets made precise and operational.

(Adapt the names to the domain — "principles" and "rules" work fine. The two-layer
structure is the point: principles, and the rules that operationalize them.)

## The five exit criteria

The loop is "done" only when all five hold. The architect owns this definition.

1. **Tenets frozen and self-consistent.** A fixed list is written down and the lab is
   consistent with it.
2. **Invariants enumerated.** A list that is internally non-contradictory, preserved
   by every operation, and satisfied by every configuration/profile.
3. **Cost/feasibility classified.** Every operation is accounted for against whatever
   the domain's hard constraints are (time, space, area, latency) — nothing
   unclassified, nothing unbounded where it must be bounded.
4. **Stress battery runs clean.** A set of demanding scenarios chosen to exercise the
   model's corners runs with no unresolved item.
5. **Two consecutive zero-change passes.** A red-team review produces no change to the
   tenets/invariants, and the next pass also produces none. The freeze is then a
   deliberate architect decision with a version bump.

## The two-angle red-team (criterion 5 in detail)

A pass that merely re-confirms its own earlier blind spots is worthless. So each pass
must attack from a **different angle**. Useful angles, run as separate passes:

- **Internal consistency / accuracy** — does any statement contradict another? Is any
  claim factually wrong (a scope mislabeled, a formula misdescribed, a specific
  mechanism stated as if general)?
- **Completeness** — does the model **rely on** any property that is not actually
  written down? (Check for rules cited as present but missing, and for operations that
  enforce a property no rule states. Consistency passes structurally cannot find this;
  only a completeness pass can.)
- **Correspondence / independence** — is every principle backed by a rule and every
  rule grounded in a principle (no orphan either way)? Is any rule strictly derivable
  from others (not minimal)?
- **Scenario / boundary stress** — re-run the stress scenarios and the edge cases
  (empty/zero configuration, maximum depth, destruction near the root, concurrent
  operations) against the current set; does any concrete situation satisfy the
  operations yet violate a rule?

A pass that finds something requiring a change is **not** a zero-change pass: fix it
(a deliberate, dated change), and the consecutive-clean count **resets to zero**. Two
clean passes in a row, from different angles, means converged.

## How findings are handled

- The red-team **presents** each finding; the **architect decides** whether it
  warrants a change. Tenets/invariants are frozen-in-spirit during the loop, so any
  change is a deliberate act, not the AI's call.
- Each fix is its own dated change in the lab, recorded with its reason.
- **Expect the red-team to catch the AI's own drafted wording.** That is the method
  working, not a failure. In the CE Suite run, the red-team caught a mislabeled scope,
  an over-generalized mechanism, an imprecise explanation, and — across angles — a
  load-bearing rule that had been cited as present but was never actually written
  into the list. All were fixed before the freeze.

## The freeze

When two consecutive clean passes are in hand, the architect declares the freeze with
a version bump (e.g., "Frozen Core v1.0"). Record:

- That the core is frozen, as of a date, at a version.
- The exact frozen set (which principles, which rules).
- That changing any frozen item now requires a deliberate **un-freeze** with a new
  version bump.
- What comes next: the build-loop that ports the frozen core into the canon.

After the freeze, routine work no longer edits the core. New questions about it are
handled as explicit un-freeze decisions, not drift.

## One honest expectation

This protocol does not make the AI correct. It assumes the AI may be wrong and is
built to **find** the wrong parts — repeatedly, from different angles — before they
are frozen. The trustworthy output is the converged, adversarially-reviewed core plus
the dated record of every correction along the way.
