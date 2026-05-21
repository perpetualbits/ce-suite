Technical White Paper: The Contextual Execution (CE) RISC-V Architecture
Author: [Your Name/Handle Here]
Date: December 2, 2025
1. Introduction
Traditional computing architectures (x86, standard RISC-V) prioritize average-case throughput but suffer from non-deterministic latency in shared resource access (memory, I/O, cache interference). This makes them unsuitable for "hard real-time" (HRT) applications such as surgical robotics, avionics control, and professional digital audio workstations (DAWs).
The Contextual Execution (CE) system is a proposed suite of five RISC-V extensions that introduces deterministic behavior and guaranteed Quality of Service (QoS) by moving key scheduling and resource management functions from non-deterministic software to dedicated hardware.
2. The Core Problem & The CE Solution
The central challenge in HRT is guaranteeing a Worst-Case Execution Time (WCET). CE removes indeterminacy through two main mechanisms:
Execution Context Isolation: Using hardware-managed Execution Context IDs (ECIDs) to partition resources (cache, context banks).
Deterministic Arbitration: Replacing complex, unpredictable memory/IO arbiters with a time-sliced, priority-based QoS system.
3. The Five CE Extensions
The CE system is a holistic architecture composed of the following integrated extensions:
3.1. Context Banks for 1-Cycle Task Switching
Description: Replicates the entire architectural CPU state (GPRs, FPRs, CSRs, PC) into dedicated on-chip register banks (~32 or 64 banks).
Benefit: Enables instantaneous (1-cycle) context switching between prioritized tasks or interrupts, eliminating the latency of saving/restoring state to memory.
3.2. Cache Partitioning Extension
Description: Assigns slices of private and shared cache memory to specific ECIDs or groups. Tags are added to cache lines, and eviction policies are hardware-enforced.
Benefit: Prevents "noisy neighbor" interference. High-priority tasks are guaranteed a minimum amount of high-speed cache, ensuring predictable memory access latency.
3.3. I/O Management Extension (QoS)
Description: Applies a priority-based, time-sliced arbitration scheme to the internal SoC interconnect and peripheral DMA controllers, mirroring the memory system approach.
Benefit: Guarantees timely I/O access for critical tasks (e.g., sensor reading or actuator control) regardless of background I/O traffic.
3.4. Memory Access Management Extension (QoS Arbiter)
Description: Replaces the standard memory controller arbiter with a deterministic scheduler using alternating time slots (Best Effort (BE) | Real-Time (RT) | BE | RT...). The system guarantees that any RT request is serviced within 2x its allocated time slot.
Benefit: Provides a provable bound on memory access latency, a cornerstone of HRT guarantees. Idle RT slots are loaned to BE tasks for efficiency.
3.5. Execution Context ID (ECID) & Group System
Description: The hardware identifier linking all extensions. An ECID points to a kernel data structure (ECS) in memory. A "group" system manages ownership and security, abstracting these controls for higher-level use.
Benefit: Provides a seamless hardware-software interface for the OS/Hypervisor to manage real-time guarantees.
4. Hardware Overhead & Rationale
Implementing the CE suite adds an estimated 5%–15% transistor overhead per core, primarily for the context banks. This allows fitting approximately 96 CE-enabled harts into the die area of 128 standard harts.
This trade-off is justified by superior metrics in:
Metric	Non-CE System (128 Harts)	CE System (96 Harts)
WCET Guarantee	Unbound / Impossible to prove	Deterministic & Provable
Latency Jitter	High and unpredictable	Near Zero (Bounded)
Context Switch Time	Hundreds/Thousands of cycles	1-2 Cycles
Certifiability	No (e.g., ASIL D, FDA Class III)	Yes
5. Applications & Use Cases
The CE architecture enables applications currently impossible on conventional hardware:
Life-Critical Systems: Surgical robotics, autonomous driving controllers, and certified avionics systems due to guaranteed determinism.
Professional Audio/Video: Glitch-free DAWs and physical modeling simulators via ultra-low, guaranteed I/O latency.
Real-Time Virtualization: The Group system allows hard real-time virtual machines (RT-VMs) to run with strong temporal isolation on the same SoC as best-effort VMs.
High-Frequency Trading: Guaranteed latency for market data processing.
6. Next Steps for Development
To engage the RISC-V International community and pursue inclusion in future specifications (RVA24/RVA25), the focus must shift from full FPGA demos to formal modeling:
Formalize Specification: Finalize the existing 27,000-word document and publish it on GitHub.
Develop SystemC Model: Prioritize a SystemC or performance model to generate quantitative data proving the WCET guarantees.
Engage TWGs: Present the formal specification and simulation results to the Real-Time TWG and Platforms TWG within RISC-V International via the RFP process.

