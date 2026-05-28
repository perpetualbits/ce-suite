// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — QoS instruction decode stubs
 * Spec reference: ch11 §11.11 (encoding table)
 *
 * QoS instructions: qs.ir, qs.or, qs.it, qs.ot
 * opcode = 0b0001011, funct3 = 0b011 (QoS)
 * funct7: QSIR=0b0000000 QSOR=0b0000001 QSIT=0b0000010 QSOT=0b0000011
 *
 * Note: qs.or and qs.ot take rs2 as a domain selector (ch11 §11.6.3).
 * Execute functions: TODO (Sail v2)
 */

union clause instruction = CE_QSIR : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(descriptor) */
union clause instruction = CE_QSOR : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(domain_id) */
union clause instruction = CE_QSIT : (regidx, regidx, regidx)    /* rd, rs1(src_ecid), rs2(child_ecid) */
union clause instruction = CE_QSOT : (regidx, regidx, regidx)    /* rd, rs1(child_ecid), rs2(domain_id) */

mapping clause encdec = CE_QSIR(rd, rs1, rs2) <->
  0b0000000 @ rs2 @ rs1 @ 0b011 @ rd @ 0b0001011

mapping clause encdec = CE_QSOR(rd, rs1, rs2) <->
  0b0000001 @ rs2 @ rs1 @ 0b011 @ rd @ 0b0001011

mapping clause encdec = CE_QSIT(rd, rs1, rs2) <->
  0b0000010 @ rs2 @ rs1 @ 0b011 @ rd @ 0b0001011

mapping clause encdec = CE_QSOT(rd, rs1, rs2) <->
  0b0000011 @ rs2 @ rs1 @ 0b011 @ rd @ 0b0001011

function clause execute(CE_QSIR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSOR(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSIT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
function clause execute(CE_QSOT(rd, rs1, rs2)) = { raise(IllegalInstruction()) }
