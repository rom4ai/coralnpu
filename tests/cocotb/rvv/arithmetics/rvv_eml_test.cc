/* VEML: proper function call with compiler-aware register binding */
#include <riscv_vector.h>

#define VEML_ENC ((0x01UL<<26)|(1UL<<25)|(10UL<<20)|(9UL<<15)|(0UL<<12)|(8UL<<7)|0x57UL)

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));

// Emit VEML with fixed registers inside a noinline function.
// Caller passes operands, function copies to v9/v10, emits VEML,
// returns result from v8.
__attribute__((noinline))
static vfloat32m1_t veml_vv(vfloat32m1_t vs1, vfloat32m1_t vs2) {
  register vfloat32m1_t a asm("v9") = vs1;
  register vfloat32m1_t b asm("v10") = vs2;
  register vfloat32m1_t c asm("v8");
  __asm__ __volatile__(
    ".4byte %[enc]"
    : "=vr"(c)
    : [enc] "i"(VEML_ENC), "vr"(a), "vr"(b)
  );
  return c;
}

int main(void) {
  size_t vl = 4;
  in_buf_1[0] = 2.0f; in_buf_1[1] = 2.0f; in_buf_1[2] = 2.0f; in_buf_1[3] = 2.0f;
  in_buf_2[0] = 1.0f; in_buf_2[1] = 1.0f; in_buf_2[2] = 1.0f; in_buf_2[3] = 1.0f;

  vfloat32m1_t v1 = __riscv_vle32_v_f32m1(in_buf_1, vl);
  vfloat32m1_t v2 = __riscv_vle32_v_f32m1(in_buf_2, vl);
  vfloat32m1_t result = veml_vv(v1, v2);
  __riscv_vse32_v_f32m1(out_buf, result, vl);

  out_buf[4] = (out_buf[0] != 0.0f) ? 1234.5f : -999.0f;
  return 0;
}
