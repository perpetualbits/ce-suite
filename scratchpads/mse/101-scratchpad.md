<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# 101-MSE-scratchpad.md

This file is the working scratchpad for the Memory Scheduling Extension (MSE) as part of the CE suite project.

**Only this file will be edited in this chat.**

---

### MSE Contract/Group Axioms

1. **Contract→Group Mapping:**
   Every contract must point to a group (its owner).

2. **Group→Parent Group Mapping:**
   Every group (except group zero) points to a parent group.

   * This creates a tree (or forest) of groups, rooted at group zero.

3. **Zero Group:**
   Group zero always points to itself.

   * This serves as the universal root and as a sentinel for emptiness.

4. **Empty Groups:**
   Any group (except zero) that points to itself is considered empty and is eligible for garbage collection or hardware reuse.

5. **Contract Allocation:**
   A new group can only be created if there is at least one contract to assign to it (no “empty” groups except as above).

6. **Non-Delegation of Self:**
   You cannot give away your own contract (cannot assign all contracts away; must always retain at least one in a group if it remains non-empty).

7. **Limited Hardware Contracts:**
   There is a finite number of hardware contracts (equal to the number of hardware-enforced slots/groups supported by MSE logic).

8. **Software Contracts:**
   Groups or contracts that exist only in software (not enforced in hardware) are allowed, but the hardware only enforces those it has slots for; overflow or lower-priority groups are managed in software and can be swapped in as needed.

9. **Reversal Trick:**
   In hardware, the contracts contain some bits point to their parent group, not the other way around. Each in each group is “reversed”: rather than contracts pointing down a tree, groups point to their owner, allowing efficient reclamation and delegation with minimal hardware state.

10. **Group Deletion:**
    When a group becomes empty (all contracts removed/delegated), it is dissolved, and its parent pointer is set to itself.

11. **Unique Ownership:**
    No contract may be owned by more than one group at a time.

12. **Delegation Constraint:**
    Only a group’s owner (the parent group) can reassign or delegate contracts to child groups.\\

    Put notes here:
    \- NOTE1

---

## Section 1: What We Know for Sure

* **Per-hart State:**
  RISC-V architectural state and instructions are strictly per-hart. No instruction (including any proposed MSE instruction) may directly alter the state of another hart.

* **Resource Contention:**
  Memory access in all modern architectures (UMA, NUMA, hypercube, etc.) is inherently contended between harts/CPUs. Arbitration for RAM (and even L2/L3 cache) is always necessary at some level.

* **Global Arbitration Needs OS/Hypervisor:**
  Only the OS or hypervisor can have the “big picture” of execution contexts, their priorities, and resource requirements. Any memory scheduling or arbitration for latency/bandwidth *across harts* must be OS-directed, not initiated by individual ECs.

* **Cache Partitioning (CPE) is Valid:**
  Hardware-enforced cache partitioning is a proven and valuable technique (Intel CAT, ARM, etc.), and should be included in the CE suite as CPE. Its purpose is to guarantee cache residency and predictable access latency for critical contexts.

* **Bandwidth and Latency Tradeoff:**
  There is an inherent (though not perfectly linear) tradeoff between maximizing bandwidth for some ECs and minimizing latency for others. This is a core challenge for any MSE/MBW logic.

* **Per-EC Resource Profile:**
  The central “policy knob” is a per-EC resource profile (as in the CE suite’s `execution_context` struct) that tells the hardware what policy to enforce for each context (priority, minimum bandwidth, latency requirement, etc.).

* **Separation of Concerns:**
  MSE should not attempt to provide fine-grained, cross-hart memory scheduling via the ISA; instead, it should expose enforcement primitives for the OS/hypervisor to set and for hardware to enforce.

* **Instruction Set Not Finalized:**
  No concrete MSE instructions or CSRs have been fully agreed upon yet. All actual encodings, names, and interfaces remain open.

---

## Section 2: Rejected Approaches and Ideas

* **Rejected:**
  *Directly altering state on another hart via MSE instructions.*
  **Rationale:** This violates RISC-V architectural isolation and breaks standard CPU design principles.

* **Rejected:**
  *Attempting to predict or control global memory bus arbitration using only per-hart hardware or speculative prefetch queues.*
  **Rationale:** Cross-hart resource management always requires higher-level coordination; hardware can only act on local information, not global policy.

* **Rejected:**
  *Assuming that partitioning or quota mechanisms always help.*
  **Rationale:** Static allocation/partitioning may waste resources or even reduce performance if workloads don’t match the allocation policy.

---

## Section 3: Open Questions and Exploration

---

### Scenario 1: Multi-Threaded Real-Time SoC With Competing Deadlines

**Context:**
A high-end industrial controller SoC is running:

