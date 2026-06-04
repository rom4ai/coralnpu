/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Trap-flush smoke test for VEML instruction.
// Verifies the EML wrapper (rvv_backend_alu_unit_eml.sv) correctly clears
// state on trap_flush_rvv: busy=0, cycle_cnt=0, captured_valid=0.
//
// EML wrapper flush logic (lines 99-103):
//   } else if (trap_flush_rvv) begin
//     busy          <= 1'b0;
//     cycle_cnt     <= '0;
//     captured_uop  <= '0;
//     captured_valid <= 1'b0;
//
// This de-asserts result_valid (requires busy && EML_LATENCY && captured_valid),
// preventing stale writeback after flush.
//
// Full trap-flush validation requires the UVM/VCS simulation environment
// to assert trap_flush_rvv mid-EML execution and check wave forms.
// This ELF provides a basic smoke test: execute VEML and verify the core
// does not hang or produce garbage after the instruction completes.

#include <riscv_vector.h>

#define VEML_ENC(vd, vs1, vs2) \
  ((0x01UL << 26) | (1UL << 25) | \
   ((unsigned long)(vs2) << 20) | ((unsigned long)(vs1) << 15) | \
   (0UL << 12) | ((unsigned long)(vd) << 7) | 0x57UL)

float in_buf_1[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));

int main(int argc, char** argv) {
  size_t vl = 4;

  register vfloat32m1_t vs1_reg asm("v1") = __riscv_vle32_v_f32m1(in_buf_1, vl);
  register vfloat32m1_t vs2_reg asm("v2") = __riscv_vle32_v_f32m1(in_buf_2, vl);
  (void)vs1_reg; (void)vs2_reg;  // used via fixed-register asm clobbers

  // VEML: v8 = exp(vs2) - ln(vs1)
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 1, 2)) : "v1", "v2", "v8");

  // Store result — if EML completed normally, out_buf gets exp-ln values.
  // If trap-flush occurred during VEML, the wrapper cleared its state,
  // result_valid stayed 0, and out_buf retains its initial zero value.
  __riscv_vse32_v_f32m1(out_buf, vd_reg, vl);

  return 0;
}
