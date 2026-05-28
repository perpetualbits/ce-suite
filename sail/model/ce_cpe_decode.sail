// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CPE instruction decode stubs
 * Spec reference: ch07 §7.10 (encoding table)
 *
 * CPE instructions: cp.ir, cp.or, cp.it, cp.ot
 * funct3 = 001, opcode = custom-0
 * Execute functions: TODO (Sail v2)
 */

/* CPE funct7 selectors (ch07 §7.10) */
let CPE_CPIR : bits(7) = 0b0000000
let CPE_CPOR : bits(7) = 0b0000001
let CPE_CPIT : bits(7) = 0b0000010
let CPE_CPOT : bits(7) = 0b0000011

union clause ast = {
  CE_CPIR : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(descriptor) */
  CE_CPOR : (regidx, regidx),          /* rd, rs1(ecid) */
  CE_CPIT : (regidx, regidx, regidx),  /* rd, rs1(src_ecid), rs2(child_ecid) */
  CE_CPOT : (regidx, regidx)           /* rd, rs1(child_ecid) */
}

mapping clause encdec = CE_CPIR(rd, rs1, rs2) <->
  CPE_CPIR @ rs2 @ rs1 @ FUNCT3_CPE @ rd @ CE_OPCODE

mapping clause encdec = CE_CPOR(rd, rs1) <->
  CPE_CPOR @ 0b00000 @ rs1 @ FUNCT3_CPE @ rd @ CE_OPCODE

mapping clause encdec = CE_CPIT(rd, rs1, rs2) <->
  CPE_CPIT @ rs2 @ rs1 @ FUNCT3_CPE @ rd @ CE_OPCODE

mapping clause encdec = CE_CPOT(rd, rs1) <->
  CPE_CPOT @ 0b00000 @ rs1 @ FUNCT3_CPE @ rd @ CE_OPCODE

/* Execute stubs — TODO in Sail v2 */
function clause execute(CE_CPIR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_CPOR(rd, rs1))      = { raise(IllegalInstruction()) }
function clause execute(CE_CPIT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_CPOT(rd, rs1))      = { raise(IllegalInstruction()) }