* A four hart CPU. On each of these harts we run the following
* Three real-time audio DSP threads, each processing audio at 96kHz (one thread per channel, e.g., L, R, sub). These have narrower latency requirements than the video frames

- Two real-time video input processes, handling two 4K camera feeds, each with strict per-frame deadlines (e.g., <12ms per frame).
- Six non-realtime Linux user processes: database logger, web server, monitoring UI, ML inference, etc.—all best-effort, should run as smoothly as possible, but must never cause deadline misses for the real-time threads.

**Key questions/issues to surface:**

* How does the OS communicate to hardware that audio/video threads require both high bandwidth *and* extremely low and consistent latency? How are their needs described (rate, burst, max latency tolerated, etc.)?
* What if two real-time deadlines overlap or both need a burst of RAM? Can the hardware *guarantee* both, or must the OS/RT scheduler ensure their critical windows never coincide?
* If the non-realtime workloads start paging or doing heavy IO, how is their memory access throttled (and how fast can this be enforced in hardware)?
* What feedback (if any) does hardware give to the OS about current utilization, violations, or near-miss deadline events?

---

### Scenario 2: Multi-level Virtualization With CEPH and Mixed QoS

**Context:**
A cloud node (L0) is running:

* The CEPH distributed object storage backend, accelerated with RVV1.0 vector ops (for erasure-coded pool computation) and serving IO over a >=100GbE NIC.
* Several VMs (at L1):

  * Some for premium tenants running latency-critical analytics and DB workloads (guaranteed throughput, cache residency, and tail latency).
  * Some for general batch jobs and web services.
  * Some running guest VMs themselves (nested virtualization, L2) for further multi-tenancy.
* CEPH’s erasure coding tasks are high-bandwidth and bursty, can fill RAM and vector units, but the system must still meet SLA for premium VMs.

**Key questions/issues to surface:**

* When CEPH launches a big erasure coding job (maybe even spanning NUMA nodes), how do the L0 OS and MSE enforce “do not starve premium tenants,” even if CEPH is allowed to use “all else unused” bandwidth?
* How do cache partitioning (CPE), memory scheduling (MSE), and QoS interact when one L2 guest tries to over-consume memory or cache—does the L1 hypervisor get a chance to intervene? How is resource delegation/isolation maintained over multiple virt levels?
* Can MSE enforce minimum bandwidth *and* maximum latency for premium VMs without causing resource underutilization (i.e., can “leftover” bandwidth be given to CEPH without violating guarantees)?

---

### Scenario 3: Satellite With Hard Realtime and Data Analytics

**Context:**
A scientific satellite SoC with:

* Multiple RISC-V harts (with OOO, speculative, vector, etc.)
* Must maintain continuous laser link with peer satellites (for gravitational wave detection) via real-time beam steering and signal processing, with hard <1ms latency for feedback loops.
* Simultaneously, must perform big data analytics and batch jobs on the science data, and opportunistically downlink bulk results to Earth when in view.

**Key questions/issues to surface:**

* Can the hardware strictly enforce a worst-case memory access latency for the real-time laser/comm subsystem, given all the modern CPU unpredictabilities (prefetch, OOO, cache evictions, DRAM refresh, etc.)?
* If the science data jobs suddenly spike (e.g., due to interesting event in the data), can they be throttled quickly enough to avoid causing a missed control deadline?
* What telemetry or feedback does hardware provide if the memory scheduler cannot meet the promised deadlines (e.g., due to unexpected contention, cosmic-ray-induced errors, or hardware faults)?

---

* Scenario 1: Multi-Threaded Real-Time SoC With Competing Deadlines

**Context:**
High-end industrial controller SoC running:

* 3 real-time audio DSP threads (96kHz, one per channel)
* 2 real-time video input processes (4K feeds, strict per-frame deadlines)
* 6 non-realtime Linux processes (logger, web server, ML, etc.—best-effort, must not disturb RT threads)

**Key questions:**

* How does the OS specify bandwidth/latency needs for each RT thread/process to hardware?

* How does hardware arbitrate overlapping deadlines?

* How is best-effort/non-realtime activity throttled to guarantee RT deadlines?

* What feedback can hardware provide if a deadline is violated or nearly violated?
  SC1 END

### \$1---

### Cycle-by-Cycle Scheduling and Group Enforcement Example

**Setup:**

* 4 harts (Hart0, Hart1, Hart2, Hart3).
* Each hart runs an EC with these active resource profiles:

  * Hart0: RT, Latency=1, Bandwidth=3, Group=0
  * Hart1: RT, Latency=2, Bandwidth=3, Group=0
  * Hart2: RT, Latency=5, Bandwidth=6, Group=1
  * Hart3: BE, Latency=0, Bandwidth=0, Group=BE
* Best-effort pool: 4 cycles (25%)
* Group0 cap: 6 cycles per window
* Group1 cap: 6 cycles per window

