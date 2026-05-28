<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Managing Long-Running Specification Projects with AI Assistants

**Purpose:** This document captures the methodology developed during the CE Suite
RISC-V specification project. It is written to be reusable: the CE Suite is used
as a concrete example throughout, but every principle applies to any long-running
technical writing project — hardware specifications, software architecture documents,
protocol definitions, or standards proposals — especially when an AI assistant is
involved.

**The core problem this methodology solves:** Long documents written across many
sessions, with or without AI assistance, tend to drift. Chapters contradict each
other. Design decisions made in one document are silently contradicted in another.
A "quick harmonization pass" corrupts three files before anyone notices. This
document describes what to do instead.

---

## Part 1 — The fundamental principles

### 1.1 The comb

Every project needs one authoritative source of truth — a single document whose
definitions, decisions, and constraints are normative. When any other document
contradicts it, the other document is wrong. This document is called the
**comb**: when things get tangled, you run the comb through them.

In CE Suite this was `docs/charter/project_instructions.md`. In another project
it might be an architecture decision record, a protocol specification, or a
design axioms document. The name does not matter; what matters is that:

1. **It is versioned.** Every substantive change increments a version number and
   adds a changelog entry. Unversioned design documents drift without anyone
   noticing.
2. **It is the first thing read at every session.** Not occasionally. Every time.
3. **It is never edited as a side effect of other work.** Charter changes are their
   own dedicated sessions. Editing a chapter never silently changes the charter.
4. **When there is a conflict, the comb wins.** Without exception. If you think
   the comb is wrong, park the thought and open a dedicated charter-revision
   session later.

### 1.2 One unit of work per session

The single most important operational rule: **do one chapter (or one file, or one
item) per session. Commit between each. Never batch.**

This sounds inefficient. It is not. Here is why:

- Each session starts with full context (required reading). A fresh context catches
  drift that a continuing context misses.
- A commit after each unit creates a recovery point. "This session corrupted three
  files" becomes `git reset --hard` instead of lost work.
- Batching is where mistakes embed silently. A sweep of ten files will get eight
  right and two wrong. You will find the two wrong ones weeks later, in the middle
  of something else.

The discipline is: decide what one thing you are doing, do it, commit, end the
session. Start a new session for the next thing.

### 1.3 Never sweep

A sweep is any operation that touches multiple units of content in one pass:
"let me harmonize the terminology across all chapters," "let me fix this pattern
everywhere," "let me update the version reference in all files."

Sweeps fail because they require the assistant (or the author) to make dozens of
small judgment calls without review. Most will be correct. The incorrect ones
will be silent and consistent-looking, which makes them very hard to find.

**Sweeps are decomposed into per-unit passes.** The assistant may plan a sweep —
"here are the eight files where 'Pool' still appears; we will fix them one at a
time" — but it does not execute one. Each fix is its own session with its own
commit.

---

## Part 2 — Document structure

### 2.1 The document hierarchy

A well-managed specification project has a clear hierarchy. Borrowing the CE Suite
structure as a template:

```
[The Comb] — authoritative design doc, versioned, with changelog
    ↓
[Refamiliarize] — quick onboarding; summarizes current state, decisions, what's open
    ↓
[Working Notes] — process rules; how to work on this project without making a mess
    ↓
[Chapters / Content] — the actual content; derivative; must align with the comb
    ↓
[Reference / Appendices] — lookup material derived from chapters
```

Each level is derivative of the level above. A conflict always resolves in favour
of the higher level.

### 2.2 The refamiliarize document

This is one of the highest-leverage investments in a long-running project. After
any break — a week, a month, a year — you open this document first. It tells you:

- Where the project is right now.
- What has been decided and locked.
- What is still open.
- What the next step is.

Without this document, every return to the project starts with a re-read of all
the chapters to reconstruct the current state. With it, you are oriented in 15
minutes.

**Keep it current.** Every time a decision is made or a chapter is completed,
update the refamiliarize document in the same commit. A stale refamiliarize
document is worse than no refamiliarize document — it gives false orientation.

