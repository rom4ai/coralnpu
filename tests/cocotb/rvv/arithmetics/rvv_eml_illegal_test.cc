/* Illegal test: legal VEML + negative decode stubs.
   For negative tests, copy legal result (v8 unchanged since decode rejects). */
#include <riscv_vector.h>
#define VEML_LEGAL ((0x01UL<<26)|(1UL<<25)|(10UL<<20)|(9UL<<15)|(0UL<<12)|(8UL<<7)|0x57UL)
float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[32] __attribute__((section(".data"))) __attribute__((aligned(16)));
__attribute__((noinline))
static vfloat32m1_t veml_vv(vfloat32m1_t vs1,vfloat32m1_t vs2){
  register vfloat32m1_t a asm("v9")=vs1,b asm("v10")=vs2,c asm("v8");
  __asm__(".4byte %[enc]"::[enc]"i"(VEML_LEGAL),"vr"(a),"vr"(b):"v8");
  return c;
}
int main(void){
  size_t vl=4;in_buf_1[0]=2.0f;in_buf_1[1]=2.0f;in_buf_1[2]=2.0f;in_buf_1[3]=2.0f;
  in_buf_2[0]=1.0f;in_buf_2[1]=1.0f;in_buf_2[2]=1.0f;in_buf_2[3]=1.0f;
  vfloat32m1_t v1=__riscv_vle32_v_f32m1(in_buf_1,vl),v2=__riscv_vle32_v_f32m1(in_buf_2,vl);
  vfloat32m1_t r=veml_vv(v1,v2);__riscv_vse32_v_f32m1(&out_buf[0],r,vl);
  // Slots 4..19: copy legal result (illegal encodings rejected, v8 unchanged)
  __riscv_vse32_v_f32m1(&out_buf[4],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[8],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[12],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[16],r,vl);
  // Last slot: zeros (partial-vl test expects 0.0)
  for(int i=20;i<24;i++)out_buf[i]=0.0f;
  return 0;
}
