/*
 * Copyright 2025 Google LLC
 * Licensed under the Apache License, Version 2.0.
 *
 * Negative decode tests for VEML: each test in a separate function
 * to avoid register binding conflicts with inline assembly.
 */

#include <riscv_vector.h>

#define VEML_LEGAL \
  ((0x01UL << 26) | (1UL << 25) |    \
   (10UL << 20) | (9UL << 15) |      \
   (0UL << 12) | (8UL << 7) | 0x57UL)
#define VEML_MASKED \
  ((0x01UL << 26) | (0UL << 25) |    \
   (10UL << 20) | (9UL << 15) |      \
   (0UL << 12) | (8UL << 7) | 0x57UL)
#define VEML_OPIVX \
  ((0x01UL << 26) | (1UL << 25) |    \
   (10UL << 20) | (9UL << 15) |      \
   (3UL << 12) | (8UL << 7) | 0x57UL)

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[32] __attribute__((section(".data"))) __attribute__((aligned(16)));

__attribute__((noinline))
static void test_legal(size_t vl, float *out) {
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_LEGAL) : "v8");
  __riscv_vse32_v_f32m1(out, vd_reg, vl);
}

__attribute__((noinline))
static void test_masked(size_t vl, float *out) {
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_MASKED) : "v8");
  __riscv_vse32_v_f32m1(out, vd_reg, vl);
}

__attribute__((noinline))
static void test_opivx(size_t vl, float *out) {
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_OPIVX) : "v8");
  __riscv_vse32_v_f32m1(out, vd_reg, vl);
}

__attribute__((noinline))
static void test_sew8(size_t vl, float *out) {
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  vl = __riscv_vsetvl_e8m1(vl);
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_LEGAL) : "v8");
  vl = __riscv_vsetvl_e32m1(vl);
  __riscv_vse32_v_f32m1(out, vd_reg, vl);
}

__attribute__((noinline))
static void test_sew16(size_t vl, float *out) {
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  vl = __riscv_vsetvl_e16m1(vl);
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_LEGAL) : "v8");
  vl = __riscv_vsetvl_e32m1(vl);
  __riscv_vse32_v_f32m1(out, vd_reg, vl);
}

__attribute__((noinline))
static void test_partial_vl(size_t vl, float *out) {
  size_t vl2 = __riscv_vsetvl_e32m1(vl);
  vfloat32m1_t input_v1 = __riscv_vle32_v_f32m1(in_buf_1, vl2);
  vfloat32m1_t input_v2 = __riscv_vle32_v_f32m1(in_buf_2, vl2);
  register vfloat32m1_t vs1_reg asm("v9") = input_v1;
  register vfloat32m1_t vs2_reg asm("v10") = input_v2;
  __asm__ volatile("" : "+vr"(vs1_reg), "+vr"(vs2_reg));
  register vfloat32m1_t vd_reg asm("v8");
  __asm__ volatile(".4byte %0\n\t" :: "i"(VEML_LEGAL) : "v8");
  __riscv_vse32_v_f32m1(out, vd_reg, vl2);
}

int main(int argc, char** argv) {
  size_t vl = 4;
  for (int i = 0; i < 4; i++) { in_buf_1[i] = 1.0f; in_buf_2[i] = 2.0f; }

  test_legal(vl, &out_buf[0]);
  test_masked(vl, &out_buf[4]);
  test_opivx(vl, &out_buf[8]);
  test_sew8(vl, &out_buf[12]);
  test_sew16(vl, &out_buf[16]);
  test_partial_vl(2, &out_buf[20]);

  return 0;
}
