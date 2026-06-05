/* Stress test: back-to-back VEML + mixed VEML/VFADD.
   Data provided by Python backdoor. ELF does NOT overwrite buffers. */
#include <riscv_vector.h>
#define VEML_ENC ((0x01UL<<26)|(1UL<<25)|(10UL<<20)|(9UL<<15)|(0UL<<12)|(8UL<<7)|0x57UL)
float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_b2b_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_b2b_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_mixed_fadd[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_mixed_eml[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
__attribute__((noinline))
static vfloat32m1_t veml_vv(vfloat32m1_t vs1,vfloat32m1_t vs2){
  register vfloat32m1_t a asm("v9")=vs1,b asm("v10")=vs2,c asm("v8");
  __asm__(".4byte %[enc]"::[enc]"i"(VEML_ENC),"vr"(a),"vr"(b):"v8");
  return c;
}
int main(void){
  size_t vl=4;
  vfloat32m1_t v1=__riscv_vle32_v_f32m1(in_buf_1,vl);
  vfloat32m1_t v2=__riscv_vle32_v_f32m1(in_buf_2,vl);
  vfloat32m1_t r1=veml_vv(v1,v2);__riscv_vse32_v_f32m1(out_b2b_1,r1,vl);
  vfloat32m1_t r2=veml_vv(v1,v2);__riscv_vse32_v_f32m1(out_b2b_2,r2,vl);
  vfloat32m1_t f=__riscv_vfadd_vv_f32m1(v1,v2,vl);__riscv_vse32_v_f32m1(out_mixed_fadd,f,vl);
  vfloat32m1_t r3=veml_vv(v1,v2);__riscv_vse32_v_f32m1(out_mixed_eml,r3,vl);
  return 0;
}
