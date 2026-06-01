# Change-Prompt Template

*The planner fills this in for one plan-and-build. It is scoped to exactly one file.
Use role names throughout (architect, planner, builder) — no "I/you/me". Delete the
italic guidance lines before use.*

---

# Change-prompt — {{ONE-LINE TITLE OF THE CHANGE}}

**Produced by:** planner.
**For:** a fresh builder session, run by the architect.
**Scope:** ONE file — `{{PATH/TO/FILE}}`. {{If a canon change: note "version bump +
changelog."}} No other file is edited in this session.

{{One or two sentences: what this change does and why, and which decision it enacts.}}

## Step 0 — Orient (before any other action)

Read, in order, from the live repository: {{the orientation chain — entry point;
methodology.md; the canon's current state; the status doc; plus any document directly
relevant to this change}}. Then describe the plan. Do not edit yet.

## The work (one file)

{{Precisely what changes in this file. Give the exact anchor(s) and, where helpful, the
proposed text — but mark anything the architect must settle at the planning step as a
decision, not a fait accompli. The builder proposes a plan, the architect locks it,
then the builder writes the file.}}

*{{If this is a reconciliation or propagation change: include an explicit check against
the project's decisions (the lab record of what was added, removed, changed, or scoped),
not only the current core — end-state matching cannot catch a mechanism the core removed
(it shows up as absence). State the check: "does this text describe a mechanism the core
removed or refined?" (methodology.md §9).}}*

## Planning-stage decisions for the architect (if any)

{{List anything that is the architect's call — wording, placement, an identifier or
address, a structural choice. Present options; do not pre-decide. If there are none,
say "none."}}

## Hard rules (anti-sweep enforcement)

- Edit exactly one file: `{{PATH/TO/FILE}}`. Nothing else.
- {{List the specific things this session must NOT touch — adjacent files, related
  fixes, open items — even if convenient.}}
- Do not resolve any open design question as a side effect; surface it instead.
- Do not re-open or re-argue decisions the architect has already made.
- {{If editing a non-authoritative/working doc: preserve its status and any
  history-keeping convention.}}

## Side-effect (propagation) check — before commit

Search the rest of the repository for anything that references or depends on what
changed. Report either (a) the specific files and lines needing follow-up, or (b) an
explicit confirmation that nothing else is affected. {{If known, list the expected
follow-up surface here so the builder reports against it — but the builder reports;
it does not edit those files.}} This step is mandatory and is not optional.

## Session-report instruction

Before ending, report: {{what was changed and the exact lines}}; {{any planning-stage
decision as resolved}}; the full side-effect-check result; the commit message; the
commit hash; and confirmation that `git push` followed `git commit` in the same turn.

*The report is a **claim to be verified**, not evidence. The planner verifies the commit
against the actual file, not against the report's quoted text (see Verification below).*

## Verification (read-back) — planner, after the commit

*After the builder reports the commit, the planner does not accept it on the report. The
planner fetches the affected file from the live repository as a raw website URL (default
branch, no host API) and confirms each promised change is present — a **valid
verification**: robust to line-wrapping, markdown, and whitespace; reading surrounding
context; never matching against the report's quoted text. If the read-back does not show
a change, the planner diagnoses three causes — stale cache, over-strict check, or
genuinely-absent edit — before concluding, and escalates to the architect's
version-control working tree as the designed backstop. (Full doctrine: `methodology.md`
§6.)*
