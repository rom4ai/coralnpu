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

// EML (Element-wise Math Library) test for VEML instruction.
// VEML: funct6=000001, funct3=OPIVV=000, opcode=0x57
// Computes exp(vs2) - ln(vs1) per FP32 element via 8-cycle EMLUnit pipeline.

#include <riscv_vector.h>

float in_buf_1[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data")))
    __attribute__((aligned(16)));

void eml_f32m1(const float* in_buf_1, const float* in_buf_2, float* out_buf) {
  size_t vl = 4;  // VLEN=128, SEW=32, LMUL=1

  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);

  // VEML vd, vs1, vs2 with vm=1, funct6=000001, funct3=000, opcode=0x57
  // Encoding: funct6[31:26]=0x01, vm[25]=1, vs2[24:20], vs1[19:15],
  //           funct3[14:12]=0, vd[11:7], opcode[6:0]=0x57
  // Use .4byte to emit raw encoding with explicit register assignments.
  // Register v8=vd, v9=vs1(from input_v1), v10=vs2(from input_v2)
  register vfloat32m1_t vd_reg asm("v8");
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;

  // Prevent the compiler from optimizing away the register assignments
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // Emit VEML: vd=v8, vs1=v9, vs2=v10
  // 32-bit encoding = {funct6=0x01, vm=1, vs2=10, vs1=9, funct3=0, vd=8, opcode=0x57}
  // = 0b 000001 1 01010 01001 000 01000 1010111
  // = 0x05494457
  __asm__ volatile(".4byte 0x05494457\n\t" : "=vr"(vd_reg) : "vr"(vs1_reg), "vr"(vs2_reg));

  __riscv_vse32_v_f32m1(out_buf, vd_reg, vl);
}

int main(int argc, char** argv) {
  eml_f32m1(in_buf_1, in_buf_2, out_buf);
  return 0;
}
