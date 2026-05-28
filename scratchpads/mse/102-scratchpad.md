<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Context Extensions: Recent Refinements and Real-Time Scheduling Discussion

### Key Additions and Insights Since Last Revision

---

## 1. BE/Contract Slot Alternation for Predictable Latency and Interrupts

* **Time is divided into alternating slots:**

  * **Contract slots:** reserved for hard real-time contracts (enforcing bandwidth and latency guarantees).
  * **Best-Effort (BE) slots:** can be freely preempted by interrupts or used for opportunistic/background tasks.
  * **50% of slots are always BE** (e.g., even slots: contract; odd slots: BE).

* **Purpose:**

  * Allows interrupts to take over with zero or minimal latency (at most one slot) by always having a BE slot immediately available.
  * Guarantees that contract holders never lose their guaranteed share—even under heavy interrupt load—since their slots cannot be preempted except under tightly controlled and bounded conditions.

* **Implementation:**

  * Simple slot counter or toggle (odd/even) is used for alternation; minimal hardware complexity.
  * The OS/firmware ensures that nested interrupts are routed to a different hart/core to avoid starvation or livelock.

---

## 2. Impact on CME’s 1-Cycle Latency

* **CME guarantees** a 1-cycle context switch at the CPU (register file swap), but when BE/contract slotting is applied to RAM or shared resources:

  * **RAM access latency for an interrupt is now quantized to slot size** (typically the minimum DRAM or interconnect access period).
  * **Best-case interrupt memory access:** immediate if a BE slot;
    **Worst-case:** must wait one contract slot, so up to one slot’s additional latency.
* **This does not affect the 1-cycle context switch for core-local operations or cache accesses** (see below).

---

## 3. Cache Partitioning Restores True 1-Cycle Latency

* **If cache is partitioned per contract/hart,** all L1/L2 accesses for a real-time context are guaranteed 1-cycle, **regardless of slot schedule for RAM**.
* **Combining CME/MSE with cache partitioning (CPE):**

  * Critical real-time and interrupt code/data fit in the cache partition →

    * **1-cycle context switch**
    * **1-cycle cache access**
    * **End-to-end true low-latency response for cached workloads**
* **RAM slotting then only sets the upper bound for uncached or shared memory accesses.**

---

## 4. Mathematical/Algorithmic Consequences

* **BE/contract slotting:** Maximum guaranteed contract bandwidth = 50% (or another chosen fraction), but all contracts and interrupts get hard upper bounds on latency and share.
* **Deficit/catch-up logic:** Any deviation from schedule (e.g., due to interrupts) is compensated immediately after, so contracts always get their minimum share over the scheduling window.
* **Scheduling and arbitration remain simple:** Minimal logic (counters, toggles, small accumulators).

---

## 5. Real-Time System Implications

* **Determinism and predictability:** Interrupts and hard contracts each get guaranteed time slices, with upper and lower bounds tightly controlled.
* **Resource utilization trade-off:** System is intentionally underutilized (up to 50% of bandwidth set aside for BE/interrupts) to maximize predictability—standard practice in hard-real-time systems.
* **Extension to OS/firmware:**

  * OS should route interrupts interrupting interrupts to a new hart/core if possible to avoid priority inversion or starvation.

---

### Summary Table

| Resource         | Partitioning Used | Latency (interrupt/RT) | Guarantee                            |
| ---------------- | ----------------- | ---------------------- | ------------------------------------ |
| CPU              | CME               | 1 cycle                | Always                               |
| Cache (L1/L2)    | Per-contract      | 1 cycle                | If code/data fits in partition       |
| RAM              | BE/contract slot  | 1 slot (min)           | Deterministic, max = slot size       |
| BE slot fraction | 50% (example)     | Immediate preempt      | Allows zero-latency interrupt access |

---

# Interrupt Nesting and Contract Latency Guarantees

### Interrupt Nesting in Linux and Implications for Resource Partitioning

---

## 1. Interrupt Nesting Reality in Linux and Modern CPUs

* **Most modern CPUs** (x86, ARM, RISC-V) support prioritized hardware interrupts.

  * Non-maskable interrupts (NMI) can preempt any other handler, including other interrupts.
  * Standard hardware IRQs typically do not nest, but high-priority events (NMI, watchdog) can always preempt.

