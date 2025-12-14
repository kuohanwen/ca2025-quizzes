    .globl main
    .data
pass_msg: .asciz "PASS\n"
fail_msg: .asciz "FAIL\n"

    .text
main:
    addi sp, sp, -4
    sw   ra, 0(sp)
    
# Test 1: 3.0 กั 2.5 = 7.5
test1:
    li a0, 0x4040        # Input A = 3.0
    li a1, 0x4020        # Input B = 2.5
    jal ra, bf16_mul     # Output C = A * B
    li t1, 0x40F0        # Expected Output C = 7.5
    bne a0, t1, fail1
    jal ra, print_pass
    j test2
fail1:
    jal ra, print_fail

# Test 2: 0.0 กั Inf = NaN  
test2:
    li a0, 0x0000        # Input A = 0.0
    li a1, 0x7F80        # Input B = +Inf
    jal ra, bf16_mul     # Output C = A * B
    li t1, 0x7FC0        # Expected Output C = NAN
    bne a0, t1, fail2
    jal ra, print_pass
    j test3
fail2:
    jal ra, print_fail

# Test 3: 2.0 กั -1.5 = -3.0
test3:
    li a0, 0x4000        # Input A = 2.0
    li a1, 0xBFC0        # Input B = -1.5
    jal ra, bf16_mul     # Output C = A * B
    li t1, 0xC040        # Expected Output C = -3.0
    bne a0, t1, fail3
    jal ra, print_pass
    j done
fail3:
    jal ra, print_fail

print_pass:
    la a0, pass_msg
    li a7, 4
    ecall
    ret

print_fail:
    la a0, fail_msg
    li a7, 4
    ecall
    ret

done:
    lw ra, 0(sp)
    addi sp, sp, 4
    li a7, 10
    ecall

    .globl bf16_mul
bf16_mul:
    addi sp, sp, -16
    sw   s0, 0(sp)
    sw   s1, 4(sp)
    sw   s2, 8(sp)
    sw   ra, 12(sp)

# Extract sign, exponent, mantissa
    srli t0, a0, 15
    andi t0, t0, 1
    srli t1, a1, 15
    andi t1, t1, 1
    xor  s0, t0, t1           # result sign

    srli t2, a0, 7            # exp A
    andi t2, t2, 0xFF
    srli t3, a1, 7            # exp B
    andi t3, t3, 0xFF

    andi t4, a0, 0x7F         # mant A
    andi t5, a1, 0x7F         # mant B

# Step 1 กX NaN Handling (highest priority)
    li t6, 0xFF

    # A is NaN?
    beq t2, t6, check_nan_a

    # B is NaN?
    beq t3, t6, check_nan_b

    j check_inf      # no NaN ก๗ go Inf check

check_nan_a:
    bnez t4, make_nan
    j check_inf   # A=Inf but not NaN
check_nan_b:
    bnez t5, make_nan
    j check_inf

# Step 2 กX Inf Handling
check_inf:
    li t6, 0xFF

    # A = Inf
    beq t2, t6, handle_inf_a

    # B = Inf
    beq t3, t6, handle_inf_b

    j check_zero

handle_inf_a:
    # A = Inf
    beqz t3, make_nan         # Inf กั 0 = NaN  
    j make_inf

handle_inf_b:
    # B = Inf
    beqz t2, make_nan         # 0 กั Inf = NaN  
    j make_inf

# Step 3 กX Zero Handling
check_zero:
    # A == 0 ก๗ 0
    beqz t2, check_a_mant
    j check_b_zero

check_a_mant:
    beqz t4, return_zero

check_b_zero:
    # B == 0 ก๗ 0
    beqz t3, check_b_mant
    j normalize_inputs

check_b_mant:
    beqz t5, return_zero

# NaN / Inf / Zero Makers
make_nan:
    li a0, 0x7FC0
    j mul_done

make_inf:
    slli a0, s0, 15
    li t6, 0x7F80
    or a0, a0, t6
    j mul_done

return_zero:
    slli a0, s0, 15
    j mul_done

# Normalize A & B
normalize_inputs:
    mv s1, zero     # exp_adjust = 0

# Normalize A
    beqz t2, norm_a_sub
    ori t4, t4, 0x80
    j norm_b

norm_a_sub:
    beqz t4, return_zero
norm_a_loop:
    andi t6, t4, 0x80
    bnez t6, norm_a_end
    slli t4, t4, 1
    addi s1, s1, -1
    j norm_a_loop
norm_a_end:
    li t2, 1

# Normalize B
norm_b:
    beqz t3, norm_b_sub
    ori t5, t5, 0x80
    j do_mul

norm_b_sub:
    beqz t5, return_zero
norm_b_loop:
    andi t6, t5, 0x80
    bnez t6, norm_b_end
    slli t5, t5, 1
    addi s1, s1, -1
    j norm_b_loop
norm_b_end:
    li t3, 1

# Mantissa Multiply
do_mul:
    mul s2, t4, t5

    add t6, t2, t3
    addi t6, t6, -127
    add  t6, t6, s1
    mv   s1, t6

# Normalize multiplication result
    li t6, 0x8000
    and t6, s2, t6
    beqz t6, mul_norm_low

    srli s2, s2, 8
    andi s2, s2, 0x7F
    addi s1, s1, 1
    j check_exp

mul_norm_low:
    srli s2, s2, 7
    andi s2, s2, 0x7F

# Exponent Overflow / Underflow
check_exp:
    li t6, 255
    bge s1, t6, make_inf

    blez s1, return_zero

# Assemble Final BF16
final_output:
    slli a0, s0, 15
    andi s1, s1, 0xFF
    slli s1, s1, 7
    or a0, a0, s1
    or a0, a0, s2
    j mul_done

# Epilogue
mul_done:
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

