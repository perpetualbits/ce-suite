# Charter Changelog

This file mirrors the changelog section of
`project_instructions.md`. Charter version bumps must update both.

## v0.7 — current

**Locked:**

- `ecs_ptr` mandated at offset 0 of `EC[e]` (§3.2, §3.3).
- ECID width = 16 bits, with PID-vs-ECID note (§3.6).
- D ≤ 3 as architectural maximum; implementations may pick smaller (§5.1).
- Instruction naming uses two-letter extension prefixes
  `{ec, cp, ms, qs}` (§6.1).
- §3.7 added covering CE disable and ignore semantics at firmware and
  per-privilege-level granularity.
- `ec.or` → `ec.od` rename confirmed; rationale parked in §8.1 for
  re-reasoning.

**Added:**

- §2.1 retired-terms list now includes `ec.or`.
- §8 open items now includes the `ec.od`/`ec.or` rationale (§8.1) and
  the CE-disable CSR specification (§8.8).

---

## v0.6

Strawman rewrite after the late-2025 / mid-2026 hiatus. Author and
Claude (Sonnet 4.5) walked the existing drafts together; Claude
produced this version after the author reviewed and reacted.

**Added:**

- Glossary with retired terms.
- Proposed ECID width (16 bits) — marked `[guess]` for author confirmation.
- Proposed D value (3) — marked `[guess]`.
- `ec.od` instruction mandate — marked `[guess]`.
- Generation counter requirement.
- Chapter-by-chapter alignment guidance (§7.3).
- Separation of workflow notes into a companion document.

---

## v0.5 — pre-hiatus

The unversioned "compressed charter" that existed before the work
was paused. Established:

- ECID-first operands (not pointers).
- The `EC[e]` array model.
- The principle "ECID is not a pointer."

This version was archived during the v0.6 rewrite. See
`docs/archive/` if a reference is ever needed.
