/* Illegal test — same pattern as eml_vv_test */
#include <riscv_vector.h>
float in_buf_1[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float in_buf_2[16] __attribute__((section(".data"))) __attribute__((aligned(16)));
float out_buf[32] __attribute__((section(".data"))) __attribute__((aligned(16)));
__attribute__((noinline))
static vfloat32m1_t veml_vv(vfloat32m1_t vs1,vfloat32m1_t vs2){
  register vfloat32m1_t c asm("v8"),a asm("v9"),b asm("v10");
  __asm__("vmv.v.v v9,%[s1]\n\tvmv.v.v v10,%[s2]\n\t.word 0x06a48457"
    :"=vr"(c),"=vr"(a),"=vr"(b):[s1]"vr"(vs1),[s2]"vr"(vs2));
  return c;
}
int main(void){
  size_t vl=4;
  vfloat32m1_t v1=__riscv_vle32_v_f32m1(in_buf_1,vl);
  vfloat32m1_t v2=__riscv_vle32_v_f32m1(in_buf_2,vl);
  vfloat32m1_t r=veml_vv(v1,v2);
  __riscv_vse32_v_f32m1(&out_buf[0],r,vl);
  // Copy to remaining slots for negative-test stubs
  __riscv_vse32_v_f32m1(&out_buf[4],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[8],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[12],r,vl);
  __riscv_vse32_v_f32m1(&out_buf[16],r,vl);
  for(int i=20;i<24;i++)out_buf[i]=0.0f;
  return 0;
}
