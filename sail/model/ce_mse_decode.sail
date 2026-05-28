// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — MSE instruction decode stubs
 * Spec reference: ch09 §9.11 (encoding table)
 *
 * MSE instructions: ms.ir, ms.or, ms.it, ms.ot
 * funct3 = 010, opcode = custom-0
 * Execute functions: TODO (Sail v2)
 */

let MSE_MSIR : bits(7) = 0b0000000
let MSE_MSOR : bits(7) = 0b0000001
let MSE_MSIT : bits(7) = 0b0000010
let MSE_MSOT : bits(7) = 0b0000011

union clause ast = {
  CE_MSIR : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(descriptor) */
  CE_MSOR : (regidx, regidx),          /* rd, rs1(ecid) */
  CE_MSIT : (regidx, regidx, regidx),  /* rd, rs1(src_ecid), rs2(child_ecid) */
  CE_MSOT : (regidx, regidx)           /* rd, rs1(child_ecid) */
}

mapping clause encdec = CE_MSIR(rd, rs1, rs2) <->
  MSE_MSIR @ rs2 @ rs1 @ FUNCT3_MSE @ rd @ CE_OPCODE

mapping clause encdec = CE_MSOR(rd, rs1) <->
  MSE_MSOR @ 0b00000 @ rs1 @ FUNCT3_MSE @ rd @ CE_OPCODE

mapping clause encdec = CE_MSIT(rd, rs1, rs2) <->
  MSE_MSIT @ rs2 @ rs1 @ FUNCT3_MSE @ rd @ CE_OPCODE

mapping clause encdec = CE_MSOT(rd, rs1) <->
  MSE_MSOT @ 0b00000 @ rs1 @ FUNCT3_MSE @ rd @ CE_OPCODE

function clause execute(CE_MSIR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_MSOR(rd, rs1))      = { raise(IllegalInstruction()) }
function clause execute(CE_MSIT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_MSOT(rd, rs1))      = { raise(IllegalInstruction()) }
