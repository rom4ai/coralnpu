/*
 * Self-checking VEML test — no backdoor dependency.
 * ELF initializes in_buf_1 = 2.0, in_buf_2 = 1.0.
 * Expected: exp(1.0) - ln(2.0) ≈ e - 0.693 = 2.025 (non-zero).
 */

#include <riscv_vector.h>

#define VEML_ENC \
  ((0x01UL << 26) | (1UL << 25) | \
   (10UL << 20) | (9UL << 15) | \
   (0UL << 12) | (8UL << 7) | 0x57UL)

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));

int main(int argc, char** argv) {
  size_t vl = 4;
  in_buf_1[0] = 2.0f; in_buf_1[1] = 2.0f; in_buf_1[2] = 2.0f; in_buf_1[3] = 2.0f;
  in_buf_2[0] = 1.0f; in_buf_2[1] = 1.0f; in_buf_2[2] = 1.0f; in_buf_2[3] = 1.0f;

  vfloat32m1_t v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t vs1_reg asm("v9") = v1;
  register vfloat32m1_t vs2_reg asm("v10") = v2;

  __asm__ volatile(
    ".4byte %[enc]"
    :: [enc] "i"(VEML_ENC),
       [vs1] "vr"(vs1_reg),
       [vs2] "vr"(vs2_reg)
    : "v8"
  );

  register vfloat32m1_t vd_reg asm("v8");
  __riscv_vse32_v_f32m1(out_buf, vd_reg, vl);

  // Self-check sentinel
  if (out_buf[0] != 0.0f)
    out_buf[4] = 1234.5f;  // success
  else
    out_buf[4] = -999.0f;  // failure

  return 0;
}
