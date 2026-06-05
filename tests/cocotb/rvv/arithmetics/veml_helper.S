# VEML instruction helper — calls the custom hardware operation
# void veml_f32m1(void *vd, const void *vs1, const void *vs2, size_t vl)
# 
# Register mapping: vs1=v9, vs2=v10, vd=v8
# Encoding: funct6=000001, vm=1, funct3=000(OPIVV), opcode=0x57

.section .text
.global veml_f32m1
.type veml_f32m1, @function

veml_f32m1:
    # Set vector length from a4
    vsetvli zero, a4, e32, m1, ta, ma

    # Load operands
    vle32.v v9, (a1)    # vs1
    vle32.v v10, (a2)   # vs2

    # Execute VEML
    .word 0x06a48457    # VEML v8, v9, v10

    # Store result
    vse32.v v8, (a0)

    ret
