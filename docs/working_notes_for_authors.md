<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Working Notes for Authors

**Purpose:** This document is the workflow companion to the Project Instructions.
The charter says *what* the CE Suite is. This document says *how to work on it*
without making a mess.

It is not normative on the architecture. It *is* normative on the process —
following it is what keeps the comb sharp and prevents the kind of drift that
defeated the previous attempt.

**Audience:** Yourself, future-you, any collaborator, and any AI assistant
you bring in (Claude, Claude Code, or otherwise). When you start a chat
about CE work, this is one of the documents the assistant should be told
to read.

---

## Part 1 — The five rules

These are the rules that, if followed, prevent the catastrophic drift
patterns from the previous attempt at this project. Each rule has a
rationale; understand the rationale and the rule follows naturally.

### Rule 1: The charter is the comb

When in doubt, **the Project Instructions win**. If you find yourself
reading a chapter that contradicts the charter, the chapter is wrong,
not the charter. Don't argue with the charter mid-chapter-edit.

This is the load-bearing rule. Every other rule is a refinement of it.

**What this means in practice:**

- Start every CE work session by re-reading the charter. Yes, every session.
  It's short.
- When an AI assistant produces text that contradicts the charter, the text
  is wrong. Don't accept it just because it sounds plausible.
- When *you* have an intuition that contradicts the charter, write the
  intuition down somewhere (a scratchpad, a chat about charter changes,
  a note to self) but do not let it leak into chapter text. Either the
  intuition is wrong, or the charter needs to change — and changing the
  charter is its own dedicated activity.

### Rule 2: One chapter per session

Working on multiple chapters in one session is how chapters quietly
corrupt each other. The AI assistant — or you, frankly — will start
"harmonizing across chapters" and the harmonization will silently propagate
the wrong choice. This happened repeatedly in the previous attempt.

**The right pattern:**

1. Pick a chapter.
2. Start a fresh chat.
3. Have the assistant re-read the charter, the refamiliarize doc, and the
   target chapter — and nothing else, except specific scratchpads relevant
   to that chapter.
4. Refactor the chapter.
5. Review the diff. Commit to git.
6. End the chat.
7. Start a new chat for the next chapter.

