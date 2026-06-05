# VEML instruction helper — proper register allocation via function call ABI
# void veml_f32m1(float *vd, const float *vs1, const float *vs2, size_t vl)
# 
# Calculates vd[i] = exp(vs2[i]) - ln(vs1[i]) for vl elements (SEW=32, LMUL=1)
# 
# Calling convention (RISC-V ILP32/ILP64, HW vector):
#   a0 = vd (output buffer)
#   a1 = vs1 (input buffer for ln)
#   a2 = vs2 (input buffer for exp)
#   a3 = vl (vector length)

.section .text
.global veml_f32m1
.type veml_f32m1, @function

veml_f32m1:
    # Configure vector unit: SEW=32, LMUL=1
    vsetvli zero, a3, e32, m1, ta, ma

    # Load operands into v9, v10
    vle32.v v9, (a1)     # vs1 = buffer for ln input
    vle32.v v10, (a2)    # vs2 = buffer for exp input

    # VEML v8, v9, v10
    # Encoding: funct6=000001, vm=1, vs2=v10, vs1=v9, funct3=OPIVV=0, vd=v8, opcode=0x57
    .word 0x06a48457

    # Store result from v8
    vse32.v v8, (a0)

    ret
