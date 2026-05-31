<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Cluster F — QoS local-view recommendation

**Status:** Scratchpad — explicitly NOT normative. Input to a dedicated
charter session; carries no authority over the charter or any chapter until
promoted there. (See `scratchpads/README.md`.)
**Date / label:** 2026-05-31 — recommendation for how QoS realizes the
local-view principle the charter already mandates for it.
**Intended path:** `scratchpads/qos/cluster_f_local_view_recommendation.md`
**Disposition route:** promote into charter + ch00 + ch11 + ch13 via the
charter session and its per-chapter follow-ups, then this scratchpad is
superseded.

---

## Provenance (read this first)

The round-two close stamp in `ce_core_designloop_session_capture.md` recorded
this recommendation as "drafted and architect-approved." It was never
committed — no file existed at the intended path, and `git log` for
`scratchpads/qos/` shows no commit creating it. The recommendation lived only
in round-two chat. web-Claude reconstructed it during round three from verified
repo state (charter v0.24); the architect re-confirmed the single design choice
in the round-three chat. This file restores the artifact a charter session
needs to cite, so the session is not built on a document that does not exist.

This recommendation does not change anything. It records one approved design
choice and the work a later charter session must do; the charter session is the
architect's, and it makes the normative edits.

---

## The question Cluster F closes

The charter already makes the **local-view principle a hard invariant**:
software runs unchanged at any delegation level, and hardware converts internal
stored-global values into the running EC's local view at read time (charter
§4.5.0; ch00 §0.7 "local-view CSR readbacks"). MSE realizes this concretely:

- Stored-global accounting CSRs: `mse_bw_cap` (0x7C7), `mse_bw_sum` (0xFC9).
- A separate **local-view readback** CSR: `mse_absolute_bw` (0xFD3), an 8-bit
  pre-flattened `BW` field on the 0–255 scale, computed by hardware at read
  time via **Formula 2** (ch09 §9.4.6): `r(e) = floor( s(e) × N / s(p(e)) )`,
  N = 256.

ch00 explicitly **defers the QoS realization to Cluster F** — the QoS bullet
reads, in effect, "when cluster F resolves, QoS applies the same local-view
principle for I/O fabric domains," and the CPE bullet says cluster F will
formalize it. So the principle is normative; the QoS *mechanism* is the hole.

The hole is concrete: QoS today has the stored-global half — `qos_bw_cap`
(0x7CC) and `qos_bw_sum` (0xFCE), defined in ch13 §6.6/§6.7 as analogous to the
MSE CSRs — but **no local-view readback CSR analogous to `mse_absolute_bw`**.
Delegated software has no way to read its own I/O-bandwidth slice in local
terms the way it can for memory.

## The recommendation (the architect's confirmed choice)

**Borrow the MSE storage format; v1 is single-level.** Concretely:

1. **Same two-tier storage model as MSE.** QoS keeps its stored-global
   accounting CSRs (already present) and gains a new **QoS local-view readback
   CSR**, the I/O-fabric analog of `mse_absolute_bw`, computed by the same
   Formula 2 readback. No new hardware mechanism is introduced — this is the
   MSE template applied to the I/O-fabric/NoC domain, consistent with CE's
   "no new mechanisms" stance and with committed framing F3–F6 (QoS adopts
   MSE's pre-flattening, arbitration, and rounding).

2. **Single-level in v1 — no telescoping.** This is committed framing **F2**:
   telescoping is only meaningful when VMs hold direct hardware I/O
   (IOMMU/passthrough), narrower than MSE's universal applicability. So the v1
   QoS local-view returns fraction-of-own-slice at the running level without
   composing a multi-level delegation chain. At L=0 the readback equals
   fraction-of-total directly, exactly as MSE behaves at L=0. Multi-level
   telescoping for QoS is a post-v1 question, revisited only if direct-HW-I/O
   VMs become common.

This satisfies the local-view invariant for the QoS half and is the last
design-loop blocker on criterion 4. It does not touch the QoS Contract
lifecycle (create → bind → split → release), which already mirrors MSE.

## Open spec details the charter session settles (not fixed here)

These are charter-session calls; web-Claude flags them rather than deciding:

- **CSR address.** The new QoS local-view readback CSR needs an address in the
  user-RO QoS block (neighborhood of `qos_bw_sum` 0xFCE / by analogy to MSE's
  0xFD3). The charter session assigns it; this scratchpad does not.
- **Scale reconciliation.** The QoS Contract `bw_class` field is 4 bits
  (ch11 §11.5.1), while MSE's local-view readback is 8-bit pre-flattened on the
  0–255 scale. Borrowing the MSE format implies the QoS readback presents the
  same Formula-2 0–255 pre-flattened value derived from the 4-bit class. The
  charter session confirms this is the intended scale and that the 4-bit→0–255
  pre-flattening matches MSE's.
- **Exact section anchors** in charter/ch00/ch11/ch13 (below) are confirmed by
  the charter session against the live repo before any edit.

## Propagation surface (for the charter session + per-chapter sessions)

This lands as a charter session followed by per-chapter sessions — **one file
per code-Claude session, propagation check before each commit, no sweep**:

- **charter** — make the QoS local-view normative (the §4.5.0 local-view family
  applied to QoS); cite the exact base mechanism reused (Formula 2, MSE storage
  format) under "no new mechanisms." Version bump + changelog.
- **ch00** — replace the "when cluster F resolves" QoS deferral (the QoS bullet
  in the local-view §, near the CPE/QoS bullets ~line 506) with the realized
  mechanism.
- **ch11** — add a local-view readback subsection (the QoS analog of MSE's
  reading example in ch10 §10.10) and reference the new CSR.
- **ch13** — add the new QoS local-view CSR as a §6.x entry, analogous to §5.9
  `mse_absolute_bw`, with the Formula-2 semantics and the assigned address.

The Cluster F priority item in `docs/work-items.md` (Current priority §, item 1)
is the tracking entry; the charter session flips it from "charter session
pending" to resolved with the commit hash, following the cluster D pattern but
with narrower scope (no telescoping section for QoS, per F2).
