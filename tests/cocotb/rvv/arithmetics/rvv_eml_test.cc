/* VADD via .4byte self-check: in_buf_1=2.0, in_buf_2=1.0, VADD=3.0 */
#include <riscv_vector.h>
#define VADD_ENC ((0x00UL<<26)|(1UL<<25)|(10UL<<20)|(9UL<<15)|(0UL<<12)|(8UL<<7)|0x57UL)
float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
int main(void){
  size_t vl=4;in_buf_1[0]=2.0f;in_buf_1[1]=2.0f;in_buf_1[2]=2.0f;in_buf_1[3]=2.0f;
  in_buf_2[0]=1.0f;in_buf_2[1]=1.0f;in_buf_2[2]=1.0f;in_buf_2[3]=1.0f;
  vfloat32m1_t v1=__riscv_vle32_v_f32m1(in_buf_1,vl);
  vfloat32m1_t v2=__riscv_vle32_v_f32m1(in_buf_2,vl);
  register vfloat32m1_t a asm("v9")=v1,b asm("v10")=v2;
  __asm__(".4byte %[enc]"::[enc]"i"(VADD_ENC),[v9]"vr"(a),[v10]"vr"(b):"v8");
  register vfloat32m1_t c asm("v8"); __riscv_vse32_v_f32m1(out_buf,c,vl);
  out_buf[4]=(out_buf[0]==3.0f)?1234.5f:-999.0f; return 0;
}