**Cycle 0:**

* Hart0, Hart1, Hart2 request RAM.
* MMU looks at MSE class bits for all 4 harts (from per-hart registers).
* Hart0 (latency=1) wins.
* Grant: Hart0 gets 3 cycles.
* Bookkeeping:

  * Group0 total: 3
  * System RT total: 3

**Cycle 3:**

* Hart0 at cap (not requesting), Hart1 and Hart2 still need RAM.
* Hart1 (latency=2) wins.
* Grant: Hart1 gets 3 cycles.
* Group0 total: 6 (cap reached for this window).
* System RT total: 6

**Cycle 6:**

* Hart0 and Hart1 at cap; Hart2 is now highest-priority RT.
* Hart2 (group1) wins, gets 6 cycles.
* Group1 total: 6 (cap reached).
* System RT total: 12

**Cycles 12–15:**

* Only BE pool remains (4 cycles).
* Hart3 (BE) gets these cycles (split if other BE ECs are running).
* System RT total: capped at 12.

**Window End:**

* Running totals reset.
* OS may context-switch harts if deadlines require new ECs.

---

**Key Group System Points:**

* Each EC’s profile includes a group ID (set by OS).
* MMU tracks group caps and active group totals—O(groups) state, not O(M).
* At context switch, only the new EC’s profile is loaded; group and system totals incremented on grant.

**Result:**

* Per-cycle data movement is minimal: only local registers and counters updated.
* The group system is unified: the same group IDs can be used for CME, MSE, CPE, QOS.
* In nested virt, granularity can be reduced at delegation; guests cannot exceed host-set group caps.

---

**Scheduling Window Walk-Through (Example: 4 harts, 16-cycle window)**

1. **At the Start of the Window:**

   * OS ensures the *right* N ECs are running (by context switching as needed).
   * Each hart’s context bank contains:

     * GPRs, FPRs, PC, SATP, etc.
     * MSE resource profile: latency (4b), bandwidth (4b), group ID (if any), best-effort status (1b), other policy bits.

2. **On Context Switch:**

   * CME hardware (`ec.ob`) atomically loads all state into per-hart registers.
   * MMU now “sees”:

     * Hart 0: ECID = 41, latency = 0010, bandwidth = 0110, group = 0
     * Hart 1: ECID = 17, latency = 0100, bandwidth = 0011, group = 0
     * Hart 2: ECID = 76, latency = 1011, bandwidth = 1000, group = 1
     * Hart 3: ECID = 22, latency = 0000, bandwidth = 0000, group = best-effort

3. **Each Arbitration Cycle (e.g., per DRAM access or burst):**

   * MMU checks all 4 harts for “requesting” (wanting RAM).
   * Of those:

     * First, look at nonzero latency class (guaranteed RT ECs).
     * Winner: **lowest latency value**; ties → round-robin.
     * Grants that hart a burst of size given by its bandwidth class (e.g., 3 cycles for 0011).
   * After grant:

     * Update per-EC, per-group, and system counters.
     * If cap would be exceeded (e.g., group or system), deny further grants until window resets or OS rebalances.

4. **If No RT/Guaranteed ECs Request:**

   * Best-effort pool (the reserved portion, e.g., 4/16 cycles) is divided among BE ECs via round-robin.
   * Only N harts are ever considered.

5. **During the Window:**

   * If a deadline approaches or OS needs to “swap in” a different EC (for deadline or fairness):

     * OS does a context switch on the appropriate hart.
     * CME hardware swaps the context and loads the new EC’s resource profile.

6. **At the End of the Window:**

   * Per-EC, group, and system running totals reset.
   * OS may update which ECs are scheduled (next N), based on system state and upcoming deadlines.

---

**Where Does Information Live?**

| Info                    | Who Holds It                    | How Large?       | When Updated?           |
| ----------------------- | ------------------------------- | ---------------- | ----------------------- |
| All EC profiles         | OS (RAM, run queue, etc.)       | O(M)             | Context creation/update |
| Active EC profiles      | CME/hardware, per hart          | O(N)             | Context switch          |
| Per-group/system caps   | MMU/hardware registers/counters | O(groups) + O(1) | EC create/switch        |
| Arbitration logic state | MMU/hardware (combinatorial)    | O(N)             | Each arbitration cycle  |

---

**How Much Data Moves Where, and When?**

* **Context switch:** Resource profile (a few bytes) is loaded for the new EC. No other data moves unless ECID changes.
* **Per arbitration:** Only the N active harts' profile bits and counters are referenced (total O(N)).
* **No streaming or large data transfer of meta-data** per arbitration, only local registers.

---

**Is This Feasible?**

