/* VEML with vsetvl barrier between VEML and VSE32.
 * vsetvl serializes the vector pipeline, ensuring VEML retires first. */
#include <riscv_vector.h>

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));

#define VEML_ENC ((0x01UL<<26)|(1UL<<25)|(10UL<<20)|(9UL<<15)|(0UL<<12)|(8UL<<7)|0x57UL)

int main(void) {
  size_t vl = 4;
  in_buf_1[0]=2.0f; in_buf_1[1]=2.0f; in_buf_1[2]=2.0f; in_buf_1[3]=2.0f;
  in_buf_2[0]=1.0f; in_buf_2[1]=1.0f; in_buf_2[2]=1.0f; in_buf_2[3]=1.0f;

  // Load data and bind to fixed registers
  vfloat32m1_t v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  register vfloat32m1_t a asm("v9") = v1;
  register vfloat32m1_t b asm("v10") = v2;

  // Emit VEML with register constraints
  register vfloat32m1_t c asm("v8");
  __asm__ volatile(
    ".4byte %[enc]"
    : "=vr"(c)
    : [enc] "i"(VEML_ENC), "vr"(a), "vr"(b)
    : "memory"
  );

  // BARRIER: vsetvl serializes the vector pipeline
  // All pending vector writes (including VEML to v8) are complete after this
  vl = __riscv_vsetvl_e32m1(vl);

  // Now VEML has retired — v8 contains the result
  __riscv_vse32_v_f32m1(out_buf, c, vl);

  out_buf[4] = (out_buf[0] != 0.0f) ? 1234.5f : -999.0f;
  return 0;
}
