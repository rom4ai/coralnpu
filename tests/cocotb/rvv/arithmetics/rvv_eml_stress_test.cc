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

// Stress tests for VEML instruction:
// - Back-to-back VEML dispatch (task12)
// - Mixed VEML + standard ALU traffic (task13)

#include <riscv_vector.h>

#define VEML_ENC(vd, vs1, vs2) \
  ((0x01UL << 26) | (1UL << 25) | \
   ((unsigned long)(vs2) << 20) | ((unsigned long)(vs1) << 15) | \
   (0UL << 12) | ((unsigned long)(vd) << 7) | 0x57UL)

float in_buf_1[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_b2b_1[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_b2b_2[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_mixed_eml[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_mixed_fadd[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));

// task12: Back-to-back VEML
static void eml_back_to_back(void) {
  size_t vl = 4;

  // Load operands into fixed registers v9, v10
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  // Force live: compiler must materialize v9, v10 before VEML
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // First VEML: v8 = exp(vs2) - ln(vs1), operands in v9,v10
  register vfloat32m1_t vd1_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 9, 10)) : "v8");
  __riscv_vse32_v_f32m1(out_b2b_1, vd1_reg, vl);

  // Force v9,v10 live again (compiler may have reused them)
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // Second VEML: v16 = exp(vs2) - ln(vs1)
  register vfloat32m1_t vd2_reg asm("v16");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(16, 9, 10)) : "v16");
  __riscv_vse32_v_f32m1(out_b2b_2, vd2_reg, vl);
}

// task13: Mixed VEML + VFADD
static void eml_mixed_alu(void) {
  size_t vl = 4;

  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // VFADD v24 = vs1 + vs2  (different dest, sources in v9,v10 preserved)
  vfloat32m1_t vfadd_result = __riscv_vfadd_vv_f32m1(vs1_reg, vs2_reg, vl);
  __riscv_vse32_v_f32m1(out_mixed_fadd, vfadd_result, vl);

  // Force v9,v10 live again before VEML
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // VEML v8 = exp(vs2) - ln(vs1)  (operands in v9,v10)
  register vfloat32m1_t vd_eml_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 9, 10)) : "v8");
  __riscv_vse32_v_f32m1(out_mixed_eml, vd_eml_reg, vl);
}

int main(int argc, char** argv) {
  eml_back_to_back();
  eml_mixed_alu();
  return 0;
}
