
CME INSTRUCTION REFERENCE CARD
Legend for Types:
rd: Destination register

rs1, rs2: Source registers

imm: Immediate field (used for masks, addresses, etc.)

mask: Register or imm, selects register groups (GPR/FPR/VEC/PC/CSR/etc.)

All group/bank IDs are assumed 6 bits (for 64 max), can be extended.

1. CONTEXT BANK OPERATIONS
ec.ib
Store (save) current execution context into a context bank (partial or full)

Type: System, privileged/user (configurable)

Encoding: ec.ib rd, rs1 (bank_id in rd, mask in rs1)

Side effects: Overwrites bank; updates cme_status, cme_next_free if new alloc

Guaranteed cycles: 1 (banked), ≤3 (if features disabled by mask)

DMA fallback: n/a

Affected CSRs: cme_status, cme_last_bank, cme_reg_mask

ec.ob
Restore context from a context bank into the CPU (partial or full)

Type: System, privileged/user

Encoding: ec.ob rd, rs1 (bank_id in rd, mask in rs1)

Side effects: Overwrites live registers, may jump if PC bit set

Guaranteed cycles: 1 (banked), ≤3

DMA fallback: n/a

Affected CSRs: cme_status, cme_last_bank, cme_reg_mask

2. DMA (MEMORY) SPILL/FILL
ec.im
Spill (save) bank to memory (DMA, for migration, swap, suspend)

Type: System, privileged only

Encoding: ec.im rs1, rs2, imm (bank_id, mem_ptr, mask)

Side effects: Bank→memory write; triggers migration; bank may be freed

Guaranteed cycles: Variable; ≤(ctx_size / DMA_width) + setup (max set by implementation, e.g., 128 cycles)

DMA fallback: Required if no bank space

Affected CSRs: cme_status, cme_dma_addr, cme_reg_mask

ec.om
Fetch (load) context from memory into bank (DMA, for migration, resume)

Type: System, privileged only

Encoding: ec.om rd, rs1, imm (bank_id, mem_ptr, mask)

Side effects: memory→bank read; raises fault if no bank free

Guaranteed cycles: Variable; ≤(ctx_size / DMA_width) + setup

DMA fallback: Required for migration

Affected CSRs: cme_status, cme_dma_addr, cme_reg_mask

3. GROUP MANAGEMENT
ec.ig
Create a bank group (for delegation)

Type: Privileged only

Encoding: ec.ig rd (returns group_id in rd)

Side effects: Allocates new group, sets up group table, updates CSRs

Guaranteed cycles: 1–2

Affected CSRs: cme_group_map, cme_status

ec.og
Disband a bank group (returns banks to parent group)

Type: Privileged only

Encoding: ec.og rs1 (group_id in rs1)

Side effects: Pops group from banks, releases group table, notifies child VMs

Guaranteed cycles: (Banks_in_group / CAM_width) (O(1) with wide CAM)

Affected CSRs: cme_group_map, cme_status

ec.it
Assign (delegate) group to tenant (process/VM)

Type: Privileged only

Encoding: ec.it rs1, rs2 (group_id in rs1, tenant_id in rs2)

Side effects: Updates group mapping, sets group ID in tenant CSRs

Guaranteed cycles: 2–3

Affected CSRs: cme_group_map, cme_status

ec.ot
Revoke group from tenant

Type: Privileged only

Encoding: ec.ot rs1 (group_id in rs1)

Side effects: Triggers forced revoke if in use, pops stack, notifies all affected

Guaranteed cycles: (Banks_in_group / CAM_width)

Affected CSRs: cme_group_map, cme_status

4. SECURE ENCLAVE/VAULT OPS
ec.iv
Seal context into secure vault

Type: Privileged only

Encoding: ec.iv rs1, rs2 (bank_id, mask)

Side effects: Bank data is sealed, encrypted, write-protected

Guaranteed cycles: Device dependent; ≤16 (if AES in hardware)

Affected CSRs: cme_status, cme_seal_key

ec.ov
Unseal context from secure vault

Type: Privileged only

Encoding: ec.ov rd, rs1 (bank_id in rd, mask in rs1)

Side effects: Unseals bank, restores context, access checks

Guaranteed cycles: Device dependent; ≤16

Affected CSRs: cme_status, cme_seal_key

5. REGISTER MASK FIELD
Present in almost all instructions (as mask or immediate).

Bits:

Bit	Reg Group	Meaning
0	GPR	Integer registers
1	FPR	Floating point
2	VEC	Vector (RVV)
3	MAT	Matrix/Tensor (future)
4	PC	Program Counter
5	CSR	Critical CSRs
6–7	Reserved	

If PC bit set for restore:

Loads PC and atomically jumps to it.

6. CSRs
CSR Name	Purpose	Notes
cme_bank_count	Number of banks in system	Read-only
cme_next_free	Next available bank (alloc)	Read-only
cme_status	Last op status/error codes	Set/cleared by CME instructions
cme_reg_mask	Last mask value used	For debugging/tracing
cme_group_map	Bank/group mapping table	R/W
cme_dma_addr	DMA memory pointer	R/W
cme_seal_key	Key for sealing/unsealing banks	R/W, secure privilege

7. Programmer Notes / Side Effects
Exception on illegal access: All CME ops check group/bank privilege; trap if access denied.

All migration (DMA) ops may block or raise exception if memory bus is busy.

Group revoke triggers exceptions/interrupts to affected harts (bank revoke protocol).

Seal/unseal: May take multiple cycles (crypto), are privileged, and may fault if hardware is locked down.

8. Max Cycle Table (Per Instruction Class, Approximate)
Instruction	Normal Path (Banked)	DMA Path (Mem)	Secure Path
ec.ib/ob	1–3	n/a	n/a
ec.im/om	n/a	10–128*	n/a
ec.ig/og	1–4	n/a	n/a
ec.iv/ov	n/a	n/a	8–16

* Depends on register file size and bus width (e.g., 4K context / 32B DMA = 128 cycles worst-case)

9. Instruction Bitfield Encoding (Sketch)
Opcode: 8 bits (e.g., 1101_zzzz)

Major function: 4 bits (cat/dir/type)

Bank/group fields: 6 bits each

Mask: 8 bits (or immediate)

Address (DMA): 32–64 bits

Tenant/VM ID: 12–16 bits (as needed)

Example (pseudo-binary):
[opcode][func][rd][rs1][rs2][imm/mask][...address...]


