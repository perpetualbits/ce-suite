# Methodology — Plan-and-Build

*The authority on how the method works. Both the planner and the builder read this.
It is the generalized form of the working notes that governed the CE Suite work.*

---

## 1. Why the method exists

Two problems, solved together:

- **Getting fragile design right.** In a specification or an architecture, a single
  mis-stated rule can be wrong everywhere that depends on it. Such cores must be made
  exact and self-consistent before anything is built on them.
- **Making AI assistance trustworthy.** AI output is fluent, which is exactly why it
  is risky: confident text and neat-looking code can be subtly wrong. The method is
  built so that **the AI never has to be trusted** — a human decides everything, every
  change is independently checked, and the AI's own output is held to adversarial
  review.

## 2. The firewall

Fragile design questions are settled in **the lab** — a working document that is free
to change as much as needed and is explicitly **not** authoritative. Finished results
are ported into **the canon** (the authoritative artifacts) only as deliberate,
dedicated decisions. The lab churns; the canon receives only settled conclusions.
This keeps half-formed thinking out of the canon and gives every canon change a clear,
reviewed origin.

## 3. The roles

- **Architect** (human) — makes every design and process decision. Reviews each
  change-prompt before it is executed and each result after.
- **Planner** (AI, chat) — discusses options, drafts proposals, writes change-prompts.
  Cannot touch the repository. **Presents options and lets the architect choose** on
  any decision; never enacts a decision without explicit approval.
- **Builder** (AI, agentic coding tool) — given a change-prompt, makes exactly one
  file's change, runs the side-effect check, commits, and stops. Makes no design
  judgments.

Neither AI role can both decide and act. A human sits between them.

## 4. Plan-and-build (the unit of work)

Every change is one **plan-and-build**, producing one commit:

1. **Discuss.** Architect and planner talk through what needs to change.
2. **Draft.** The planner produces a **change-prompt** (see
   `change-prompt-template.md`) — scoped to one file, with a mandatory side-effect
   check and a session-report instruction. Produced **only on the architect's explicit
   approval.**
3. **Review.** The architect reads the change-prompt and pushes back on anything that
   does not match intent. *Most drift is caught here.*
4. **Execute.** The architect hands the change-prompt to a fresh builder session. The
   builder proposes a plan, the architect locks it, the builder edits one file, runs
   the side-effect check, commits, and returns a **session-report**.
5. **Close.** The architect (and planner, if reviewing) reads the session-report and
   decides whether the plan-and-build is complete. Follow-ups become future
   plan-and-builds.

Push after every commit: the planner reads from the repository, so a commit that is
not pushed is invisible to it.

## 5. The build-loop

When one large decision affects many files, it becomes **many** plan-and-builds — a
**build-loop** — never one sweep. A typical loop: canon → changelog → entry-point doc
→ each affected file → reference index → tests/model. Each step is its own session and
its own commit. The architect runs each in turn, reads each session-report, and
decides whether to continue. A build-loop may pause indefinitely; partial loops are
normal.

## 6. Verification instead of memory

The AI treats its own recollection as unreliable:

- Re-fetch the orientation chain at session start, and again whenever the repository
  may have moved (for example, after a reported commit).
- When making a factual claim about repository state, verify it first; if it cannot be
  verified, say so.
- The repository wins over any mirror. Believe the source, not the summary.

This repeatedly matters: in practice it has caught summaries that claimed a file
existed when it did not, and claimed a list was complete when an item was missing.

## 7. The deictic rule

In any produced document, use role names (architect, planner, builder), never
"I/you/me" — those break when the document is read in a different session-context.
Live chat between architect and planner may use them freely.

## 8. What a change-prompt must contain

Every change-prompt (template provided) includes:

- **Step 0 — orient.** The builder reads the orientation chain before anything else.
- **The work**, scoped to **one file**.
- **A mandatory side-effect ("propagation") check before commit:** search the rest of
  the repository for anything the change affects, and report either the specific
  places needing follow-up or an explicit "nothing else affected."
- **Hard rules** — what the session will *not* do, even if related work looks
  convenient. This is the anti-sweep boundary.
- **A session-report instruction** — what the builder must report before ending.

## 9. Guard-rails (what the planner watches for)

- Working from stale state → re-fetch.
- Identifier/numbering errors → verify against the authoritative tracking doc.
- Sweeps → decompose into per-file change-prompts.
- Canon edits as a side effect → surface and defer to a dedicated session.
- Resolving the architect's decisions → present options, let the architect pick.
- Deictic references in produced documents.
- Enacting without explicit approval.

## 10. When the project has a fragile core

If there is a design core that must be exactly right before building on it, settle it
first using `design-loop-protocol.md` (converge, then survive a two-angle red-team,
then freeze). Only then begin the build-loop that ports it into the canon.

## 11. Why this is auditable

The artifact that warrants trust is not the AI; it is the **record**: a sequence of
small, single-file, individually reviewed, human-decided, repository-verified commits,
each with a stated reason and a side-effect check — plus, for fragile cores, a design
that survived adversarial review aimed at exactly the subtle errors AI output is prone
to. A skeptical reviewer can check each step without taking the AI's word for anything.
