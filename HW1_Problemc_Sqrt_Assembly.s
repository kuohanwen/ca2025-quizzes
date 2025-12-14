    .data
pass_msg:   .asciz "Test Passed\n"
fail_msg:   .asciz "Test Failed\n"

    .text
    .globl main
    .globl bf16_sqrt

main:
    addi sp, sp, -4
    sw   ra, 0(sp)

test1:
    li   a0, 0x4080          # Input A = 4.0 
    jal  ra, bf16_sqrt       # Output C = sqrt(A)
    li   t1, 0x4000          # Expected Output C = 2.0
    bne  a0, t1, test1_fail  
    jal  ra, print_pass
    j    test2

test1_fail:
    jal  ra, print_fail
    j    test2

test2:
    li   a0, 0x7F80          # Input A = +Inf 
    jal  ra, bf16_sqrt       # Output C = sqrt(A)
    li   t1, 0x7F80          # Expected Output C = +Inf 
    bne  a0, t1, test2_fail  
    jal  ra, print_pass
    j    test3

test2_fail:
    jal  ra, print_fail
    j    test3

test3:
    li   a0, 0x0000          # Input A = +0.0 
    jal  ra, bf16_sqrt       # Output C = sqrt(A)
    li   t1, 0x0000          # Expected Output C = +0.0 
    bne  a0, t1, test3_fail
    jal  ra, print_pass
    j    program_end

test3_fail:
    jal  ra, print_fail
    j    program_end

program_end:
    lw   ra, 0(sp)
    addi sp, sp, 4
    li   a7, 10              # syscall: exit (RARS)
    ecall

print_pass:
    la   a0, pass_msg
    li   a7, 4               # print_string
    ecall
    ret

print_fail:
    la   a0, fail_msg
    li   a7, 4               # print_string
    ecall
    ret

bf16_sqrt:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)
    sw s5, 4(sp)
    sw s6, 0(sp)

    srli t0, a0, 15            # Shift right 15 
    andi t0, t0, 1             # Extract sign bit
    srli t1, a0, 7             # Shift right 7
    andi t1, t1, 0xFF          # Extract exponent (8 bits)
    andi t2, a0, 0x7F          # Extract mantissa (7 bits)

    li   t3, 0xFF
    bne  t1, t3, check_zero    # if exp != 0xFF ¡÷ not Inf/NaN
    bnez t2, return_a          # exp=0xFF, mant!=0 ¡÷ NaN, just return a (NaN propagation)
    bnez t0, return_nan        # exp=0xFF, mant=0, sign!=0 ¡÷ -Inf ¡÷ NaN
    j    return_a              # exp=0xFF, mant=0, sign=0 ¡÷ +Inf, return a

check_zero:                    # Handle zero
    or   t3, t1, t2            # if exp==0 && mant==0 ¡÷ zero
    bnez t3, check_negative
    j    return_zero

check_negative:                # Handle negative / denormals
    bnez t0, return_nan        # negative number ¡÷ NaN
    bnez t1, compute_sqrt      # if exp!=0 ¡÷ normalized ¡÷ go sqrt
    j    return_zero           # denormals are flushed to zero

compute_sqrt:
    addi s0, t1, -127          # s0 = unbiased exponent E
    ori  s1, t2, 0x80          # s1 = mantissa with implicit leading 1 (1.xxx)

    andi t3, s0, 1             # t3 = E & 1 (check odd/even)
    beqz t3, even_exp

    # odd exponent: sqrt(2^E * M) = 2^{(E-1)/2} * sqrt(2*M)
    slli s1, s1, 1             # mantissa * 2
    addi t4, s0, -1
    srai t4, t4, 1
    addi s2, t4, 127           # s2 = output exponent (biased)
    j    binary_search

even_exp:
    # even exponent: sqrt(2^E * M) = 2^{E/2} * sqrt(M)
    srai t4, s0, 1
    addi s2, t4, 127           # s2 = output exponent (biased)

binary_search:
    # Search integer y in [90,256] such that (y^2 >> 7) ? s1
    li   s3, 90                # low
    li   s4, 256               # high
    li   s5, 128               # best (initial guess)

search_loop:
    bgt  s3, s4, search_done
    add  t3, s3, s4
    srli t3, t3, 1             # mid = (low + high) / 2

    mv   a1, t3
    mv   a2, t3
    jal  ra, multiply          # a0 = mid * mid
    mv   t4, a0
    srli t4, t4, 7             # compare (mid^2 >> 7) with s1

    bgt  t4, s1, search_high   # too large ¡÷ move high
    mv   s5, t3                # accept mid as current best
    addi s3, t3, 1             # low = mid + 1
    j    search_loop

search_high:
    addi s4, t3, -1            # high = mid - 1
    j    search_loop

search_done:
    li   t3, 256
    blt  s5, t3, check_low     # if best < 256 ¡÷ normal case
    srli s5, s5, 1             # if best >= 256 ¡÷ renormalize
    addi s2, s2, 1
    j    extract_mant

check_low:
    li   t3, 128
    bge  s5, t3, extract_mant  # already normalized (>=128)

norm_loop:                     # ensure mantissa in [128,255]
    li   t3, 128
    bge  s5, t3, extract_mant
    li   t3, 1
    ble  s2, t3, extract_mant  # avoid exponent underflow
    slli s5, s5, 1
    addi s2, s2, -1
    j    norm_loop

extract_mant:
    andi s6, s5, 0x7F          # take low 7 bits as mantissa
    li   t3, 0xFF
    bge  s2, t3, return_inf    # exponent overflow ¡÷ +Inf
    blez s2, return_zero       # exponent underflow / zero
    andi t3, s2, 0xFF
    slli t3, t3, 7
    or   a0, t3, s6            # pack exponent + mantissa (sign=0)
    j    cleanup

return_zero:
    li   a0, 0x0000
    j    cleanup

return_nan:
    li   a0, 0x7FC0            # canonical quiet NaN
    j    cleanup

return_inf:
    li   a0, 0x7F80            # +Inf
    j    cleanup

return_a:
    # a0 already has original input (Inf / NaN propagation etc.)
cleanup:
    lw s6, 0(sp)
    lw s5, 4(sp)
    lw s4, 8(sp)
    lw s3, 12(sp)
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

# multiply(a1, a2) ¡÷ a0 = a1 * a2 (unsigned, shift-add)
multiply:
    li   a0, 0
    beqz a2, mult_done
mult_loop:
    andi t0, a2, 1
    beqz t0, mult_skip
    add  a0, a0, a1
mult_skip:
    slli a1, a1, 1
    srli a2, a2, 1
    bnez a2, mult_loop
mult_done:
    ret