**Resist the temptation to "fix this related thing while we're at it."**
That is the corruption vector. Make a note ("Chapter 3 mentions banks in
a way that may need updating after Chapter 2") and address it in the
Chapter 3 session.

### Rule 3: Use git transactionally

If you are not committing to git after every chapter session, you are
one bad session away from losing weeks of work. This is not paranoia.
This is the actual lived experience that produced the hiatus.

**The discipline:**

- One chapter, one session, one commit.
- Commit messages name the chapter and the change: "ch02: refactor to
  ECID operands; add ec.od; retire ec.or."
- Charter bumps are their own commits: "charter: v0.7 — lock ecs_ptr at
  offset 0, ECID 16 bits, D≤3, add §3.7 disable/ignore."
- Push to the remote **immediately after every commit, in the same
  turn**. Web-based AI sessions read the project from GitHub; a
  local-only commit means the next session sees stale content and
  may duplicate or conflict with work just done.
- A local-only repo also doesn't survive a laptop accident.

**When something goes wrong**, `git reset --hard HEAD` and you've lost
at most the current session's work. Without git, that same situation
costs you days.

### Rule 4: Don't let the assistant sweep

When an AI assistant offers to "harmonize the terminology across all
chapters in a single pass," **say no**. Sweep operations are seductive
because they sound efficient. They are the single most destructive
operation in this project's history.

The reason sweeps fail: the assistant has to make a hundred small judgment
calls in a row without you reviewing each one. It will get most of them
right and a few of them wrong, and the wrong ones will be silently
embedded in files that already looked correct. You'll find them weeks
later in the middle of doing something else.

**The right pattern:**

- Sweeps are decomposed into per-chapter passes.
- Each pass gets its own session, its own review, its own commit.
- The assistant may *plan* a sweep ("here are the 8 chapters where
  'Pool' still appears; we'll fix them one at a time, starting with
  Chapter 3"). The assistant should not *execute* a sweep across
  multiple chapters in a single turn.

### Rule 5: Open items stay open

When an item is in §8 of the charter (the "open items deferred to later
versions" list), it is open *deliberately*. Resolving it requires a
charter bump and a changelog entry — it does not happen as a side effect
of editing some other chapter.

If a chapter-refactor session tries to resolve an open item, stop.
Note the decision that was nearly made, end the session, and start a
dedicated charter-revision session to actually decide it.

---

## Part 2 — Session patterns

These are the concrete patterns for running sessions, refined from
experience.

### 2.1 The standard chapter-refactor session

```
1. Open a fresh chat.
2. First message: "We're refactoring Chapter N. Please read in order:
   docs/charter/project_instructions.md
   docs/refamiliarize.md
   docs/chapters/chNN-<name>.md
   [any specific scratchpad relevant to this chapter]
   Then describe what needs to change. Do not edit yet."
3. The assistant responds with a plan. You read it carefully.
4. You push back on anything that doesn't match your intent.
5. Once the plan is locked, the assistant produces the refactored
   chapter as a file.
6. You review the file. Iterate if needed.
7. **Propagation check (mandatory).** Before committing, the assistant
   grep-searches all other chapters, reference files, and the adoc/
   mirror for any content that references or depends on what was changed.
   It reports: (a) files that need updating and the specific lines, or
   (b) explicit confirmation that no other file is affected. This step is
   not optional and should not require prompting.
8. Apply any cross-chapter corrections identified in step 7. If a
   correction touches a second chapter, keep it minimal (a single-line
   fix or cross-reference); anything larger becomes its own session.
9. Save to disk, commit to git with a descriptive message.
10. End the chat.
```

Steps 2–4 are the most important. **Most drift gets caught at the
planning stage if you actually read the plan.** Don't skim it. The
assistant will produce a plan in a minute; reading it carefully takes
five minutes; saving five hours of corrupted-chapter recovery costs
the same five minutes.

### 2.2 The charter-revision session

```
1. Open a fresh chat.
2. First message: "We're revising the charter to resolve open item §8.X.
   Please read docs/charter/project_instructions.md. Do not edit yet."
3. The assistant responds with the open item's current state and the
   options for resolving it.
4. You discuss; you decide.
5. The assistant produces the new charter version and updates the
   changelog.
6. You review. Iterate. Commit.
7. End the chat.
8. Open a fresh chat to propagate the charter change to whichever
   chapters are affected, one at a time, per the standard chapter
   pattern above.
```

The propagation is what makes this expensive. **Resolve charter open
items in batches when it's natural**: if two items are clearly going
to resolve in compatible directions, fix them in one charter bump and
do the propagation pass once. But never let charter changes accumulate
beyond a single version bump — that's how the previous compressed
charter ended up unversioned and contested.

### 2.3 The "I'm confused, what was I doing" session

```
1. Open a fresh chat.
2. First message: "I'm coming back to this project after a break.
   Please read docs/refamiliarize.md and tell me where the project is."
3. The assistant summarizes Part A of refamiliarize.md.
4. You ask whatever questions you need to.
5. Once oriented, start a real session per 2.1 or 2.2.
```

This is the cheap session. Use it any time you're not sure where you are.
It costs almost nothing and prevents you from starting a real session
in the wrong mental state.

### 2.4 The cross-cutting question session

Cross-cutting questions ("how does decision X affect Chapters 3 and 5?")
should resolve to:

- A short, scoped chat.
- One concrete written artifact (a comment in the relevant chapter,
  a note in the changelog, a scratchpad entry, or a new open item in §8
  of the charter).
- Then end the chat.

**Do not let cross-cutting chats accumulate.** They are not a meaningful
substitute for chapter work; they are a tax on chapter work. If you find
yourself in a long cross-cutting chat, end it and convert what's been
discussed into written artifacts before resuming.

---

## Part 3 — Tone and pushback

A few notes on how to work productively with an AI assistant on this
project.

### 3.1 Push back when something feels wrong

If the assistant produces something that doesn't match your sense of
the project, say so directly. "That doesn't match what we decided in
Chapter 0." "That sounds like the Pool model we retired." "That's
introducing terminology that's not in the glossary." The assistant
will adjust, and you'll have caught a drift early.

The failure mode is the opposite: assuming the assistant must be right
because it sounds confident. **Assistants sound confident even when
wrong**, especially on novel architecture. Confidence is not evidence.

### 3.2 Ask for the reasoning

When the assistant proposes a change, ask "why?" If the answer is "to
align with charter §X," that's a good answer. If the answer is "because
this is how it's usually done in similar systems," check whether your
system is similar enough for that reasoning to apply. Your design has
several places where it deliberately diverges from convention (ECID
opacity, GroupID = ECID, the reversal trick). The assistant's training
data is mostly convention.

### 3.3 Treat the assistant's strongest suggestions skeptically

Counterintuitive but real: the suggestions an assistant makes most
confidently are sometimes the ones most likely to be wrong, because
they're the ones drawn most directly from generic training data.
Original architectural choices in your project are *not* in the
training data; they live in the charter. So when an assistant pushes
hard on a design point, double-check it against the charter.

### 3.4 But also: don't reject good suggestions just because they're suggestions

The opposite failure mode is rejecting useful refinements out of
suspicion. An assistant that flags "the PID/ECID distinction needs
explaining in §3.6" is doing useful work; ignoring it costs you a
committee question later. The discipline is to evaluate suggestions
on merit, not to accept or reject based on source.

---

## Part 4 — File hygiene

### 4.1 Where things go

If you're not sure where a new file should go:

- **Normative spec content** → `docs/chapters/` or `docs/charter/`.
- **Quick reference, lookup-style content** → `docs/reference/`.
- **Onboarding or workflow guidance** → `docs/` (top level of docs).
- **Working notes, exploratory thinking, anything tentative** → `scratchpads/`.
- **Code that supports the spec** (simulators, calculators) → `tools/`.
- **Hardware sources** (RTL, testbenches) → `hw/`.
- **Software sources** (kernel patches, tests) → `sw/`.
- **Anything obsolete** → `docs/archive/` (do not delete).

### 4.2 When in doubt, scratchpad first

If you have an idea that might become spec content but you're not sure,
write it in a scratchpad first. Promote it to a chapter only when it's
clearly the right thing. The reverse — writing speculatively in a
chapter and then having to back it out — is what creates the kind of
drift the comb is meant to prevent.

### 4.3 Don't delete

Almost nothing in this project should ever be deleted. Obsolete drafts
go to `docs/archive/` with an explanation. Old scratchpads stay where
they are. The audit trail is part of the work.

The exception: editor backup files, build artifacts, and personal
secrets. The `.gitignore` handles these.

### 4.4 One canonical version of each thing

For any concept (e.g., the ECID definition), there is exactly one
canonical place where it lives: §2 of the charter, in this case.
Other documents may reference that canonical definition but do not
duplicate it.

When you find duplication ("the ECID is also defined in Chapter 1"),
delete the duplicate and link to the canonical definition instead.
Duplicates drift; canonical references don't.

---

## Part 5 — Specific lessons from the previous attempt

These are concrete patterns that hurt the project before. Recognize them
when they recur.

### 5.1 Pools kept coming back

After Pools were retired in Chapter 0, they kept reappearing in chapter
edits and AI responses for months. The reason: "Pool" is a common word
in the surrounding training data (Linux thread pools, memory pools, GPU
warp pools), so any context that mentions resource scheduling tends to
drift toward the word.

**Defense:** Pool is explicitly listed in the charter's retired-terms
section. Any chapter using the word "Pool" is wrong. Search for it
when reviewing.

### 5.2 Pointer-based operands kept reappearing

CME instructions were defined to take ECID numbers as operands, but
chapters kept re-introducing pointer-based operands because "load
pointer to struct, dereference, call instruction" is a common idiom
in operating systems. The training data favors it.

**Defense:** Charter §6.2 explicitly forbids pointer operands.
Chapter 5 frames pointer use as a Linux convention, not as architecture.
Any architecture chapter using pointers in instruction signatures is wrong.

### 5.3 The charter itself got drift-edited

When the charter was unversioned and lived next to the chapters, AI
sessions would sometimes "improve" the charter as a side effect of
editing a chapter. By the time it was noticed, the charter had been
quietly weakened.

**Defense:** The charter now lives in `docs/charter/` with its own
changelog and version number. Charter edits are deliberate, dedicated
sessions. Drive-by charter edits are not allowed.

### 5.4 Multiple Chapter 0 drafts existed simultaneously

At one point there were three versions of Chapter 0 in the same folder,
all of them seeming current. This is what made the comb idea seem to
fail — there was no single comb to follow.

**Defense:** There is exactly one current Chapter 0:
`docs/chapters/ch00-fundamental-structure.md`. The other two are in
`docs/archive/`. If a third version reappears, that's drift; archive
it or delete it (rare, see Rule 4.3) immediately.

### 5.5 MSE and QoS chapters now exist

`docs/chapters/ch09-mse-memory-scheduling.md` and
`docs/chapters/ch11-qos-io-quality-of-service.md` both exist and are
the normative reference for their extensions. The `scratchpads/mse/`
material has been superseded; treat it as archive only.

Known open items for ch09 and ch11 are tracked in `docs/work-items.md`
(F4 for ms.it encoding; D4/F2 for qs.or/qs.ot domain selector).

---

## Part 6 — A short pre-flight checklist

Before you start any CE work session, run through this list mentally:

- [ ] Do I know what session this is — chapter refactor, charter revision,
      orientation, or cross-cutting question?
- [ ] Have I opened a fresh chat for it?
- [ ] Has the assistant been told to read the charter and refamiliarize
      doc first?
- [ ] Am I working on one chapter, not many?
- [ ] Is my repo clean (no uncommitted work that could collide with this
      session's changes)?
- [ ] Do I know what "done" looks like for this session, and how I'll
      commit the result?
- [ ] Has the propagation check been run (§2.1 step 7) — has the
      assistant searched for cross-chapter effects and reported them
      explicitly?
- [ ] Did I push after the last commit? (`git push` must follow every
      `git commit` in the same turn — web Claude reads from GitHub.)

If any answer is no, fix that before continuing. None of these checks
are time-consuming; skipping them is what produced the previous mess.

---

## Part 7 — Vocabulary for the chat-and-code workflow

This part names the participants, artifacts, and patterns used when web-Claude
(in claude.ai) and code-Claude (Claude Code) work together to produce changes
in this repo. The rules in Parts 1–6 still apply; Part 7 adds the vocabulary
that makes those rules easier to discuss and harder to forget.

### 7.1 The vocabulary

| Term | Meaning |
|---|---|
| architect | Roland Nagtegaal. The decision-maker. |
| web-Claude | Claude in claude.ai. Discusses, drafts, prepares code-prompts. |
| code-Claude | Claude Code in the architect's terminal. Reads the repo, executes one file edit per session, commits. |
| code-prompt | The document web-Claude produces for code-Claude. Contains the prompt and any supporting content. |
| session-report | What code-Claude returns at session end. Records what was done, what was checked, and the commit hash. |
| prompt-and-code | The chat-then-code workflow producing one commit. |
| prompt-to-code-loop | A multi-session sequence after a charter-level decision, where each affected file is its own prompt-and-code. |

Case-insensitive variants (web-claude, webclaude, code-claude, codeclaude,
code-prompt, codeprompt, session-report, sessionreport) are all the same
term. Hyphenation may vary; meaning does not.

### 7.2 The deictic rule

In any document either Claude produces — code-prompts, scratchpad entries,
working-notes additions, drafts of any kind — use role names: architect,
web-Claude, code-Claude. Never "I" / "you" / "me" / "we" / "us".

In chat between architect and web-Claude, deictic words are fine; the
context is unambiguous.

The reason: documents are read in session-contexts different from the one
that wrote them. A code-prompt drafted in a web-Claude session is read
hours or days later by a code-Claude session. "I" then refers to no
particular agent and "you" can mean either Claude depending on who is
reading. Role names stay stable across the gap.

The rule applies to every kind of document, not just code-prompts:
scratchpad notes, working-notes additions, charter drafts, README text,
session-report excerpts quoted elsewhere. Anywhere the document might be
read outside its originating chat, role names are mandatory.

### 7.3 The prompt-and-code shape

A prompt-and-code is a single completed cycle producing one commit. Its
phases:

1. **Chat phase.** The architect and web-Claude discuss what needs to
   change. Web-Claude proposes; the architect decides. No decision is
   enacted automatically. The architect's explicit approval gates the
   transition to phase 2.

2. **Drafting phase.** Web-Claude produces a code-prompt: a document
   containing the prompt for code-Claude plus any supporting content
   (templates, content blocks to insert, propagation-check queries).
   Every code-prompt must include:
   - **Step 0: orient.** Code-Claude reads the orientation chain
     (CLAUDE.md, charter, refamiliarize, working notes, plus any
     relevant sub-project CLAUDE.md) before any other action.
   - **The work.** Scoped to one file, per Rule 2 in Part 1.
   - **A mandatory propagation check** before commit, per the standard
     chapter-refactor session pattern in §2.1 step 7.
   - **Hard rules.** What the session will NOT do, even if related work
     seems convenient. This is the anti-sweep enforcement at the
     session boundary.
   - **A session-report instruction.** What code-Claude must report
     before ending.

3. **Execution phase.** The architect hands the code-prompt to a fresh
   code-Claude session. Code-Claude executes, commits, ends the
   session, and produces a session-report.

4. **Closure phase.** The architect reads the session-report and decides
   whether the prompt-and-code is complete. If propagation revealed
   additional work in other files, those become future prompt-and-codes,
   often in a prompt-to-code-loop.

### 7.4 The prompt-to-code-loop

When one charter-level decision affects many files, it requires many
prompt-and-codes — not one big sweep. The series is a prompt-to-code-loop.

Typical example: a charter change to a normative rule propagates as
charter → CHANGELOG → ch00 → each affected chapter → CSR reference (ch13)
→ Sail. Each propagation step is its own session. Each is its own commit.
Each session-report either confirms that step is done or surfaces
additional follow-ups.

The loop is not a sweep. The architect runs each session in turn, reads
each session-report, and decides whether to continue. A prompt-to-code-loop
may pause indefinitely — there is no requirement to finish one before
starting other work. Partial loops are normal.

### 7.5 What web-Claude does and does not do

Web-Claude:
- Discusses, proposes, drafts.
- Re-fetches the orientation chain at session start, and again when
  context suggests the repo has moved (for example, after the architect
  reports a recent commit from code-Claude).
- Produces code-prompts only on the architect's explicit approval.
- Asks for clarification rather than guessing on architectural calls.

Web-Claude does not:
- Enact decisions without explicit architect approval.
- Resolve open items as a side effect of discussion.
- Propose multi-file changes packaged as a single code-prompt; decomposition
  into per-file code-prompts is mandatory.
- Use deictic words in produced documents.

### 7.6 What code-Claude does and does not do

Code-Claude:
- Reads the orientation chain before any other action, every session.
- Executes the code-prompt for the scoped file or files (typically one).
- Performs the mandatory propagation check before staging.
- Commits and produces a session-report.

Code-Claude does not:
- Touch files outside the code-prompt's scope, even if the change seems
  small or related.
- Re-interpret the architect's intent silently — when uncertain, stop and
  ask via the session-report.
- Skip the orientation read because a prior session "already did it" —
  every session starts fresh.

### 7.7 What the session-report must contain

The session-report is the architect's record of what happened. At minimum:
- What was changed (file, scope, brief description).
- What was checked (the propagation findings — full list, not just
  highlights).
- The commit hash, so the architect can verify and reference later.
- Any flagged anomalies: structure mismatches, unexpected content,
  cases where code-Claude stopped rather than guessing.

Session-reports are not throwaway. They become the audit trail when the
architect, weeks later, asks "what touched this file and why?"

---

*End of Working Notes for Authors.*
