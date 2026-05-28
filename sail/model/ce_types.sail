// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — base types, constants, and error codes
 * Spec reference: ch00 §0.2 (ECID), ch15 §15.4 (error codes)
 */

/* ECID: 16-bit, hart-local (ch00 §0.2) */
type ecid_t = bits(16)

/* Register group mask: XLEN-wide (ch03 §3.7, ch00 §0.10) */
type regmask_t = xlenbits

/* Delegation level: 0..3, D ≤ 3 (ch00 §0.8) */
type del_level_t = bits(2)

/* Generation counter: 8-bit (ch00 §0.3) */
type generation_t = bits(8)

/* Bank slot index returned by ec.ib (ch03 §3.1) */
type bank_slot_t = bits(8)

/* ------------------------------------------------------------------ */
/* CME error codes (ch15 §15.4)                                       */
/* ------------------------------------------------------------------ */

type cme_error_t = bits(8)

let CME_OK                : cme_error_t = 0x00
let CME_ERR_INVALID_ECID  : cme_error_t = 0x01  /* unallocated slot or generation mismatch */
let CME_ERR_NO_BANK       : cme_error_t = 0x02  /* free-bank pool empty or no bank resident */
let CME_ERR_PERMISSION    : cme_error_t = 0x03  /* caller not an authorized ancestor */
let CME_ERR_CAP_DEPTH     : cme_error_t = 0x04  /* delegation depth cap D exceeded */
let CME_ERR_ILLEGAL_FIELD : cme_error_t = 0x05  /* reserved field non-zero in operand */
let CME_ERR_ALREADY_SEALED : cme_error_t = 0x06 /* bank is already sealed */
let CME_ERR_NOT_SEALED    : cme_error_t = 0x07  /* bank not sealed, or authentication failed */

/* Widen error code to XLEN for writing into rd */
function cme_err_to_xlenbits(e : cme_error_t) -> xlenbits = zero_extend(e)

/* ------------------------------------------------------------------ */
/* CE Suite instruction encoding constants (ch03 §3.10)               */
/* ------------------------------------------------------------------ */

/* All CE Suite instructions share opcode custom-0 */
let CE_OPCODE : bits(7) = 0b0001011  /* 0x0B */

/* funct3 selects the extension */
let FUNCT3_CME : bits(3) = 0b000
let FUNCT3_CPE : bits(3) = 0b001
let FUNCT3_MSE : bits(3) = 0b010
let FUNCT3_QOS : bits(3) = 0b011

/* CME funct7 selectors (ch03 §3.10.3) */
let CME_ECIB : bits(7) = 0b0000000
let CME_ECOB : bits(7) = 0b0000001
let CME_ECIM : bits(7) = 0b0000010
let CME_ECOM : bits(7) = 0b0000011
let CME_ECIG : bits(7) = 0b0000100
let CME_ECOG : bits(7) = 0b0000101
let CME_ECIT : bits(7) = 0b0000110
let CME_ECOT : bits(7) = 0b0000111
let CME_ECIR : bits(7) = 0b0001000
let CME_ECOE : bits(7) = 0b0001001
let CME_ECIV : bits(7) = 0b0001010
let CME_ECOV : bits(7) = 0b0001011
