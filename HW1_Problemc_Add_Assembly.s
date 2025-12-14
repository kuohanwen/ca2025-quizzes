    .data
newline:    .string "\n"
pass_msg:   .asciz "Test Passed\n"
fail_msg:   .asciz "Test Failed\n"
    .text
    .globl main
main:
    addi sp, sp, -4
    sw   ra, 0(sp)

test1:
    # Test 1.0 + 2.0 = 3.0
    li   a0, 0x3F80          # Input A = 1.0
    li   a1, 0x4000          # Input B = 2.0
    jal  ra, bf16_add        # Output C = A + B
    li   t1, 0x4040          # Expected Output C = 3.0
    bne  a0, t1, test1_fail
    jal  ra, print_pass
    j    test2
test1_fail:
    jal  ra, print_fail
    j    test2

test2:
    # Test -1.5 + 0.5 = -1.0
    li   a0, 0xBFC0          # Input A = -1.5
    li   a1, 0x3F00          # Input B = 0.5
    jal  ra, bf16_add        # Output C = A + B
    li   t1, 0xBF80          # Expected Output C = -1.0
    bne  a0, t1, test2_fail
    jal  ra, print_pass
    j    test3
test2_fail:
    jal  ra, print_fail
    j    test3

test3:
    # Test -Inf + 5.0 = -Inf
    li   a0, 0xFF80          # Input A = -Inf
    li   a1, 0x40A0          # Input B = 5.0
    jal  ra, bf16_add        # Output C = A + B
    li   t1, 0xFF80          # Expected Output C = -Inf
    bne  a0, t1, test3_fail
    jal  ra, print_pass
    j    tests_done
test3_fail:
    jal  ra, print_fail
    j    tests_done
print_pass:
    la   a0, pass_msg
    li   a7, 4               # syscall: print string
    ecall
    jr   ra
print_fail:
    la   a0, fail_msg
    li   a7, 4               # syscall: print string
    ecall
    jr   ra
tests_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    li   a7, 10              # syscall: exit
    ecall

    .globl bf16_add
bf16_add:
    # extract sign, exponent, mantissa
    srli t0, a0, 15          # t0 = sign_a (bit 15)
    srli t1, a1, 15          # t1 = sign_b
    srli t2, a0, 7
    andi t2, t2, 0xFF        # t2 = exp_a (8 bits)
    srli t3, a1, 7
    andi t3, t3, 0xFF        # t3 = exp_b
    andi t4, a0, 0x7F        # t4 = mant_a (7 bits)
    andi t5, a1, 0x7F        # t5 = mant_b (7 bits)
    li   t6, 0xFF
    bne  t2, t6, check_exp_b
exp_a_checkall:
    bnez t4, ret_a           # mant_a != 0 ¡÷ a is NaN, return a
    bne  t3, t6, ret_a       # a is Inf, b is finite ¡÷ return a
    bnez t5, return_b1       # b mantissa != 0 ¡÷ b is NaN
    bne  t0, t1, return_nan  # +Inf + -Inf ¡÷ NaN
return_b1:
    mv   a0, a1              # b is NaN or same-sign Inf
    ret
return_nan:
    li   a0, 0x7FC0          # canonical NaN
ret_a:
    ret
check_exp_b:
    beq  t3, t6, return_b2
    j    check_0_a
return_b2:
    mv   a0, a1              # b is NaN or Inf
    ret
check_0_a:
    bnez t2, check_0_b       # exp_a != 0 ¡÷ not zero
    bnez t4, check_0_b       # mant_a != 0 ¡÷ not zero
    mv   a0, a1              # a is ¡Ó0 ¡÷ result = b
    ret
check_0_b:
    bnez t3, norm_a
    bnez t5, norm_a
    ret                      # b is ¡Ó0 ¡÷ result = a (a0)
norm_a:
    beqz t2, norm_b          # exp_a == 0 ¡÷ subnormal
    ori  t4, t4, 0x80        # mant_a |= 1 << 7 (restore hidden bit)
norm_b:
    beqz t3, end_check1
    ori  t5, t5, 0x80        # mant_b |= 1 << 7 (restore hidden bit)
end_check1:
    addi sp, sp, -20
    sw   s0, 16(sp)
    sw   s1, 12(sp)
    sw   s2,  8(sp)
    sw   s3,  4(sp)
    sw   s4,  0(sp)
    sub  s0, t2, t3          # s0 = exp_diff = exp_a - exp_b
    blez s0, diff_neg        # exp_a <= exp_b
    mv   s2, t2              # result_exp = exp_a
    li   t6, 8
    bgt  s0, t6, return_a    # if exp_diff > 8 ¡÷ B too small
    srl  t5, t5, s0          # shift mant_b
    j    exp_done
diff_neg:
    bgez s0, diff_else       # exp_diff == 0
    mv   s2, t3              # result_exp = exp_b
    li   t6, -8
    bge  s0, t6, shift_a     # if exp_diff >= -8 ¡÷ shift A
    j    return_b3           # else A too small ¡÷ result ? B
shift_a:
    neg  s4, s0              # s4 = -exp_diff
    srl  t4, t4, s4          # shift mant_a
    j    exp_done
diff_else:                   # exp_diff == 0
    mv   s2, t2
    j    exp_done
return_a:
    # a0 is already A ¡÷ return A directly
    j    bf16_epilogue

return_b3:
    # result = B
    mv   a0, a1
    j    bf16_epilogue

exp_done:
    bne  t0, t1, diff_sign   # sign differ ¡÷ subtraction
same_sign:
    mv   s1, t0              # result_sign
    add  s3, t4, t5          # result_mant = mant_a + mant_b
    andi t6, s3, 0x100       # overflow into bit 8?
    beqz t6, norm_end
    srli s3, s3, 1           # shift mantissa right
    addi s2, s2, 1           # exponent++
    li   t6, 0xFF
    bge  s2, t6, overflow_inf
    j    norm_end

overflow_inf:
    # a0 = ¡ÓInf
    slli a0, s1, 15          # sign
    li   t6, 0x7F80          # Inf exponent (exp=0xFF, mant=0)
    or   a0, a0, t6
    j    bf16_epilogue

diff_sign:
    bge  t4, t5, manta_gt_b
    mv   s1, t1              # result_sign = sign_b
    sub  s3, t5, t4          # mant_b - mant_a
    j    mant_result
manta_gt_b:
    mv   s1, t0              # result_sign = sign_a
    sub  s3, t4, t5          # mant_a - mant_b
mant_result:
    beqz s3, return_zero     # exact zero
norm_loop:
    andi t6, s3, 0x80
    bnez t6, norm_end
    slli s3, s3, 1
    addi s2, s2, -1
    blez s2, return_zero
    j    norm_loop

norm_end:
    # reconstruct BF16: sign | exponent | mantissa
    slli a0, s1, 15          # sign
    andi t0, s2, 0xFF
    slli t0, t0, 7           # exponent
    or   a0, a0, t0
    andi t0, s3, 0x7F        # mantissa
    or   a0, a0, t0
    j    bf16_epilogue

return_zero:
    li   a0, 0x0000          # +0

bf16_epilogue:
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20
    ret

