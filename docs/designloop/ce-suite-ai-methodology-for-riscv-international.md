# How AI Was Used to Help Design the CE Suite — Method, Practice, and Why It Can Be Trusted

*A document for RISC-V International and the wider community, technical and
non-technical. It describes the process by which an AI assistant helped settle the
logical core of the Context Engine (CE) Suite, how that process actually ran, and the
specific reasons the result can be relied on. It is deliberately candid — including
about the mistakes the AI made — because honesty about limitations is what makes the
trustworthy parts believable.*

---

## 1. Why this document exists

AI systems can now produce fluent text and plausible code. That fluency is exactly
why many engineers and reviewers distrust AI output: a confident paragraph or a
neat-looking patch can be subtly wrong, and the wrongness is hard to spot precisely
because it reads well. For a hardware architecture specification — where a single
mis-stated rule can be wrong in silicon and wrong in every document that depends on
it — that distrust is not just reasonable; it is correct.

The CE Suite work took that distrust as the starting assumption. The goal was not to
"let an AI write the specification." It was to use an AI assistant inside a process
**designed so that the AI never has to be trusted** — where a human makes every
decision, every change is independently checked, and the AI's own output is held to
adversarial scrutiny before anything is committed. This document explains that
process and shows, with concrete examples from the actual work, that it caught the
AI's mistakes rather than freezing them in.

---

## 2. The two problems being solved

**Problem one — getting the logical core exactly right.** CE lets many isolated
workloads share one processor safely. Its correctness rests on a small set of
principles and rules about identity, ownership, delegation, visibility, and cleanup.
If those are even slightly inconsistent, every chapter of the specification has to be
rewritten when the inconsistency is found. So the principles and rules had to be
made exact and proven self-consistent before being written into the formal
specification.

**Problem two — the trust gap.** Any AI involvement had to be structured so that a
skeptical reviewer could verify the result without taking the AI's word for anything.

The method below addresses both at once: it is simultaneously a way to get the logic
right and a way to make AI assistance auditable.

---

## 3. The core idea: a process that does not rely on trusting the AI

The method rests on one principle: **do not trust the AI; build a process that does
not need to.** Three mechanisms implement it.

- **A human decides everything.** The architect — a person — made every
  architectural and process decision. The AI proposed options, drafted documents, and
  flagged problems, but it was structurally forbidden from enacting any decision on
  its own.
- **Verification replaces memory.** The AI did not rely on what it "remembered" about
  the project. At every step it re-read the actual repository and verified claims
  against it, and it explicitly marked anything it had not verified as unverified.
- **The AI's own output is attacked.** The process includes a built-in adversarial
  review whose job is to find errors in the design — including errors in text the AI
  itself wrote — and it must pass that review twice in a row, from different angles,
  before anything is considered settled.

The rest of the document describes how these are built into the workflow, and then
shows them working.

---

## 4. The trust architecture

### 4.1 The firewall: a laboratory separate from the specification

The fragile logical core was worked out in a separate "laboratory" document that was
free to change as much as needed. Finished results were ported into the formal
specification only as deliberate, dedicated decisions. This separation — settle the
logic in the lab, then port it deliberately — is called the firewall. It keeps
half-finished thinking out of the specification, and it means the specification only
ever receives reviewed, settled conclusions.

### 4.2 The human as the sole decision-maker

The architect held every decision. The AI's standing instructions explicitly required
it to *present options and let the architect choose* on any architectural or process
question, and never to enact a decision without explicit human approval. In practice
this meant the AI's typical output was "here are the choices and the trade-offs;
which do you want?" — and then it waited.

### 4.3 Two narrow AI roles, neither of which can act alone

AI assistance was split into two roles with deliberately limited mandates:

- A **discussion-and-drafting** role: it talked through the design with the architect,
  prepared proposals, and wrote up precise instructions for changes. It could not
  touch the repository.
- An **execution** role: given a written instruction, it made **exactly one file's
  worth of change**, ran a mandatory check for side-effects, and committed — then
  stopped. It made no design judgments.

Neither role could both decide and act. The discussion role could draft but not
change anything; the execution role could change one file but not decide what the
change should mean. A human sat between them, reviewing the instruction before it was
executed and the result after.

### 4.4 One change at a time, with a mandatory side-effect check

Every change was scoped to a single file and a single session. Before each commit, a
mandatory "propagation check" searched the rest of the project for anything the change
might affect, and reported it explicitly — either the specific places needing
follow-up, or an explicit statement that nothing else was affected. Large sweeping
edits were forbidden; a change that touched many files was broken into many separate,
individually reviewed steps. This makes every change small, legible, and reversible,
and it makes the full history an auditable trail of single steps with stated reasons.

### 4.5 Verification instead of memory

The AI treated its own recollection as unreliable. At the start of each session and
whenever the repository might have moved, it re-fetched the actual files and worked
from them. When it made a factual claim about the state of the project, it verified it
first, and when it could not, it said so. This discipline repeatedly mattered (see
Section 5).

### 4.6 The exit test: converge, then survive two adversarial passes