### 2.3 The working notes document

This document contains process rules, not content. It answers: how do we work on
this project? It covers:

- Session patterns (how to start and end a session correctly)
- The rules and their rationale
- Warning patterns from previous failures
- How to work with AI assistants on this project

The working notes are normative on process, not on architecture. Violation of
working notes rules does not make the content wrong; it makes a mess that
will require cleanup.

### 2.4 The AI bootstrap file (CLAUDE.md or equivalent)

When using an AI assistant, the first message it sees must prime it correctly.
Keep a small file at the project root — in Claude Code this is `CLAUDE.md` —
that tells the assistant what to read first and what rules to follow.

Example from CE Suite:

```
Read docs/charter/project_instructions.md and docs/refamiliarize.md first.
Follow the rules in docs/working_notes_for_authors.md — especially: one chapter
per session, no sweeps, no charter edits as a side effect.
```

This file is loaded automatically at the start of every session. It is the
enforcement mechanism for session discipline when working with AI.

---

## Part 3 — Tracking work

### 3.1 The work items document

Every known inconsistency, gap, and open design question lives in one place: a
work items document. This prevents the "I know there's a problem somewhere but
I can't remember where" failure mode.

Organize work items by category:

- **Design decisions required** — things that cannot be fixed until a decision is
  made. These block downstream work and must be resolved first.
- **Specification fixes** — known inconsistencies that have a clear correct answer.
- **Gaps** — places where content is missing and needs to be written.
- **Proposal/publication readiness** — items required for external submission or
  publication, independent of internal correctness.
- **Enhancements** — valuable additions that do not block the core work.

Each item records: what the problem is, what files are affected, what the
resolution is (once resolved), and what it unblocks. Resolved items stay in the
document, marked done. The audit trail is part of the value.

Include a **priority order** section that answers: if I have one session, which
item should I work on? This prevents decision paralysis at the start of each
session.

### 3.2 Open items in the comb

Architectural questions that are not yet resolved belong in the comb's own open
items section (CE Suite: §8 of the charter). This is distinct from the work items
document: the comb's open items are decisions that have not been made yet; the
work items document tracks execution work.

When an open item is resolved, it is resolved in the comb first — with a version
bump and a changelog entry — and then propagated to the affected chapters. Never
the other way around.

---

## Part 4 — The session patterns

### 4.1 The standard content session

```
1. Open a fresh chat / context.
2. Read the comb, the refamiliarize doc, and the working notes. Do not skip this.
3. Read the target chapter or file.
4. The assistant describes what needs to change. You read this carefully.
5. Push back on anything that does not match your intent.
6. The assistant makes the changes.
7. MANDATORY: Propagation check. Before committing, search for every other file
   that references or depends on what was changed. The assistant reports:
   (a) files that need updating and the specific lines, or
   (b) explicit confirmation that no other file is affected.
   This step is not optional. Do not skip it. Do not let the assistant skip it.
8. Apply any cross-file corrections identified in step 7. If a correction
   requires significant changes to a second file, stop and make it a separate
   session.
9. Commit with a descriptive message. End the session.
```

The propagation check (step 7) is where most silent drift is caught. A change to
a shared definition, a renamed instruction, a new error code — these all have
downstream references. Without the propagation check, those references become
stale without anyone noticing.

### 4.2 The design-decision session

```
1. Open a fresh chat / context.
2. Read the comb and the relevant open item.
3. The assistant presents the options with their tradeoffs.
4. You discuss and decide.
5. The assistant updates the comb: resolves the open item, bumps the version,
   adds a changelog entry.
6. Commit the comb change alone.
7. End the session.
8. Open a new session for each affected chapter and propagate, one at a time.
```

Design decisions are never made as a side effect of chapter work. If you find
yourself needing to resolve a design question while editing a chapter, stop, open
a design-decision session, resolve it in the comb, then return to the chapter.

### 4.3 The "I'm lost" session