* **Yes:** All “big” bookkeeping is OS-side (O(M)), and only O(N) resource profile info is “active” in hardware at any one time.
* Hardware only moves a small, fixed amount of meta-data per context switch and arbitration cycle.
* This is not a metadata or state explosion and fits well with existing SoC/CPU practices.

---

* **Scenario 2: Multi-level Virtualization With CEPH and Mixed QoS**

**Context:**
Cloud node (L0) running:

* CEPH backend with RVV1.0 acceleration for erasure-coded pools, using >=100GbE NIC
* Several VMs (at L1):

  * Premium (guaranteed) analytics/DB workloads
  * Batch jobs/web
  * Nested VMs (L2)
* CEPH’s erasure coding is bursty, may fill RAM/vector units, but SLAs must be met for premium VMs

**Key questions:**

* How do L0 OS and MSE enforce "do not starve premium tenants" even when CEPH uses all unused bandwidth?

* How do CPE, MSE, QoS interact when L2 guest over-consumes? Does the L1 hypervisor get to intervene?

* Can MSE enforce both min bandwidth and max latency for premium VMs, while still allowing CEPH to opportunistically use leftover bandwidth?
  SC2 END

* **Scenario 3: Satellite With Hard Realtime and Data Analytics**

**Context:**
Scientific satellite SoC with:

* Multiple RISC-V harts (OOO, speculative, vector)
* Must maintain continuous laser link for gravitational wave detection (<1ms latency feedback)
* Simultaneously runs big data analytics and batch jobs, opportunistically downlinking to Earth

**Key questions:**

* Can hardware enforce worst-case memory access latency for laser/comm subsystem despite all modern CPU unpredictabilities?

* Can analytics jobs be throttled quickly enough to avoid missed deadlines?

* What telemetry or feedback does hardware provide if memory deadlines cannot be met?
  SC3 END

* **Open Questions:**

  * What information should the OS/hypervisor set in per-EC resource profiles, and how should these be exposed to hardware?
  * What kinds of instructions or CSRs are most natural for MSE, given the constraints above?
  * Where does memory scheduling logic live—in the MMU, in a central memory arbiter, or distributed across caches and memory controllers?
  * Are there useful per-hart hints or instructions (e.g., “I am about to need high bandwidth for N cycles” or “real-time, low-latency required now”) that can actually be enforced by hardware?
  * Are there any approaches to memory scheduling that must be specifically *excluded* due to architectural or security issues?
  * How does the presence of speculative prefetch, out-of-order issue, and variable DRAM/NUMA topology further complicate any possible hardware enforcement of latency/bandwidth policy?

---

### Abstract Frameworks: Fractal Time-Slice Memory Scheduling

**Idea:**
Model time as a continuous stream of memory access opportunities (RAM cycles or bursts). Each real-time process P(i) declares:

* A deadline: it must start its RAM access within X(i) cycles.
* A minimum holding time: it requires at least Y(i) cycles of RAM access before it can yield without failing.

By recursively subdividing time (merging intervals when no deadlines fall within), the memory controller can construct a dynamic, fractal time-slice schedule. This guarantees every admitted real-time process receives the bandwidth and latency it needs, while best-effort (non-RT) traffic can fill unused intervals.

**Strengths:**

* Directly expresses both deadline and minimum bandwidth requirements for multiple real-time ECs.
* Admits merging (for efficiency) and fine subdivision (for guarantees), analogous to TDMA in hard-real-time systems.
* Can be used as a reasoning framework, or (with constraints) as a practical scheduling model in hardware.

**Requirements:**

* **Precise time accounting:** The memory controller or MMU must track and enforce reservations at cycle or burst granularity.
* **Admission control:** New real-time requests must be checked against the current schedule; admission only if all deadlines can be honored.
* **Preemption/throttling:** Non-RT or best-effort accesses must yield in time for the next RT reservation.
* **Combinability:** Leftover time can be efficiently used by non-RT or opportunistic tasks.

**Potential and Precedents:**

* Static and semi-dynamic TDMA (used in aerospace, industrial, and automotive systems).
* Academic real-time DRAM controllers that reserve slots for hard-RT workloads.

**Feasibility Analysis:**

* **For a small N of RT processes:** Practical and even proven, if the scheduling window is static or changes infrequently.
* **For dynamic, general-purpose workloads:** The complexity (in hardware logic and rescheduling cost) can grow rapidly, making full dynamism challenging.
* **In OOO or highly concurrent CPUs:** Real-world jitter (from speculation, prefetch, DRAM refresh, etc.) limits guarantee precision.
* **NUMA/hypercube systems:** Multiple time schedules must be maintained per region/channel; cross-region ECs require careful analysis.

**Summary Table:**

