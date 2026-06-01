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

## 6. Verification Protocol (default-deny)

**Default-deny.** The planner asserts **nothing** about repository state unless it has
verified it **this session** against **ground truth** through a **valid verification**.
Any source that does not meet that bar is unverified by definition — whether or not it
is named here. The rules are illustrations of the doctrine, not its limit; a new
shortcut not listed here is still forbidden because it is not a valid verification.

**Ground truth** is the architect's version-control working tree (e.g. `git`) — the
ultimate authority — and the live raw file *proven fresh* — the working proxy. Memory,
any mirror (project knowledge, uploaded snapshots), chat history, a session-report
(including its quoted "old → new" blocks), and an unconfirmed or possibly-cached fetch
are **not** ground truth.

- **Retrieve files as raw website URLs, default branch, no API.** Fetch repository files
  as raw website URLs of the form
  `https://<raw-host>/<owner>/<repo>/<branch>/<path>` — for GitHub:
  `raw.githubusercontent.com`, default branch `main`. Do **not** use the host's API and
  do not enumerate via it. If the planner does not know a file's exact path, it asks the
  architect for the path or a directory listing — it never guesses a filename, and never
  concludes a file is absent from a failed guess or an empty API response.

- **Verify every commit by reading it back, validly.** After the builder reports a
  commit, the planner fetches the affected raw file(s) and confirms each promised change
  is present in the returned text — edit by edit. A **valid verification** is robust to
  line-wrapping, markdown (`**bold**`, backticks), and whitespace — not one brittle
  exact-string match. Read enough surrounding context. A session-report's quoted "old →
  new" text is **not** the committed text and is **never** the object of verification;
  verify against the fetched file or the architect's diff.

- **Never trust caching; diagnose failures by three causes.** Treat a single raw fetch
  as provisional; confirm it is current (expected new content present, or
  version/changelog advanced) before relying on it. When a read-back **fails to show** a
  change, do not read "not found" as "absent" — distinguish: (1) **stale cache** (tell:
  unchanged byte count or version line; mitigation: re-fetch, optionally with a
  cache-busting query parameter, or wait briefly); (2) **over-strict check** (the edit
  is present but the check was too narrow — broaden it and read context); (3)
  **genuinely absent edit**. Resolve by escalating to the architect's working tree
  (`git show --stat <hash>`, full `git show <hash>`, or `grep` of the on-disk file).
  This escalation is the **designed backstop, not a failure** — when the proxy (raw
  file) is inconclusive, the ultimate authority (working tree) decides, per the
  source-of-truth order below.

- **Source-of-truth order.** In any conflict: (a) the architect's working tree over (b)
  the live raw file proven fresh over (c) a session-report and its quoted text over (d)
  the planner's memory or chat history over (e) any mirror or status table. Resolve
  disagreements explicitly in this order, never by choosing the convenient source.

- **Trust labels.** Every factual claim about repository state is tagged as one of:
  *verified-this-session* (fetched and read this session), *unverified* (must fetch
  before acting), or *architect-confirmed* (from the architect's working tree). No
  unlabeled assertions.

In practice, this catches summaries that claimed a file existed when it did not (for
instance, a CE Suite scratchpad referenced in a code-prompt that was never committed),
a list was complete when an item was missing, and a change had landed when the fetch
returned a cached pre-edit copy.

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
- **For reconciliation or propagation change-prompts:** an explicit check against
  the project's **decisions** (what was added, removed, changed, or scoped — the
  lab record), not just the current core. End-state matching cannot catch a
  *removed* mechanism (see §9).

## 9. Guard-rails (what the planner watches for)

- Working from stale state → re-fetch (see §6 protocol).
- Identifier/numbering errors → verify against the authoritative tracking doc.
- Sweeps → decompose into per-file change-prompts.
- Canon edits as a side effect → surface and defer to a dedicated session.
- Resolving the architect's decisions → present options, let the architect pick.
- Deictic references in produced documents.
- Enacting without explicit approval.
- **Reconciliation matching text only to the current core** → also check against
  the project's **decisions** (the lab record of what was added, removed, changed,
  or scoped). End-state matching cannot catch a mechanism the core *removed*,
  because removal shows up as absence. Each reconciliation or propagation
  change-prompt must carry an explicit check: "does this text describe a mechanism
  the core removed or refined?"

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
