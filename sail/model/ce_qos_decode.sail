// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — QoS instruction decode stubs
 * Spec reference: ch11 §11.11 (encoding table)
 *
 * QoS instructions: qs.ir, qs.or, qs.it, qs.ot
 * funct3 = 011, opcode = custom-0
 *
 * Note: qs.or and qs.ot take rs2 as a domain selector (ch11 §11.6.3).
 * Execute functions: TODO (Sail v2)
 */

let QOS_QSIR : bits(7) = 0b0000000
let QOS_QSOR : bits(7) = 0b0000001
let QOS_QSIT : bits(7) = 0b0000010
let QOS_QSOT : bits(7) = 0b0000011

union clause ast = {
  CE_QSIR : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(descriptor) */
  CE_QSOR : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(domain_id) */
  CE_QSIT : (regidx, regidx, regidx),  /* rd, rs1(src_ecid), rs2(child_ecid) */
  CE_QSOT : (regidx, regidx, regidx)   /* rd, rs1(child_ecid), rs2(domain_id) */
}

mapping clause encdec = CE_QSIR(rd, rs1, rs2) <->
  QOS_QSIR @ rs2 @ rs1 @ FUNCT3_QOS @ rd @ CE_OPCODE

mapping clause encdec = CE_QSOR(rd, rs1, rs2) <->
  QOS_QSOR @ rs2 @ rs1 @ FUNCT3_QOS @ rd @ CE_OPCODE

mapping clause encdec = CE_QSIT(rd, rs1, rs2) <->
  QOS_QSIT @ rs2 @ rs1 @ FUNCT3_QOS @ rd @ CE_OPCODE

mapping clause encdec = CE_QSOT(rd, rs1, rs2) <->
  QOS_QSOT @ rs2 @ rs1 @ FUNCT3_QOS @ rd @ CE_OPCODE

function clause execute(CE_QSIR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSOR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSIT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSOT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
