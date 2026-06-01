# START HERE — The Plan-and-Build Methodology Kit

A reusable, tool-agnostic method for using an AI assistant to change a codebase or
specification **safely and auditably** — every decision human, every change small and
reviewed, the AI's own output held to adversarial scrutiny. It is distilled from the
methodology that settled the CE Suite logical core.

## What's in the kit

| File | What it is | When to use it |
|---|---|---|
| `START-HERE.md` | This overview. | First. |
| `initiator-prompt.md` | The standing instructions you install in a new project so an AI assistant follows the method. The centerpiece. | Once, when setting up a project. |
| `methodology.md` | The authority on *how* the method works — roles, workflow, rules, guard-rails. The assistant reads this. | Referenced every session. |
| `change-prompt-template.md` | The template for the document the **planner** writes for the **builder**. | Every plan-and-build. |
| `session-report-template.md` | The template for what the **builder** returns. | Every plan-and-build. |
| `design-loop-protocol.md` | The optional convergence protocol for settling a fragile design "core" before building on it (exit criteria + two-angle red-team + freeze). | Projects with a fragile core to settle first. |

## The roles (tool-agnostic)

- **Architect** — the human. Makes every decision. (Maps to "architect" in CE.)
- **Planner** — an AI in a chat interface. Discusses, drafts, prepares change-prompts.
  Cannot touch the repository. (Maps to "web-Claude.")
- **Builder** — an AI agentic coding tool. Executes exactly one file's change per
  session, then commits. Makes no design judgments. (Maps to "code-Claude.")

Any chat assistant can be the planner; any agentic coding tool can be the builder.
The method does not depend on which.

## The shortest possible description

1. Settle fragile design questions in a **lab** document, separate from the
   authoritative artifacts (**the canon**). Port results into the canon only as
   deliberate decisions. (*The firewall.*)
2. To make any change: the **planner** writes a **change-prompt** (scoped to one
   file, with a mandatory side-effect check); the **architect** reviews it; the
   **builder** executes that one file and commits; the **architect** reviews the
   result. (*Plan-and-build.*)
3. A big change becomes **many** small plan-and-builds, never one sweep. (*Build-loop.*)
4. The AI **verifies against the repository** rather than trusting its memory, and
   flags anything unverified.
5. For a fragile core, **converge then freeze**: settle it, then survive a red-team
   review twice in a row from different angles before building on it.

## How to set up a new project

1. Fill in the placeholders in `initiator-prompt.md` (project name, repository URL,
   which files are the canon, where the lab lives) and install it as the project's
   standing instructions (project knowledge, a system prompt, or a `CLAUDE.md`-style
   file the assistant reads first).
2. Put `methodology.md`, `change-prompt-template.md`, and `session-report-template.md`
   in the repository where both the planner and builder can read them.
3. If the project has a fragile core to settle, add `design-loop-protocol.md` too.
4. Work in plan-and-builds. Use the build-loop for anything that touches many files.

The rest of the kit is the detail.
