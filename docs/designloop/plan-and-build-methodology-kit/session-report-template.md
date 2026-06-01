# Session-Report Template

*The builder returns this at the end of a plan-and-build, after committing and pushing.
Use role names — no "I/you/me". Delete the italic guidance before use.*

---

# Session-report — {{TITLE OF THE CHANGE}}

**Change-prompt:** {{which change-prompt this executed}}
**File edited:** `{{PATH/TO/FILE}}` (exactly one)

## What changed
{{The new or changed content as written — exact lines or a precise summary. If a
planning-stage decision was settled, state the choice made and why.}}

## Planning-stage decisions, as resolved
{{For each decision the change-prompt flagged: the option chosen and the reason. If
none, "none."}}

## Side-effect (propagation) check
{{Either (a) the specific files and lines needing follow-up, classified, or (b) an
explicit confirmation that nothing else is affected. Be exhaustive: enumerate the
references checked and their disposition. If the change-prompt named an expected
follow-up surface, report against each item.}}

## Verification
{{Any internal-consistency checks run and their results — e.g., the changed thing now
agrees with the documents it must agree with; no stale reference to the old state
remains.}}

## Anything unexpected
{{Discrepancies found, claims that could not be verified, or anything the architect
should know before relying on this. If the repository state differed from what the
change-prompt assumed, say so. If nothing, "none."}}

## Commit
- **Message:** {{commit message}}
- **Hash:** {{commit hash}}
- **Pushed:** {{confirm `git push` followed `git commit` in the same turn}}
