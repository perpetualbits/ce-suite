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
- Push to the remote regularly. A local-only repo doesn't survive a
  laptop accident.

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
7. Save to disk, commit to git with a descriptive message.
8. End the chat.
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
   Please read docs/charter/project_instructions.md and
   docs/charter/CHANGELOG.md. Do not edit yet."
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

If any answer is no, fix that before continuing. None of these checks
are time-consuming; skipping them is what produced the previous mess.

---

*End of Working Notes for Authors.*