* **Linux kernel default:**

  * When servicing a standard interrupt, Linux disables further interrupts on that hart/core by default, so only NMIs can preempt IRQs.
  * "SoftIRQs" and deferred handlers (tasklets) do not count as hardware nesting.
  * **Net result: typical nesting depth in Linux is 2** (IRQ + NMI).

* **Preempt-RT/RTOS kernels:**

  * May permit limited additional nesting for preemptible IRQs, but in practice, D=2..4 is rare and deeper nesting is discouraged.

---

## 2. Scheduler Design for Guaranteed Contract Latency

* **Interrupt Block Splitting and Shifting (for D ≥ 1):**

  * When an interrupt (IN) occurs, it immediately splits the current block (BE or CN) and starts a full IN block at that instant.
  * After the interrupt handler completes, alternation resumes, but the phase may be shifted.
  * If further (nested) interrupts arrive (up to D total), each new interrupt immediately starts its own IN block at the next CN slot, creating a pattern of interleaved IN and CN blocks:

    * D=1: `IN | CN | IN | CN | ...`
    * D=2: `IN1 | CN | IN2 | CN | ...`
    * D=3: `IN1 | CN | IN2 | CN | IN3 | CN | ...`
    * D=4: `IN1 | CN | IN2 | CN | IN3 | CN | IN4 | CN | ...`
  * When all interrupts complete, the next BE slot is shortened or skipped as needed to realign the phase and restore the original alternation.
  * **At all times, time remains quantized to block boundaries from the MMU’s point of view—no subtle drift occurs.**
  * **No CN slot is ever skipped; only delayed and phase-shifted during bursts of interrupts, but the alternation pattern is always restored after.**

* **Guarantees and Bandwidth:**

  * The maximum number of consecutive interrupt blocks (D) directly sets the maximum possible delay for a contract slot (CN).
  * **Maximum guaranteed latency for a CN slot:** $(D+1) 	imes$ block time.
  * **Hard contract bandwidth remains at 50%, regardless of D.**

* **Example Patterns:**

  * D=1: `IN | CN | IN | CN | ...`
  * D=2: `IN1 | CN | IN2 | CN | ...`
  * D=3: `IN1 | CN | IN2 | CN | IN3 | CN | ...`
  * D=4: `IN1 | CN | IN2 | CN | IN3 | CN | IN4 | CN | ...`

* **Configuration:**

  * Hardware may include a configuration register for maximum allowed nesting depth D, settable by the OS or bootloader.
  * Exceeding the configured D may void real-time contract guarantees.

---

### Updated Summary Table

| Max Interrupt Nesting (D) | Slot Pattern Example                    | Max CN Bandwidth | Max CN Latency |
| ------------------------- | --------------------------------------- | ---------------- | -------------- |
| 1                         | IN, CN, IN, CN, ...                     | 50%              | 2× block time  |
| 2                         | IN1, CN, IN2, CN, ...                   | 50%              | 3× block time  |
| 3                         | IN1, CN, IN2, CN, IN3, CN, ...          | 50%              | 4× block time  |
| 4                         | IN1, CN, IN2, CN, IN3, CN, IN4, CN, ... | 50%              | 5× block time  |

> **After all interrupts complete, the alternation resumes and any phase shift is corrected by adjusting the next BE slot. No drift can accumulate.**

---

| Max Interrupt Nesting (D) | Slot Pattern | Max CN Bandwidth | Max CN Latency |
| ------------------------- | ------------ | ---------------- | -------------- |
| 1                         | BE, CN, ...  | 50%              | 2× block time  |
| 2                         | BE, CN, ...  | 50%              | 3× block time  |
| 3                         | BE, CN, ...  | 50%              | 4× block time  |
| 4                         | BE, CN, ...  | 50%              | 5× block time  |

> **Note:** The slot pattern remains alternating. "Max CN Latency" is the maximum possible delay before a contract slot is serviced, under worst-case nesting.

---

```mmd
graph TD
    A[Start] --> B{Decision}
    B -- Yes --> C[Option 1]
    B -- No --> D[Option 2]
    C --> E[End]
    D --> E
```


**Next: Add scheduler state diagrams and discuss multi-hart interrupt routing.**
