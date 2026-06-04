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

  // VEML vd, vs1, vs2 with vm=1, funct6=000001, funct3=OPIVV=000, opcode=0x57
  // Encoding: funct6[31:26]=0x01, vm[25]=1, vs2[24:20], vs1[19:15],
  //           funct3[14:12]=0, vd[11:7], opcode[6:0]=0x57
  // Register assignment: vd=v8, vs1=v9(from input_v1), vs2=v10(from input_v2)
  //
  // Word = (funct6<<26) | (vm<<25) | (vs2<<20) | (vs1<<15) | (funct3<<12) | (vd<<7) | opcode
  //      = (0x01<<26) | (1<<25) | (10<<20) | (9<<15) | (0<<12) | (8<<7) | 0x57
  //      = 0x06a48457
#define VEML_ENC(vd, vs1, vs2) \
  ((0x01UL << 26) | (1UL << 25) | \
   ((unsigned long)(vs2) << 20) | ((unsigned long)(vs1) << 15) | \
   (0UL << 12) | ((unsigned long)(vd) << 7) | 0x57UL)

  register vfloat32m1_t vd_reg asm("v8");
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;

  // Prevent compiler from optimizing away the register assignments
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));

  // Emit VEML v8,v9,v10: funct6=1, vm=1, funct3=0, opcode=0x57
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_ENC(8, 9, 10)) : "v8");

  __riscv_vse32_v_f32m1(out_buf, vd_reg, vl);
}

int main(int argc, char** argv) {
  eml_f32m1(in_buf_1, in_buf_2, out_buf);
  return 0;
}
