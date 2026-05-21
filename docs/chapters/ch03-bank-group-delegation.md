# Chapter 3: Bank Group and Delegation Semantics

## Overview

This chapter specifies the semantics and rules for context bank grouping, group creation, hierarchical delegation, and enforcement in the Context Management Extension (CME). It covers:

* Group creation and bank assignment
* Bank-to-group and group-to-parent relationships
* Delegation and revocation to tenants (VMs, secure enclaves, interrupt handlers)
* Hardware visibility and security model
* Edge cases and rigidity by design

---

## 1. Bank Groups and Ownership Model

* **Bank groups** are the units of delegation.
  Each group is identified by a *group ID* (6 bits per context hierarchy).
* **Banks** themselves remember which group they belong to (hardware field), not vice versa.
* A group also stores the *parent group ID* (hidden from guests).
* **Only banks in EC-local group 0** (the root group as seen by a given execution context) can be added to new groups.
* The *first bank* in an EC (EC-local bank 0) is always retained in group 0 and cannot be moved.

---

## 2. Group Creation and Bank Addition/Removal

* `ec.ig` (Create or extend group):

  * `ec.ig rd, x0` creates a new group, moving the first free EC-local group 0 bank to it, and returns the new group ID in `rd`.
  * `ec.ig rd, <existing group ID>` moves the next free EC-local group 0 bank to the group.
  * **Cannot add banks to tenant-owned groups.**

* `ec.og` (Remove bank from group):

  * `ec.og rd, <group ID>` removes the *last-added* EC-local bank from the group and returns it to group 0. Returns number of banks left in `rd`; if zero, group is now dissolved.
  * **Cannot remove banks from tenant-owned groups unless forcibly revoked.**

* **A group is always non-empty; removing the last bank automatically dissolves it and updates the group mapping tree.**

* OS must track which EC-local bank numbers are in which groups. Hardware tracks only bank→group mapping.

---

## 3. Delegation and Revocation

* `ec.it` (Assign group to tenant/child ECID):

  * Transfers a group (and all its banks/subgroups) to a child context (VM, enclave, etc.)
  * After delegation, the guest sees the group as group 0, and the banks as 0..K-1.
  * Host EC loses direct access to the delegated group and cannot add/remove banks.

* `ec.ot` (Revoke group):

  * Recursively revokes group from tenant and returns all banks/subgroups to the parent group (or dissolves if emptied).
  * Can be used for normal shutdown or forced eviction.

* **Delegation and revocation are hardware-enforced.**

* Guests cannot see real group or bank IDs, or their place in the host’s group tree.

---

## 4. Group and Bank Visibility Rules

* **From the guest’s perspective:**

  * Only sees its own group (group 0) and its banks (numbered 0..K-1).
  * No knowledge of parent, sibling, or other host groups.
  * Cannot infer group hierarchy or hardware mappings.
* **From the hardware/host perspective:**

  * Each bank is tagged with its true group ID.
  * Each group records its parent (used for recursive revocation).
  * Groups and banks are mapped in secure hardware tables; software cannot override or forge membership.

---

## 5. Security, Exceptions, and Rigidity

* All group and bank membership changes are hardware-privileged.
* All attempts to access, delegate, or modify groups/banks outside one’s delegated set are trapped.
* Guests cannot read or alter host-level mapping tables (such as `cme_group_map`).
* **Rigidity is by design:**

  * Delegation is not fluid; reclaiming resources always succeeds (no lockups or races).
  * VM migration or group movement requires explicit teardown and rebuild.
  * Groups must be empty before being reused.

---

## 6. Example Use Cases

* OS creates a new group for a secure enclave by moving a free bank from group 0, delegates it.
* Enclave sees its banks as 0..3 (if given four banks) and group as 0; host sees the real group ID.
* On enclave shutdown, `ec.ot` is used to revoke the group, returning all banks to the parent (host EC).
* Bank/group mapping is strictly enforced; tenants can never “see” or “grab” banks/groups beyond what’s delegated.

---

## Placeholder: Diagram – Group Tree and Bank Mapping

*Description*: Tree diagram showing nested groups, bank-to-group assignments, delegation to tenants, and the hardware translation logic between guest-visible and physical IDs.

---

[Next: Hardware Microarchitecture Overview](../hardware-microarchitecture-overview.md)

