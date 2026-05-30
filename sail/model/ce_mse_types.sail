// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — MSE architectural types
 * Spec reference: charter §4.5, ch09 §9.4 (Contract semantics),
 *                 ch13 §5 (MSE CSRs)
 *
 * MSE Contract fields (charter §4.5.1):
 *   - bw_class:  8 bits, pre-flattened on 0–255 absolute scale
 *                representing fraction of total system bandwidth.
 *   - lat_class: 8 bits, priority for tie-breaking (lower = higher).
 *   - precision: 4 bits, child precision when this Contract was
 *                created via ms.it (1–8 meaningful; 0 means
 *                "use parent's precision unchanged").
 *
 * Implementation-defined decoded widths are advertised via mse_caps.
 * Sail v1 models the maximum architectural width (8 bits per field).
 */

/* ------------------------------------------------------------------ */
/* Type aliases for function signatures                               */
/* ------------------------------------------------------------------ */

type bw_class_t   = bits(8)    /* pre-flattened bandwidth, 0-255 */
type lat_class_t  = bits(8)    /* priority, lower=higher */
type precision_t  = bits(4)    /* delegation precision, 1-8; 0 = parent */

/* ------------------------------------------------------------------ */
/* MSE_Contract (charter §4.5.1, ch09 §9.4)                          */
/* ------------------------------------------------------------------ */

struct MSE_Contract = {
  owner_ecid : ecid_t,        /* ECID this Contract belongs to */
  bw_class   : bw_class_t,    /* pre-flattened bandwidth (0-255) */
  lat_class  : lat_class_t,   /* priority for tie-break */
  precision  : precision_t,   /* delegation precision (0 = parent's) */
  valid      : bool           /* true iff this Contract is live */
}

let MSE_Contract_default : MSE_Contract = struct {
  owner_ecid = 0x0000,
  bw_class   = 0x00,
  lat_class  = 0x00,
  precision  = 0x0,
  valid      = false
}
