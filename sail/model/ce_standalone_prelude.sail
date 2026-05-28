// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite standalone type-check prelude
 *
 * Includes sail-riscv's prelude (for zeros, zero_extend, etc.) then adds
 * CE-specific stubs for the scattered declarations and types that sail-riscv
 * provides in integrated mode.
 *
 * ONLY included in `make check` (standalone type-check).
 * NOT included in `make check-riscv` — sail-riscv provides the real versions.
 *
 * Requires: SAIL_RISCV set to the sail-riscv checkout path.
 * The Makefile passes this via the SAIL_RISCV variable.
 */

default Order dec

$include <smt.sail>
$include <option.sail>
$include <arith.sail>
$include <string.sail>
$include <mapping.sail>
$include <vector_dec.sail>
$include <vector.sail>
$include <generic_equality.sail>
$include <hex_bits.sail>
$include <hex_bits_signed.sail>
$include <dec_bits.sail>
$include <result.sail>

/* Utility functions from sail-riscv prelude — replicated for standalone */

val zeros : forall 'n, 'n >= 0. implicit('n) -> bits('n)
function zeros(n) = sail_zeros(n)

/* Boolean negation — stdlib defines not_bool; overload ~ for bool as well */
overload ~ = {not_vec, not_bool}

/* Integer division and modulo — sail-riscv prelude pattern */
val quot_positive_round_zero = pure {
  interpreter: "quot_round_zero", c: "tdiv_int", cpp: "tdiv_int"
} : forall 'n 'm, 'n >= 0 & 'm > 0. (int('n), int('m)) -> int(div('n, 'm))

val rem_positive_round_zero = pure {
  interpreter: "rem_round_zero", c: "tmod_int", cpp: "tmod_int"
} : forall 'n 'm, 'n >= 0 & 'm > 0. (int('n), int('m)) -> int(mod('n, 'm))

overload operator / = {quot_positive_round_zero}
overload operator % = {rem_positive_round_zero}

val zero_extend : forall 'n 'm, 'm >= 'n. (implicit('m), bits('n)) -> bits('m)
function zero_extend(m, v) = sail_zero_extend(v, m)

val sign_extend : forall 'n 'm, 'm >= 'n. (implicit('m), bits('n)) -> bits('m)
function sign_extend(m, v) = sail_sign_extend(v, m)

val to_bits : forall 'l, 'l >= 0. (int('l), int) -> bits('l)
function to_bits(l, n) = get_slice_int(l, n, 0)

/* XLEN — RV64 assumed for standalone check */
type xlenbits = bits(64)

/* Register index — newtype matching sail-riscv's core/types.sail */
newtype regidx = Regidx : bits(5)

/* CSR address */
type csreg = bits(12)

/* encdec_reg — maps regidx <-> bits(5); same pattern as sail-riscv */
mapping encdec_reg : regidx <-> bits(5) = { Regidx(b) <-> b }

/* Register file */
register xregs : vector(32, dec, xlenbits) = vector_init(zeros())

val rX : regidx -> xlenbits
function rX(Regidx(r)) = if unsigned(r) == 0 then zeros() else xregs[unsigned(r)]

val wX : (regidx, xlenbits) -> unit
function wX(Regidx(r), v) = { if unsigned(r) != 0 then xregs[unsigned(r)] = v }

overload X = {rX, wX}

/* FPR access — mirrors sail-riscv's fdext_regs.sail / freg_type.sail */
newtype fregidx = Fregidx : bits(5)
type flenbits = bits(64)            /* standalone: D-extension (64-bit FP) assumed */

register fpr_file : vector(32, dec, flenbits) = vector_init(zeros())

val rF_bits : fregidx -> flenbits
function rF_bits(Fregidx(r)) = fpr_file[unsigned(r)]

val wF_bits : (fregidx, flenbits) -> unit
function wF_bits(Fregidx(r), v) = { fpr_file[unsigned(r)] = v }

overload F = {rF_bits, wF_bits}

/* PC accessors — mirrors sail-riscv's pc_access.sail */
register nextPC : xlenbits = zeros()

val get_arch_pc : unit -> xlenbits
function get_arch_pc() = PC

val set_next_pc : xlenbits -> unit
function set_next_pc(pc) = { nextPC = pc }

/* Execution result — mirrors sail-riscv's ExecutionResult */
union ExecutionResult = {
  Retire_Success      : unit,
  Illegal_Instruction : unit
}

let RETIRE_SUCCESS : ExecutionResult = Retire_Success()

/* Scattered declarations that CE Suite adds clauses to.
 * In integrated mode these are declared by sail-riscv. */
scattered union instruction

val execute : instruction -> ExecutionResult
scattered function execute

val encdec : instruction <-> bits(32)
scattered mapping encdec

val read_CSR : csreg -> xlenbits
scattered function read_CSR

val write_CSR : (csreg, xlenbits) -> result(xlenbits, unit)
scattered function write_CSR