After any break, do not try to pick up where you left off by re-reading
everything. Open a fresh session, read the refamiliarize document, and ask the
assistant to summarize the current state. This costs 15 minutes. Starting a real
session from a confused state costs hours.

---

## Part 5 — Versioning and changelog discipline

Every substantive change to the comb increments its version number and adds a
changelog entry. "Substantive" means: any change to a normative decision,
definition, rule, or scope boundary. Typo fixes and editorial cleanup do not
require version bumps.

A changelog entry should record:
- What changed (which decision or definition)
- Why it changed (or what it resolved)
- What was propagated and where

A versioned comb with a maintained changelog answers the question "when did we
decide X and why?" with a single lookup. Without versioning, this question becomes
an archaeological excavation of git history.

---

## Part 6 — Anti-drift mechanisms

### 6.1 Retired terms

Any concept that was considered and rejected — or renamed — belongs in a
**retired terms list** in the comb or the glossary. When an AI assistant generates
text that uses a retired term, it is a warning signal that the assistant is drawing
on generic training data rather than the project's specific decisions.

CE Suite examples: `Pool` (subsumed into Contract), `ec.or` and `ec.od` (renamed
to `ec.oe`), `EECID` (replaced by explicit `(hart_id, ECID)` tuple).

Keep this list current. Every retired term is a potential re-introduction vector.

### 6.2 Normative cross-references

When a chapter references a decision made in the comb, it should say so
explicitly — initially. These internal cross-references serve a useful function
during active development: they make the dependency visible and help with
propagation checks.

However, before publication, **remove cross-references to internal authoring
documents**. A published specification should not cite your design notes or
internal charter. References to internal document sections or tracking IDs
(like "P2 work item" or "charter §6.6") are scaffolding, not content. They need
to be cleaned up before external distribution.

### 6.3 The publication readiness sweep

Before any external distribution, run a dedicated pass to strip internal
scaffolding from publishable files. In CE Suite this was Category PUB in the
work items, covering:

1. **Retired instruction/term rename history** — readers of a published spec do
   not need to know that `ec.oe` was ever called `ec.or`. Remove it.
2. **Work-item tracking tags** — "(P2 work item)", "E3:", "F7" are internal
   project tracking. Remove them.
3. **Internal document citations** — "(charter §6.6)", "(see design doc §X)"
   — remove or convert to in-spec cross-references.
4. **Meta-document references** — file paths, "the comb says", "as we decided
   in session 12" — remove them.

This is a mechanical pass, not a content change. Do it file by file, one session
each, committing between each.

---

## Part 7 — Licensing and publication hygiene

### 7.1 Apply SPDX headers early

Do not wait until publication to decide on licensing. Apply SPDX headers to every
file as it is created or as a dedicated early pass. Two-line headers are
sufficient:

```
<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Author Name <email> -->
```

For generated files (like AsciiDoc mirrors of Markdown sources), update the
generator to emit the header automatically, so re-generation does not strip it.

### 7.2 Track what has been licensed

A simple checklist file listing every tracked file as `[ ]` (unlicensed) or `[x]`
(licensed), with files grouped by category (SPEC, CODE, SKIP), provides a
complete progress record and prevents omissions. Process it one file per session.

### 7.3 Separate source from generated output

Keep generated artifacts (PDFs, HTML, compiled code) out of the repository.
Use `.gitignore` and a build system (`make`). Publish generated artifacts via
release assets, not via commits to the main branch. This keeps the repository
clean and ensures generated output is always reproducible from sources.

---

## Part 8 — Git discipline

Git is not optional. It is the safety net that makes every other discipline
recoverable.

**Rules:**

- **One unit of work, one commit.** A commit should correspond to exactly one
  completed session. The commit message names the chapter or item and summarizes
  the change.
- **Commit before ending the session.** Not after starting the next one. If a
  session goes badly, `git reset --hard` should be available.
- **Push regularly.** A local-only repository does not survive hardware failure.
  Push at the end of every session, or at minimum at the end of every working day.