| Property              | Feasible in Hardware? | Comments                                            |
| --------------------- | --------------------- | --------------------------------------------------- |
| RT slot reservation   | Yes, for small N      | Proven in RT bus/DRAM, but static configs preferred |
| Dynamic fractal merge | Maybe, with limits    | Sched complexity and reconfig cost can explode      |
| Preempting BE traffic | Yes, with some cost   | Needs BE aware of preemption, possible buffer flush |
| Support in OOO CPUs   | Challenging           | Non-RT harts must respect schedule strictly         |

**Bottom Line:**
As an abstraction, this model is robust for both design and reasoning. For hardware, it’s feasible for moderate RT workloads and semi-static reservation. For fully dynamic, general-purpose systems, practical feasibility may require bounding N, scheduling depth, and update frequency to avoid runaway complexity.

---

### Hierarchical Bandwidth Limiting and Group Caps

**Motivation:**
Limiting a VM’s *total guaranteed bandwidth* (across all its ECs/vCPUs) is a critical control axis, beyond just restricting latency and bandwidth class bits for each individual EC. This allows the host to ensure that VMs cannot over-commit global memory resources, while still permitting opportunistic use of bandwidth if no one else is contending.

**Mechanism:**

* **Per-EC Bandwidth Classes:**
  Each EC/vCPU sets a bandwidth class bitfield that defines its *minimum guaranteed slice*.

* **VM (Group) Bandwidth Cap:**
  The host, when delegating a context group (e.g., to a VM or tenant), sets a *maximum total bandwidth cap* for all ECs in that group.
  This is enforced by hardware as:
  B\_VM,tot = sum\_over\_VM(B\_j) <= B\_VM,cap
  where B\_j is the minimum bandwidth for each EC, and B\_VM,cap is the cap set at group assignment.

* **Admission Control:**

  * For all guaranteed ECs system-wide (host and all VMs):
    sum\_all(B\_j) <= B\_total \* (1 - f\_BE)
    where f\_BE is the reserved fraction for best-effort (non-guaranteed) ECs.
  * Hardware checks both the **per-VM cap** and **global sum** whenever an EC is created or updates its class.

* **Opportunistic Best-Effort Use:**

  * VMs (and ECs within) can use more bandwidth than their cap, *but only if* no other (host or tenant) EC is requesting guaranteed access.
  * Hardware distinguishes guaranteed vs. best-effort traffic in arbitration.

* **Delegation:**

  * When a group is assigned to a VM, the host sets the cap and restricts which bandwidth/latency bits the guest may set (as before).
  * VM must divide its assigned cap among its own ECs, and cannot exceed the group’s cap in aggregate.

---

**Worked Example:**

* System total bandwidth B\_total = 16 units (slices per period).
* Host reserves at least 25% for best-effort, so B\_BE ≥ 4.
* Host runs 1 real-time thread (RT0) needing 4 units.
* VM1 is delegated a cap of 6 units for all its ECs.
* VM2 is delegated a cap of 2 units.
* Best-effort pool: 4 units, shared round-robin by all best-effort ECs.
* Hardware maintains:

  * For each group/VM, a running total of all active ECs’ class settings.
  * On EC create/update, refuses the request (raises exception) if it would push group or global over cap.

---

**Summary Table:**

| Mechanism              | Who sets? | Who enforces? | Purpose                                      |
| ---------------------- | --------- | ------------- | -------------------------------------------- |
| Per-EC class bits      | OS/VM     | Hardware      | Minimum slice/block per EC                   |
| VM group bandwidth cap | Host OS   | Hardware      | Max guaranteed bandwidth across group        |
| BE pool usage          | Hardware  | Hardware      | Everyone can use leftovers opportunistically |

---

**Result:**

* Host always retains control.
* VMs can use only what is delegated, never more guaranteed bandwidth than allowed.
* All math and checks are O(1) in hardware: just add/subtract class values on each change and check cap.

---

### Hardware Feasibility and Orthogonality

**Is the bandwidth and group cap math O(1) in hardware?**
Yes. Enforcing per-group caps and per-system totals is O(1) per EC update: hardware maintains a running sum for each group (and a global total), and on every EC creation, destruction, or class bit update, simply adds/subtracts the change and checks against the cap(s). Checking a new request is a simple `current_sum + requested <= cap?` test, which is common in hardware resource allocation (e.g., network switches, storage QoS).

**Is this math or mechanism unusual in hardware?**
No. Similar quota/cap enforcement is widely used in:

* DRAM and memory controller QoS
* Network-on-chip (NoC) arbitration
* Hierarchical fair queuing in switches and routers
* Intel RDT/MBA and cache allocation hardware

The main novelty is applying it to CPU execution context groups and exposing it in the ISA, but the logic itself is standard.

**Integration with ECID and Groups:**
Group caps and tracking fit neatly into the existing ECID/bank group model:

* Each group is assigned a bandwidth cap and maintains its own sum.
* ECID context switch or delegation passes accounting to the new group owner.
* All enforcement occurs at context switch or EC (re)configuration.

