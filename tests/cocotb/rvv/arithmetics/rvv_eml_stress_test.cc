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
float out_buf[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));

// task12: Back-to-back VEML: two independent VEML ops in sequence.
// First VEML: v8,v1,v2. Second VEML: v16,v1,v2.
// Verifies RS pop works and second VEML can start after first completes.
void eml_back_to_back(const float* in_buf_1, const float* in_buf_2,
                      float* out_buf, float* out_buf_2) {
  size_t vl = 4;  // VLEN=128, SEW=32, LMUL=1

  vfloat32m1_t vs1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t vs2 = __riscv_vle32_v_f32m1(in_buf_2, vl);

  // First VEML: v8 = exp(vs2) - ln(vs1)
  register vfloat32m1_t vd1 asm("v8");
  __asm__ volatile("" : "+vr"(vs1), "+vr"(vs2));
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 1, 2)) : "v8", "v1", "v2");
  __riscv_vse32_v_f32m1(out_buf, vd1, vl);

  // Second VEML: v16 = exp(vs2) - ln(vs1) (independent operands from first)
  register vfloat32m1_t vd2 asm("v16");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(16, 1, 2)) : "v16", "v1", "v2");
  __riscv_vse32_v_f32m1(out_buf_2, vd2, vl);
}

// task13: Mixed VEML + standard ALU (VFADD) traffic.
// VEML uses 8-cycle pipeline while VFADD is single-cycle.
// Verifies no cross-contamination between EML and standard ALU results.
void eml_mixed_alu(const float* in_buf_1, const float* in_buf_2,
                   float* out_eml, float* out_fadd) {
  size_t vl = 4;

  vfloat32m1_t vs1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t vs2 = __riscv_vle32_v_f32m1(in_buf_2, vl);

  // VFADD v24 = vs1 + vs2 (standard ALU, single-cycle p0 pipeline)
  vfloat32m1_t vfadd_result = __riscv_vfadd_vv_f32m1(vs1, vs2, vl);

  // VEML v8 = exp(vs2) - ln(vs1) (EML, 8-cycle pipeline)
  register vfloat32m1_t vd_eml asm("v8");
  __asm__ volatile("" : "+vr"(vs1), "+vr"(vs2));
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 1, 2)) : "v8", "v1", "v2");

  // Store VFADD result first (should be available immediately)
  __riscv_vse32_v_f32m1(out_fadd, vfadd_result, vl);
  // Store VEML result second (8-cycle pipeline complete by now)
  __riscv_vse32_v_f32m1(out_eml, vd_eml, vl);
}

int main(int argc, char** argv) {
  eml_back_to_back(in_buf_1, in_buf_2, out_buf, out_buf);
  eml_mixed_alu(in_buf_1, in_buf_2, out_buf, out_buf);
  return 0;
}
