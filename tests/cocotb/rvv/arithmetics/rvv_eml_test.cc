/* VEML test using naked function for direct register access */
#include <stddef.h>

// Naked: no prologue, a0=out, a1=in1, a2=in2, a3=vl
__attribute__((naked))
static void veml_f32m1(void) {
  asm volatile(
    "vsetvli zero, a3, e32, m1, ta, ma\n\t"
    "vle32.v v9, (a1)\n\t"
    "vle32.v v10, (a2)\n\t"
    ".word 0x06a48457\n\t"
    "vse32.v v8, (a0)\n\t"
    "ret"
  );
}

float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));

int main(void) {
  size_t vl = 4;
  in_buf_1[0]=2.0f;in_buf_1[1]=2.0f;in_buf_1[2]=2.0f;in_buf_1[3]=2.0f;
  in_buf_2[0]=1.0f;in_buf_2[1]=1.0f;in_buf_2[2]=1.0f;in_buf_2[3]=1.0f;
  // Set up args and call the naked function
  register float *o asm("a0") = out_buf;
  register const float *i1 asm("a1") = in_buf_1;
  register const float *i2 asm("a2") = in_buf_2;
  register size_t l asm("a3") = vl;
  asm volatile("" :: "r"(o), "r"(i1), "r"(i2), "r"(l));
  veml_f32m1();
  out_buf[4] = (out_buf[0] != 0.0f) ? 1234.5f : -999.0f;
  return 0;
}