**Are CME, CPE, QOS, and MSE still orthogonal?**
Yes. Each extension is independently implementable:

* CME handles context banks, ECID, and group delegation.
* CPE handles cache partitioning.
* QOS handles DMA, IO, and device QoS.
* MSE handles memory bandwidth/latency scheduling, group caps, and best-effort arbitration.

The extensions interact via the execution context resource profile and group IDs but can be implemented or omitted individually.

**Does O(N) complexity ever matter?**
Only for diagnostic/audit operations, which are rare and can be run in software. For all normal runtime operations, per-EC/group math is always O(1).

**Communicating to designers and users:**
The core principle is, “The sum of all group requests must never exceed the system cap minus the reserved best-effort pool, and no group can exceed its own cap.” This is analogous to disk quotas and network bandwidth allocation.

---

**Summary Table:**

| Issue                       | O(1) Feasible? | Notes/References                    |
| --------------------------- | -------------- | ----------------------------------- |
| Per-EC class enforcement    | Yes            | Add/subtract on class change        |
| Per-group cap enforcement   | Yes            | Running sum over group's active ECs |
| Per-system best-effort pool | Yes            | Subtract total guaranteed from T    |
| Audit of all ECs            | O(N)           | Only for diagnostics/auditing       |
| Hardware implementation     | Common         | NoC, network, RDT, SoC references   |

---

### Prior Art and Design Parallels for MSE

**The MSE resource scheduling and arbitration design closely resembles proven systems in other fields:**

* **Weighted Fair Queuing (WFQ), Deficit Round Robin (DRR), and Hierarchical Token Bucket (HTB) in networking:**
  Flows or groups are given bandwidth reservations and maximums, with round-robin or deficit-based arbitration. Hierarchies allow tenants or subgroups to subdivide resources without exceeding global caps.

* **Hierarchical Fair Queuing (HFQ) in routers and SoC interconnects:**
  Bandwidth and latency are allocated at multiple levels (system, tenant, flow), enforced at each step.

* **Disk and IO Schedulers (e.g., Linux Deadline, CFQ):**
  IOs are tagged with deadlines or timeslices; the scheduler tries to maximize utilization without missing any critical deadline.

* **Intel RDT (CAT/MBA):**
  OS/VM assigns “ways” or bandwidth to tenants/cores; hardware enforces min/max caps and lets unused resources be opportunistically borrowed.

* **Cloud resource cgroups and quotas:**
  OS-level resource containers can delegate quotas down a hierarchy, with hardware or hypervisor enforcing the global and per-group limits.

**Best Practices and Tricks to Consider:**

* **Tokens/buckets/windows:**
  Allocate bandwidth and latency guarantees as tokens per window (e.g., per 16 cycles). Hardware just hands out tokens, OS decides quota and replenishment.
* **Deficit accounting:**
  Track "unused" quota per EC/group. If one doesn't use its share, others can borrow it, but no EC can starve a critical workload.
* **Hierarchical enforcement:**
  Allow groups to subdivide allocations, but always enforce global top-level caps in hardware. Never trust a subtenant with more than their delegated quota.
* **Preemption and feedback:**
  Hardware raises exceptions or signals to the OS if a guarantee is violated (deadline missed, quota exceeded). OS can throttle, reschedule, or log accordingly.
* **Admission control:**
  Hardware always performs O(1) checks for cap overflow before admitting a new request. Reject or flag if not feasible.

**Implications:**

* These practices increase predictability, safety, and utilization—while keeping hardware state minimal (O(groups), O(N) active ECs).
* Most high-assurance or real-time resource schedulers in networking, IO, or storage now use similar patterns.

---

**References for MSE Designers:**

