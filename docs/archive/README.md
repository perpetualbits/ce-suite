# Archive

This folder holds **superseded** and **historical** documents from the
CE Suite project. Nothing in here is current. Nothing in here is normative.

**Do not edit these files.** Do not cite them as authoritative. They exist
for two reasons only:

1. **Provenance.** When reviewers ask "did you consider X?" or "where did
   decision Y come from?", these documents are the audit trail.
2. **Salvage.** Occasionally a discarded draft contains a useful phrasing
   or argument that should be lifted into a current document. When that
   happens, copy the relevant text into the right place; do not move the
   file out of archive.

## What's here

| File | What it was | Why superseded |
|---|---|---|
| `chapter0-half-correct.md` | Chapter 0 v0.4 | Had Pools layer (now retired); Group/Bank axioms restructured in v0.5+ |
| `chapter0-also-half-correct.md` | Chapter 0 v0.5 | Transitional draft; superseded by the current Chapter 0 |
| `chapter4-original.md` | Chapter 4 pre-revision | Predates the S/R staging-bank and copy-engine model |
| `ce-tree-of-truths.md` | Early "axiom tree" sketch | Predates the charter; the charter is the current axiom statement |
| `ucs.md` | Exploration of Unified Context Structure | Currently noted as open item §8.6 of the charter; may be promoted to optional appendix later |
| `rewrite-plan.md` | The pre-hiatus rewrite plan | Superseded by charter §7.3 (chapter-by-chapter alignment) |
| `working_with_chatgpt.md` | Lessons learned about LLM workflow | Folded into `docs/working_notes_for_authors.md` |
| `google-ai-whitepaper.md` | External summary of CE | Useful framing but overclaims; do not cite as authoritative |
| `fpga-board-spec.md` | The PA200T-StarLite Artix-7 board spec | Reference for future `hw/board/` work; not part of the spec proper |

## When you find drift

If a current document somewhere uses terminology from an archived
document (e.g., "Pool" instead of "Contract"), the **current document
is wrong**, not the archive. Update the current document.
