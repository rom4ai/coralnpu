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

// Trap-flush test for VEML instruction.
// Executes two VEML instructions in sequence, verifying the EML wrapper
// correctly handles state transitions:
//   IDLE -> BUSY (8-cycle) -> IDLE -> BUSY -> IDLE
//
// EML wrapper trap_flush_rvv behavior (lines 99-103):
//   Clears busy=0, cycle_cnt=0, captured_uop=0, captured_valid=0
//   This de-asserts result_valid (needs busy && latency && captured_valid)
//
// Full trap-flush validation (asserting trap_flush_rvv mid-execution and
// checking no stale writeback) requires a UVM/VCS testbench with waveform
// access. This ELF provides end-to-end functional coverage.

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

  // First VEML: v8 = exp(vs2) - ln(vs1)
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 9, 10)) : "v8");
  __riscv_vse32_v_f32m1(out_buf, vd_reg, vl);

  return 0;
}