* [Weighted Fair Queuing (Wikipedia)](https://en.wikipedia.org/wiki/Weighted_fair_queueing)
* [Deficit Round Robin](https://en.wikipedia.org/wiki/Deficit_round_robin)
* [Intel Resource Director Technology](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-resource-director-technology.html)
* [Hierarchical Token Bucket](https://man7.org/linux/man-pages/man8/tc-htb.8.html)
* [Linux cgroups resource control](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

---

**Bottom Line:**
**MSE is a generalization and unification of techniques long proven in networking, IO, and cloud infrastructure. By mirroring these, and explicitly referencing them in your documentation, you build confidence for reviewers, implementers, and future OS/hardware teams.**

---

### Timescales and Complexity of MSE Events and Decisions

| Event / Decision Type                 | Typical Timescale                  | Actor         | Complexity       | Notes                                                  |
| ------------------------------------- | ---------------------------------- | ------------- | ---------------- | ------------------------------------------------------ |
| **Per-memory-access arbitration**     | ns – low μs (per cycle/burst)      | MMU/hw        | O(1)             | Needs to be wire-speed; uses only per-hart/group state |
| **Per-window accounting**             | 10s–100s of ns (fixed window)      | MMU/hw        | O(1)             | Token/counter reset; no scanning                       |
| **Context switch**                    | μs – ms                            | OS, CME       | O(1) in hardware | CME atomic; profile loaded in one shot                 |
| **Best-effort pool redistribution**   | Per window or as needed            | MMU/hw        | O(1)             | Simple round-robin/fair sharing among BE ECs           |
| **OS rescheduling**                   | μs – ms                            | OS            | O(M)             | Can be arbitrarily complex; not on performance path    |
| **OS/hypervisor MSE reconfiguration** | ms – seconds (rare)                | OS/sysadmin   | O(M), slow       | Changes quotas/caps; infrequent                        |
| **Admission control checks**          | On EC creation/change (rare, fast) | MMU/hw        | O(1) per event   | Always a running sum of actives; no list walks         |
| **Telemetry/feedback to OS**          | Per violation, per window          | MMU/hw        | O(1)             | Exception, CSR update, interrupt to OS                 |
| **Group/tenant delegation**           | VM setup/teardown (rare)           | OS/hypervisor | O(1) in hw       | Just set cap and bit mask; no runtime burden           |

**Key Principles:**

* All *per-cycle, per-arbitration,* and *per-window* logic must be O(1) in hardware, referencing only the N active harts and O(groups) active groups.
* Only the OS/hypervisor ever deals with the full set of M ECs or arbitrarily complex rescheduling; hardware never does.
* Hardware does not maintain large tables, dynamic lists, or complex data structures—*all state is fixed-size and fast*.

**What Best Practices Are Safe?**

* **Token bucket / per-window accounting**: Natural fit for hardware timescales and complexity.
* **Deficit accounting/borrowing**: Feasible for active ECs/groups in a window.
* **Hierarchical enforcement**: Only track active groups; deep hierarchy is OS-level.
* **Feedback/exceptions**: O(1) signaling; hardware just flips a flag or raises an interrupt.
* **Admission control**: Always an O(1) check at event time.

**What to Avoid in Hardware:**

* No run-queue, linked lists, or variable-size tables in the MMU.
* No speculative or predictive logic—hardware only enforces for what is active now.

**Conclusion:**
MSE is fully feasible for modern MMUs/memory controllers *if and only if* all per-access and per-window logic remains O(1), with all “big” or complex logic left to the OS/hypervisor at much slower timescales.

---

### Example: Bank Teardown in a Multi-Level Virtualized System

**Delegation Tree:**

```
L0 (host)         [owns 10 banks]
│
├── L1 VM1 [3 banks]
│
├── L1 VM2 [3 banks]
│
├── L2 HV1 [8 banks]
│   ├── L3 VM1 [2 banks]
│   └── L3 VM2 [2 banks]
├── L2 HV2 [8 banks]
│   ├── L3 VM3 [2 banks]
│   └── L3 VM4 [2 banks]
├── ... repeat for HV3..HV6, each with 8 banks → 2 VMs with 2 banks each
└── (Total: 6 L2 HVs × 8 = 48 banks at L2, each passes 4 down to 2 L3 VMs)

```

**Totals:**

* L0: 10 banks
* 2 L1 VMs: 3 banks each (6 total)
* 6 L2 HVs: 8 banks each (48 total, each passes 4 to two L3 VMs)

---

#### **Teardown Sequence: All-Cooperate Case**

1. **L0 initiates reclaim:**

   * Sets `give-warning-first` bit, triggering hardware warning exceptions to all child groups/tenants (L1/L2/L3).
   * All OSes/VMs/hypervisors begin cleanup, close contracts, and free banks during grace period.
2. **Grace period:**

   * All levels respond quickly and release banks in parallel. (E.g., 2 cycles per bank for all, overlapped.)
3. **L0 initiates hard reclaim after grace:**

   * Hardware follows parent pointers, reclaiming banks recursively:

     * L3 VMs return banks to L2 HVs.
     * L2 HVs return all banks to L0.
     * L1 VMs return banks to L0.
   * Each group/bank can be reclaimed in 1 cycle, all in parallel.

**Total time (all-parallel):**

* Warning: 1 cycle
* Grace: 2 cycles
* Reclaim: 1 cycle
* **Total: 4 cycles (plus trivial OS clean-up, if any)**

---

#### **Teardown Sequence: Some Uncooperative Tenants**

1. **L0 initiates reclaim and warnings as above.**
2. **Grace period:**

   * Some VMs/HVs/OSes do not release banks; hardware waits full grace period (e.g., 2 cycles per bank), then proceeds.
3. **Hard reclaim:**

   * Hardware forcibly marks banks as invalid and returns them upward.
   * Parent pointers are followed up; all banks are reclaimed, no matter who is uncooperative.
   * Uncooperative tenants may receive error/panic, but system state is restored.

**Total hardware time:**

* Still **4 cycles** (all banks/groups in parallel); uncooperative tenants only delay their own cleanup, not the system.

---

#### **Key Guarantees:**

* Hardware always reclaims all banks in the tree, even if some tenants do not cooperate.
* Total teardown is **O(1) per group/bank per level** and **fully parallelizable**.
* No orphan banks/groups possible.

Adding the new **Memory Throughput Comparison — Worked Example with Nested Virtualization Tree** to the end of your scratchpad:

---

### Memory Throughput Comparison — Worked Example with Nested Virtualization Tree

#### Scenario Recap

* **System:** 64 harts, 64 banks
* **Tree:** L0 (host) with 10 banks, 2 L1 VMs with 3 banks each, 6 L2 hypervisors with 8 banks each (each L2 divides 4 of its banks to 2 L3 VMs)
* **Total banks:** 64

#### Workload Assumptions

* All ECs are active, but not all are saturated all the time (some are bursty).
* Banks assigned to L1 VMs and L2/L3 VMs represent tenants with varying demand.
* Some banks (e.g., for interrupt controller) have guaranteed contracts, others are best-effort.

---

#### A. No MSE (Baseline)

* **Behavior:**

  * Memory is arbitrated only by simple hardware round-robin or FIFO.
  * Any bursty tenant (e.g., L0 or L1) can flood the bus if it becomes active.
  * High throughput when busy tenants are running.
  * No guarantee that critical L3 VMs or interrupt handlers get timely service.
* **Result:**

  * If L0 runs a burst, it may consume nearly all bandwidth; lower-level VMs get starved.
  * *Average throughput: Near hardware peak*

    * *But:* Latency can spike for RT or critical tasks.
    * *Unfairness, head-of-line blocking possible.*

---

#### B. MSE Without Pools

* **Behavior:**

  * Each group/tenant has a fixed contract (e.g., 10 for L0, 3 for each L1, 8 for each L2).
  * Best-effort ECs have leftover quota.
  * If a tenant isn’t using its allocation, that bandwidth is idle until the window ends.
* **Result:**

  * Throughput drops below hardware peak when some tenants underutilize their contract.
  * No starvation; latency and minimum throughput are guaranteed for each group.
  * *Average throughput: Lower than baseline, as idle reserved slices can’t be borrowed.*

---

#### C. MSE With Pools

* **Behavior:**

  * Pools defined: e.g., all interrupt controllers share a pool, all L2 hypervisors in a “hypervisor pool,” etc.
  * Unused pool bandwidth can be used by any member of the pool, not statically partitioned.
  * Best-effort and RT/critical pools are dynamically balanced each window.
* **Result:**

  * *Critical VMs always get guaranteed minimums;* if they need more and other pool members are idle, they can use the surplus.
  * Best-effort jobs fill *all* remaining capacity, so hardware is always busy.
  * *Average throughput: Matches or exceeds baseline (no unused slots), plus fairness and predictability!*

---

#### Illustrative Example

Suppose during a 16-slot window:

| Tenant              | Contract (no pools) | Usage (this window) | No MSE (burst) | MSE (no pools) | MSE (with pools) |
| ------------------- | ------------------- | ------------------- | -------------- | -------------- | ---------------- |
| L0 (host/daemon)    | 10                  | 4                   | 10             | 10 (6 idle)    | 4                |
| L1 VM1              | 3                   | 3                   | 2              | 3              | 3                |
| L1 VM2              | 3                   | 0                   | 0              | 3 (3 idle)     | 0                |
| 6×L2 HVs (48 total) | 8                   | 6 (avg per HV)      | 6              | 8 (2 idle)     | 6                |
| Interrupt pool      | —                   | 1                   | 0              | 0              | 1                |
| Best-effort jobs    | remainder           | fills rest          | starved        | partial        | fills all slack  |

* **No MSE:** L0 or any tenant with a burst can fill all 16 slots if active.
* **MSE, no pools:** If L0 only uses 4 of its 10, 6 slots go idle; L1 VM2’s 3 go idle. Only 7+8\*6+1 = 56 slots used; 8 go unused.
* **MSE with pools:** Idle slots from L0, L1 VM2, or any under-bursty tenant are immediately available to others in the pool (or to best-effort jobs). All 16 slots are used.

---

#### Conclusion

* **No MSE:** Max bandwidth, minimum fairness/predictability.
* **MSE, no pools:** Predictable, but can waste bandwidth.
* **MSE + pools:** Predictable *and* full bandwidth utilization.

**Pools allow the system to operate at near-peak memory throughput without ever sacrificing guarantees.**

---

**Section inserted. Let me know if you want a visual, or want to expand this scenario with more levels or another angle!**