The design was only declared finished against five explicit conditions: the
principles fixed and self-consistent; the rules enumerated, non-contradictory,
upheld by every operation, and satisfied by every configuration; every operation's
cost classified; a battery of stress scenarios passing; and — the crucial one — a
**red-team review that produces no change, twice in a row, from different angles.**
The "twice, from different angles" requirement is what guards against a review that
merely re-confirms its own earlier blind spots.

---

## 5. How it actually went

The final phase of the work is a useful case study, because it shows the safeguards
catching real errors — several of them in the AI's own drafted text.

**Stopping to flag a contradiction rather than proceeding.** Early in the phase, the
AI was asked to close the last open validation item. While doing so it discovered
that the project's own notes contradicted themselves about whether a feature (I/O
quality-of-service) was in or out of scope — two sections said opposite things, and an
earlier summary had over-claimed that a needed document existed when it did not. The
AI did not pick an interpretation and move on. It stopped, laid out the contradiction,
and asked the architect to decide. The architect resolved it, and a separate, recorded
correction fixed the contradictory notes.

**The red-team finding the AI's own mistakes.** The adversarial review ran several
times. It found and the architect corrected a series of genuine defects — and notably,
several were in wording the AI itself had drafted:

- A core principle wrongly described machine-wide bandwidth as "per-thread."
- A rule wrongly described *all* divisible resources as machine-wide, when cache is
  per-core.
- An explanation the AI had written claimed a bandwidth reading depended only on a
  workload's own data, when in fact it also uses the parent's data; the AI's first
  draft of the fix was itself imprecise and was caught on the next pass.
- An interrupt-specific cleanup sequence had been over-generalized to all cases.
- A principle stated as "acyclic" sat in tension with a deliberate self-reference at
  the root, and was tightened.
- Most strikingly: a **load-bearing rule that had been referred to throughout the
  notes as present and complete was, in fact, never actually written into the list.**
  The earlier consistency reviews had not caught it because they checked the rules
  that *were* written for contradictions; only a review aimed specifically at
  *completeness* — "does the design rely on anything that isn't actually written
  down?" — surfaced it.
- A confidentiality guarantee that two operations enforced was not captured by any
  rule, and was added.

Each was fixed as a separate, dated, human-approved change, and after each fix the
two-pass review restarted. The design was declared converged only after the corrected,
completed set survived two consecutive clean passes from different angles. At that
point the architect — not the AI — made the deliberate decision to freeze it.

The point of recounting these is not that the AI was unreliable. It is that **the
process was built to assume it might be, and the process worked**: the errors were
found and corrected before anything was frozen, and the ones in the AI's own writing
were caught by the same machinery as the others.

---

## 6. Why this warrants trust

A reviewer skeptical of AI output can check each of these and does not have to take
the AI's word for any of them:

- **Every decision was human.** The AI proposed; the architect chose. No
  architectural or process decision was made by the AI.
- **Nothing was committed unreviewed.** Each change was a single file, accompanied by
  a written instruction reviewed before execution and a result reviewed after, with a
  mandatory side-effect check and a recorded commit. The history is a step-by-step,
  auditable trail.
- **The AI's output was treated as suspect by design.** The adversarial review exists
  specifically to find errors in the design, including in AI-written text, and it did.
  Convergence required surviving that review twice, from different angles.
- **The AI verified rather than asserted.** It re-read the repository instead of
  trusting its memory, and it flagged claims it had not checked — including, in one
  case, an over-claim in the project's own earlier notes.
- **The AI surfaced its own uncertainty.** When something was genuinely arguable, it
  said so and handed the decision to the architect rather than resolving it silently.

In short, the trustworthy artifact is not the AI. It is the **record**: a sequence of
small, individually reviewed, human-decided, repository-verified changes, plus a
design that has survived adversarial review aimed at exactly the kind of subtle error
that makes AI output risky.

---

## 7. What this does *not* claim

Honesty about the limits is part of the case:

- The AI did **not** autonomously design CE. It accelerated and supported a human
  architect's design work. The intellectual decisions were the architect's.
- The AI **did** make mistakes, including in its own drafted wording. The value here
  is not an infallible AI; it is a process that catches AI mistakes before they
  matter.
- This describes **one project's methodology**, not a general guarantee about AI. It
  shows a way to use AI assistance that is auditable and that does not require trusting
  the AI — which is a narrower and more defensible claim than "AI can be trusted."
- The formal specification remains the authoritative artifact. The AI-assisted lab
  work produced a settled logical core; turning it into the specification is ongoing,
  human-reviewed work.

---

## 8. Takeaway

The CE Suite work suggests a concrete answer to the distrust of AI-generated text and
code: **do not ask reviewers to trust the AI — give them a process that makes trust
unnecessary.** Keep every decision human. Make every change small, reviewed, and
recorded. Verify against the source rather than the AI's memory. And build in an
adversarial review, run more than once from different angles, whose explicit job is to
find the AI's errors — then show that it did.

What can be trusted, in the end, is not the fluency of the output but the auditability
of the path that produced it.

---

*This document describes the methodology and its outcome for the CE Suite logical
core. The technical design itself is available in a companion plain-language document;
the authoritative source is the CE Suite specification.*
