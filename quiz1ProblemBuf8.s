.data

# offset(e) = 16*(2^e - 1), e=0..15
offset_tbl:
    .word 0,16,48,112,240,496,1008,2032
    .word 4080,8176,16368,32752,65520,131056,262128,524272
    
msg1:    .asciz ": decodes to "
msg2:    .asciz " but re-encodes as "
msg3:    .asciz ": decoded is "
msg4:    .asciz " <= previous value "
msg5:    .asciz "All tests passed.\n"
msg6:    .asciz "At least one test failed.\n"
newline: .asciz "\n"

    .align 2
    .text
    .globl main

# ---------------- main ----------------
main:
    jal   ra, test               # start test
    beq   a0, x0, Not_pass       # failed
    la    a0, msg5               # print msg5 when passing
    li    a7, 4
    ecall
    li    a7, 10                 # ecall: exit
    li    a0, 0                  # exit code 0 (success)
    ecall

Not_pass:
    la    a0, msg6               # print msg6 when not passing
    li    a7, 4
    ecall
    li    a7, 10                 # ecall: exit
    li    a0, 1                  # exit code 1 (failure)
    ecall

# ---------------- test (ABI-correct) ----------------
test:
    addi  sp, sp, -32
    sw    ra, 28(sp)
    sw    s0, 24(sp)
    sw    s1, 20(sp)
    sw    s2, 16(sp)
    sw    s3, 12(sp)
    sw    s4,  8(sp)
    sw    s5,  4(sp)

    addi  s0, x0, -1             # previous_value
    li    s1, 1                  # passed = true
    li    s2, 0                  # fl (0..255)
    li    s3, 256                # loop end

For_2:
    add   a0, s2, x0             # a0 = fl
    jal   ra, uf8_decode
    add   s4, a0, x0             # value
    add   a0, s4, x0             # a0 = value
    jal   ra, uf8_encode
    add   s5, a0, x0             # fl2

# (A) round-trip check
test_if_1:
    beq   s2, s5, test_if_2
    add   a0, s2, x0             # print fl (hex)
    li    a7, 34
    ecall
    la    a0, msg1
    li    a7, 4
    ecall
    add   a0, s4, x0             # print value (decimal)
    li    a7, 1
    ecall
    la    a0, msg2
    li    a7, 4
    ecall
    add   a0, s5, x0             # print fl2 (hex)
    li    a7, 34
    ecall
    la    a0, newline
    li    a7, 4
    ecall
    li    s1, 0                  # passed = false

# (B) strict monotonic increase
test_if_2:
    blt   s0, s4, after_if
    add   a0, s2, x0
    li    a7, 34
    ecall
    la    a0, msg3
    li    a7, 4
    ecall
    add   a0, s4, x0
    li    a7, 1
    ecall
    la    a0, msg4
    li    a7, 4
    ecall
    add   a0, s0, x0
    li    a7, 34
    ecall
    la    a0, newline
    li    a7, 4
    ecall
    li    s1, 0

after_if:
    add   s0, s4, x0
    addi  s2, s2, 1
    blt   s2, s3, For_2

    add   a0, s1, x0             # return passed (1/0)
    lw    ra, 28(sp)
    lw    s0, 24(sp)
    lw    s1, 20(sp)
    lw    s2, 16(sp)
    lw    s3, 12(sp)
    lw    s4,  8(sp)
    lw    s5,  4(sp)
    addi  sp, sp, 32
    jr    ra

# =========================================================
#             CLZ (fixed 16/8/4/2/1; clz(0)=32)
# =========================================================
CLZ:
    beq   a0, x0, CLZ_ZERO
    li    t0, 0                  # bitlen-1 accumulator

    srli  t1, a0, 16
    beq   t1, x0, CLZ_1
    addi  t0, t0, 16
    add   a0, t1, x0
CLZ_1:
    srli  t1, a0, 8
    beq   t1, x0, CLZ_2
    addi  t0, t0, 8
    add   a0, t1, x0
CLZ_2:
    srli  t1, a0, 4
    beq   t1, x0, CLZ_3
    addi  t0, t0, 4
    add   a0, t1, x0
CLZ_3:
    srli  t1, a0, 2
    beq   t1, x0, CLZ_4
    addi  t0, t0, 2
    add   a0, t1, x0
CLZ_4:
    srli  t1, a0, 1
    beq   t1, x0, CLZ_5
    addi  t0, t0, 1
CLZ_5:
    li    t1, 31
    sub   a0, t1, t0            # clz = 31 - (bitlen-1)
    jr    ra
CLZ_ZERO:
    li    a0, 32
    jr    ra

# =========================================================
#                uf8_decode (lookup-table version)
# =========================================================
# a0 = uf8 code -> a0 = decoded integer
uf8_decode:
    andi  t0, a0, 0x0F          # m
    srli  t1, a0, 4             # e
    la    t2, offset_tbl
    slli  t3, t1, 2             # index = e * 4 (word offset)
    add   t2, t2, t3
    lw    t2, 0(t2)             # t2 = offset(e)
    sll   t0, t0, t1            # m << e
    add   a0, t0, t2            # value = offset + (m << e)
    jr    ra

# =========================================================
#                uf8_encode (CLZ + pow2 loop offset)
# =========================================================
# a0 = value -> a0 = uf8 code
uf8_encode:
    addi  sp, sp, -4
    sw    ra, 0(sp)
    add   t6, a0, x0            # t6 = value

    # Small values: exact (e=0)
    li    t0, 16
    blt   t6, t0, UF8ENC_RET    # a0 already holds value

    # e = floor_log2( (value + 16) >> 4 ) = 31 - clz(t)
    addi  t1, t6, 16
    srli  t1, t1, 4
    add   a0, t1, x0
    jal   ra, CLZ
    li    t2, 31
    sub   t2, t2, a0            # t2 = e

    # clamp e to 15
    li    t0, 15
    blt   t2, t0, 1f
    li    t2, 15
1:
    # Build pow2 = (1 << e) using a small loop (adds up to e iterations)
    li    t3, 1                 # t3 = pow2
    add   t1, t2, x0            # t1 = e (loop counter)
2:
    beq   t1, x0, 3f
    slli  t3, t3, 1             # pow2 <<= 1
    addi  t1, t1, -1
    j     2b
3:
    # off = ((1 << e) - 1) << 4
    addi  t3, t3, -1
    slli  t3, t3, 4             # t3 = off

    # m = (value - off) >> e  (single shift; then saturate)
    sub   t4, t6, t3
    srl   t4, t4, t2
    li    t0, 15
    blt   t4, t0, 4f
    li    t4, 15
4:
    slli  t5, t2, 4
    or    a0, t5, t4            # a0 = (e<<4) | m

UF8ENC_RET:
    lw    ra, 0(sp)
    addi  sp, sp, 4
    jr    ra
