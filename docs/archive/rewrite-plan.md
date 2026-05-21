# CE Suite Rewrite Plan: Integrating ECID and Radix Tree Model

---

## Purpose

This plan details which chapters or sections require edits, what new content to add, and high-level integration steps to ensure your CE suite documentation is up-to-date with the ECID/radix tree model and all design resolutions.

---

### Chapters/Sections To Update and Why

---

### 1. Chapter 1: Execution Context Model

* **Expand:**

  * Formal ECID definition, role as the root identity for all CE resource contracts.
  * ECID lifecycle (creation, reuse, migration, forced destruction).
  * Only privileged actors (kernel/hypervisor/firmware) may create ECIDs.
  * ECID tree/prefix/radix model, and how it enables parent-child delegation, forced revocation, and resource isolation.
  * Add distinction between unresourced and resourced ECIDs.

---

### 2. Chapter 2: CME Instruction Set Reference

* **Update:**

  * Add `ec.od` ("execution context: destroy") or equivalent, for unconditional forced-revocation/resource cleanup.
  * Update descriptions of `ec.ib`/`ec.ob`/`ec.im`/`ec.om` to clarify ECID interactions.
  * Explicitly state ECID does not migrate between harts; always re-bound.

---

### 3. Chapter 3: Bank Group and Delegation Semantics

* **Edit/clarify:**

  * Tie group/bank delegation directly to ECID tree/radix model.
  * Forced revocation semantics—describe how tree walk allows reclamation of all child resources.
  * ECID prefix ownership as the key enforcement mechanism.

---

### 4. Chapter 4: Hardware Microarchitecture Overview

* **Add:**

  * Describe SRAM vs. RAM residency: only active ECID/contract in fast path.
  * ECID contract resolution path (lookup via radix tree).
  * Hardware never pre-allocates ECID storage; relies on RAM-resident structures.
  * Quota enforcement per prefix for resourced ECIDs.

---

### 5. Chapter 5: Kernel/OS Integration

* **Major update:**

  * Kernel’s role as ECID allocator, radix tree maintainer, and contract/quota enforcer.
  * ECID allocation and freeing algorithms, forced revocation, and generation counters for ABA safety.
  * Handling migration/rebinding across harts, not true ECID migration.
  * User-visible and API effects of new model.

---

### 6. Security and Privilege Model Section

* **Add or expand:**

  * Enforcement: Only kernel/hypervisor/secure firmware can create ECIDs.
  * Guest/user code cannot access, forge, or escalate ECIDs beyond their prefix.
  * ECID-based resource isolation—radix tree as enforcement backbone.

---

### 7. Appendix: ECID Data Structures & Algorithms

* **Add:**

  * Detailed ECID radix tree data structure (C or pseudocode).
  * Allocation, delegation, forced destruction algorithms.
  * Generation counter and “one-hole” allocation notes.
  * Illustrative diagrams (prefix tree, resource cleanup flow).

---

## General Steps to Update the Specification

1. **Review** each chapter’s original text, identifying locations for the new/updated material above.
2. **Mark and replace** outdated explanations (e.g., fixed ECID slot arrays, limited prefix schemes).
3. **Integrate** ECID and radix tree concepts at both architectural and operational levels.
4. **Ensure** every section referring to context banks, group delegation, or resource contracts refers to ECIDs and the ownership/enforcement model.
5. **Highlight** privilege boundaries and OS/hypervisor responsibilities wherever ECIDs are created, delegated, or destroyed.
6. **Add diagrams or placeholders** for ECID prefix tree, contract lookup, and forced-revocation flows.
7. **Document all new instructions** and contract resolution flows in both the reference and kernel integration chapters.
8. **Update the security analysis** to reflect the improved isolation and robustness enabled by the ECID/radix tree system.

---

## Completion Checklist

* [ ] Chapter 1: ECID, parent-child tree, privilege, lifecycle
* [ ] Chapter 2: CME instruction updates (`ec.od`), ECID interaction
* [ ] Chapter 3: Delegation/revocation, prefix enforcement
* [ ] Chapter 4: Microarchitecture/lookup path/quota
* [ ] Chapter 5: Kernel/OS integration, API changes, quota, migration
* [ ] Security section: ECID privilege, enforcement
* [ ] Appendix: Full radix tree structure & algorithms

---

**Keep this rewrite plan separate from main chapters and the scratchpad. Update it as you proceed.**