- **Descriptive commit messages.** "Fixed stuff" is not a commit message.
  "ch03: add ec.iv/ec.ov normative vault semantics; remove shell-only warning"
  is a commit message.
- **Do not amend published commits.** If a mistake needs correction, create a
  new commit that fixes it. Amended commits that have been pushed rewrite history
  for anyone who pulled.

---

## Part 9 — Working with AI assistants

### 9.1 The fundamental failure mode

AI assistants sound confident even when wrong. On novel or project-specific
decisions — the kind that exist in your comb and nowhere else — the assistant's
training data is irrelevant. It will produce plausible-sounding text that may
contradict specific decisions you made six months ago.

The defence is: **always have the comb in context and check every non-trivial
claim against it.** The assistant's role is to produce well-structured prose and
to execute mechanical tasks correctly. The architectural decisions are yours.

### 9.2 Required reading at session start

Every AI session must start with the assistant reading:
1. The comb (authoritative decisions)
2. The refamiliarize document (current state)
3. The working notes (process rules)
4. The specific file being worked on

This is not optional. An assistant that has not read the comb will produce text
that contradicts it. An assistant that has not read the refamiliarize document
will not know what has already been decided.

### 9.3 Watch for these patterns

- **"Let me harmonize X across all chapters."** Say no. Decompose into per-chapter
  sessions.
- **Retired terms reappearing.** The assistant's training data contains many
  examples of the concept you retired. It will drift toward the common usage.
  Watch the retired terms list.
- **Resolving open items as a side effect.** If the assistant starts making
  normative decisions that belong in the comb while editing a chapter, stop it.
  Open a design-decision session.
- **Confident wrongness.** The assistant's confidence level is not correlated
  with correctness on project-specific decisions. When something sounds surprising,
  check it against the comb.

### 9.4 Let the assistant do what it does well

Assistants are excellent at:
- Producing well-structured prose from bullet points
- Mechanical search-and-replace across a file
- Checking a file for specific patterns
- Regenerating derived artifacts (adoc from markdown, etc.)
- Tracking what has and has not been done in a structured list
- Propagation checks (searching for all references to a changed thing)

Use them heavily for these. Reserve your attention for the architectural decisions,
which are yours.

---

## Part 10 — The pre-publication checklist

Before any external distribution (sharing with reviewers, submitting to a
standards body, publishing):

- [ ] Comb is current (version, changelog, all open items either resolved or
      explicitly deferred with rationale).
- [ ] All chapters align with the current comb version.
- [ ] Refamiliarize document reflects current state.
- [ ] No internal scaffolding in publishable files (PUB sweep complete).
- [ ] SPDX headers on all files.
- [ ] Generated artifacts (PDF, HTML) build cleanly from sources.
- [ ] Git history is clean; no uncommitted changes.
- [ ] Repository pushed to remote.
- [ ] All open items are either resolved or explicitly scoped as "deferred to
      a future version" with a brief rationale.

---

## Summary — the rules in order of importance

1. **The comb wins.** One authoritative source of truth, versioned, with
   changelog. Everything else is derivative.
2. **One unit of work per session.** Commit between each. Never batch.
3. **Never sweep.** Plan a sweep; execute it one unit at a time.
4. **Required reading at every session start.** Comb, refamiliarize, working notes.
5. **Propagation check before every commit.** Search for downstream references.
6. **Design decisions go in the comb first.** Then propagate to chapters.
7. **Retired terms stay retired.** Maintain the list; watch for reappearance.
8. **Strip internal scaffolding before publication.** Tracking tags, internal
   citations, and authoring notes are not content.
9. **Git after every session.** Local repo does not survive hardware failure.
10. **The assistant is confident even when wrong.** Check novel claims against
    the comb.

---

*This document was written based on the experience of the CE Suite RISC-V
specification project (2024–2026), co-authored with Claude (Anthropic). The
lessons here were learned the hard way — through a hiatus caused by exactly the
drift patterns described above — and then validated by successfully completing
a 20-chapter specification without repeating them.*
