    .data
pass_msg: .asciz "PASS\n"
fail_msg: .asciz "FAIL\n"

    .text
    .globl main
main:
    addi sp, sp, -4
    sw   ra, 0(sp)

# Test 1: 6.0 / 2.0 = 3.0
test1:
    li a0, 0x40C0    # Input A = 6.0
    li a1, 0x4000    # Input B = 2.0
    jal ra, bf16_div # Output C = A / B
    li t1, 0x4040    # Expected Output C = 3.0
    bne a0, t1, fail1
    jal ra, print_pass
    j test2

fail1:
    jal ra, print_fail

# Test 2: -2.0 / 4.0 = -0.5
test2:
    li a0, 0xC000    # Input A = -2.0
    li a1, 0x4080    # Input B = 4.0
    jal ra, bf16_div # Output C = A / B
    li t1, 0xBF00    # Expected Output C = -0.5
    bne a0, t1, fail2
    jal ra, print_pass
    j test3

fail2:
    jal ra, print_fail

# Test 3: -Inf / -5.0 = +Inf
test3:
    li a0, 0xFF80    # Input A = -Inf
    li a1, 0xC0A0    # Input B = -5.0
    jal ra, bf16_div # Output C = A / B
    li t1, 0x7F80    # Expected Output C = +Inf
    bne a0, t1, fail3
    jal ra, print_pass
    j done

fail3:
    jal ra, print_fail

done:
    lw ra, 0(sp)
    addi sp, sp, 4
    li a7, 10
    ecall
    
print_pass:
    la a0, pass_msg
    li a7, 4
    ecall
    jr ra

print_fail:
    la a0, fail_msg
    li a7, 4
    ecall
    jr ra

    .globl bf16_div
bf16_div:
# Extract sign, exponent, mantissa

    srli t0, a0, 15          # sign_a
    srli t1, a1, 15          # sign_b
    xor  a2, t0, t1          # result_sign = a.sign ^ b.sign

    srli t2, a0, 7           # exp_a
    andi t2, t2, 0xFF
    srli t3, a1, 7           # exp_b
    andi t3, t3, 0xFF

    andi t4, a0, 0x7F        # mant_a
    andi t5, a1, 0x7F        # mant_b

# Special cases : NaN, Inf, Zero
    li t6, 0xFF

# B is NaN or Inf 
    beq t3, t6, check_B_inf_nan

# B is Zero ¡÷ A/0 = Inf or -Inf
    beq t3, x0, check_B_zero

    j check_A_inf_nan

# B is NaN or Inf 
check_B_inf_nan:
    bnez t5, make_nan       # B mantissa != 0 ¡÷ NaN
    # B = Inf
    beq t2, t6, make_nan    # Inf / Inf = NaN
    # finite / Inf = Zero
    j make_zero


# B == Zero 

check_B_zero:
    beq t5, x0, make_inf    # A / 0 ¡÷ ¡ÓInf
    j continue              # subnormal zero ¡÷ go normalize

# A is NaN or Inf 

check_A_inf_nan:
    beq t2, t6, A_inf_or_nan
    j continue

A_inf_or_nan:
    bnez t4, make_nan       # NaN
    # A is Inf
    j make_inf

# Continue : Normalize A & B mantissas
continue:
# Normalize A
    li s1, 0                # exp_adjust = 0
    beq t2, x0, normA_sub
    ori t4, t4, 0x80        # add hidden 1
    j normB

normA_sub:
    beq t4, x0, make_zero   # A = 0
normA_loop:
    andi t6, t4, 0x80
    bnez t6, normA_done
    slli t4, t4, 1
    addi s1, s1, -1
    j normA_loop
normA_done:
    li t2, 1

# Normalize B
normB:
    beq t3, x0, normB_sub
    ori t5, t5, 0x80
    j divide_start

normB_sub:
    beq t5, x0, make_zero   # B=0 case already handled above
normB_loop:
    andi t6, t5, 0x80
    bnez t6, normB_done
    slli t5, t5, 1
    addi s1, s1, -1
    j normB_loop
normB_done:
    li t3, 1

# Long Division 16-bit
divide_start:

    slli a4, t4, 15         # dividend <<= 15
    li   a5, 0              # quotient = 0

    mv   t6, t5             # divisor working copy
    slli t6, t6, 15

    li t0, 16

div_loop:
    slli a5, a5, 1          # shift quotient left

    sltu t1, a4, t6         # if dividend < divisor
    bne  t1, x0, div_skip

    sub a4, a4, t6          # dividend -= divisor
    ori a5, a5, 1           # quotient bit = 1

div_skip:
    srli t6, t6, 1          # divisor >>= 1
    addi t0, t0, -1
    bne t0, x0, div_loop

# Compute exponent

    sub a3, t2, t3
    addi a3, a3, 127

    beq t2, x0, decA
    j adjustB
decA:
    addi a3, a3, -1

adjustB:
    beq t3, x0, incB
    j normalize_q
incB:
    addi a3, a3, 1

# Normalize quotient (mantissa)
normalize_q:
    li t0, 0x8000
    and t1, a5, t0
    bnez t1, shift8

# Shift left until top bit=1
norm_q_loop:
    and t1, a5, t0
    bnez t1, shift8
    slli a5, a5, 1
    addi a3, a3, -1
    j norm_q_loop

shift8:
    srli a5, a5, 8

# Assemble final BF16

    andi a5, a5, 0x7F

    li t0, 255
    bge a3, t0, make_inf
    ble a3, x0, make_zero

    andi t0, a3, 255
    slli t0, t0, 7

    slli a0, a2, 15
    or a0, a0, t0
    or a0, a0, a5
    jr ra

# Special return paths
make_zero:
    slli a0, a2, 15
    jr ra

make_inf:
    slli a0, a2, 15
    li t0, 0x7F80
    or a0, a0, t0
    jr ra

make_nan:
    li a0, 0x7FC0
    jr ra
