    .text
    .globl bf16_isnan
bf16_isnan:
    # a0: bf16 bits, return 1 if NaN, else 0
    li      t0, 0x7FFF          # clear sign
    and     t1, a0, t0          # t1 = |x|
    li      t2, 0x7F80          # |Inf|
    sltu    a0, t2, t1          # a0 = (|x| > |Inf|)
    ret


    .globl bf16_isinf
bf16_isinf:
    # a0: bf16 bits, return 1 if ¡ÓInf, else 0
    li      t0, 0x7FFF
    and     t1, a0, t0          # t1 = |x|
    li      t2, 0x7F80          # |Inf|
    xor     t1, t1, t2
    seqz    a0, t1              # a0 = 1 if equal
    ret


    .globl bf16_iszero
bf16_iszero:
    # a0: bf16 bits, return 1 if ¡Ó0, else 0
    li      t0, 0x7FFF
    and     t1, a0, t0          # drop sign
    seqz    a0, t1
    ret


    .globl f32_to_bf16
f32_to_bf16:
    # a0: f32 bits, return bf16 bits in a0
    srli    t0, a0, 23
    andi    t0, t0, 0xFF        # exponent
    addi    t0, t0, -255        # exponent - 0xFF
    bnez    t0, f32_unspecial

    # exponent == 0xFF: Inf or NaN, just truncate
    srli    a0, a0, 16
    ret

f32_unspecial:
    # round to nearest even when truncating to bf16
    srli    t0, a0, 16
    andi    t0, t0, 1           # bit16 (LSB of discarded part)
    li      t1, 0x7FFF
    add     t0, t0, t1          # 0x7FFF or 0x8000
    add     a0, a0, t0
    srli    a0, a0, 16
    ret


    .globl bf16_to_f32
bf16_to_f32:
    # a0: bf16 bits, return f32 bits
    slli    a0, a0, 16
    ret


    .globl BF16_NAN
BF16_NAN:
    # return quiet NaN (bf16)
    li      a0, 0x7FC0
    ret


    .globl BF16_ZERO
BF16_ZERO:
    # return +0 (bf16)
    li      a0, 0x0000
    ret
   
