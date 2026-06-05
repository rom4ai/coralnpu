/*
 * Copyright 2025 Google LLC
 *
 * VEML test — simple single-call, no exception handler override.
 * Matches the pattern of eml_trap_test.cc exactly.
 */

#include <riscv_vector.h>

#define VEML_ENC(vd, vs1, vs2) \
  ((0x01UL << 26) | (1UL << 25) | \
   ((unsigned long)(vs2) << 20) | ((unsigned long)(vs1) << 15) | \
   (0UL << 12) | ((unsigned long)(vd) << 7) | 0x57UL)

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));

int main(int argc, char** argv) {
  size_t vl = 4;

  for (int i = 0; i < 4; i++) {
    in_buf_1[i] = 1.0f;
    in_buf_2[i] = 2.0f;
  }

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
