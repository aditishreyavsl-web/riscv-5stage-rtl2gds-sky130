# Self-checking RV32I test. PASS: store 1 to tohost (0xFF0); FAIL: store 0xDEAD0000|testno.
# x30 is scratch for CHECK; x29 holds the running test number.
start:
    # ---- 1. ALU + back-to-back forwarding (EX->EX, MEM->EX, WB->ID bypass)
    li   x29, 1
    li   x1, 5
    li   x2, 7
    add  x3, x1, x2
    CHECK x3, 12
    sub  x4, x1, x2
    CHECK x4, -2
    add  x5, x3, x3          # EX/MEM forward
    add  x6, x5, x3          # EX/MEM + MEM/WB forward
    CHECK x6, 36
    li   x7, 0x80000001
    sll  x8, x1, x2
    CHECK x8, 640
    srl  x9, x7, x1
    CHECK x9, 0x04000000
    sra  x10, x7, x1
    CHECK x10, 0xFC000000
    slt  x11, x4, x1         # -2 < 5 signed
    CHECK x11, 1
    sltu x12, x4, x1         # 0xFFFFFFFE < 5 unsigned? no
    CHECK x12, 0
    xor  x13, x1, x2
    CHECK x13, 2
    or   x14, x1, x2
    CHECK x14, 7
    and  x15, x1, x2
    CHECK x15, 5
    # ---- 2. immediates
    li   x29, 2
    addi x16, x1, -10
    CHECK x16, -5
    slti x17, x16, -4
    CHECK x17, 1
    sltiu x18, x16, 1
    CHECK x18, 0
    xori x19, x1, 0xF
    CHECK x19, 10
    ori  x20, x1, 0x30
    CHECK x20, 0x35
    andi x21, x20, 0x0F
    CHECK x21, 5
    slli x22, x1, 4
    CHECK x22, 80
    srli x23, x7, 28
    CHECK x23, 8
    srai x24, x7, 28
    CHECK x24, 0xFFFFFFF8
    lui  x25, 0x12345
    CHECK x25, 0x12345000
    # ---- 3. loads/stores, load-use hazard
    li   x29, 3
    li   x1, 0x100
    li   x2, 0xA1B2C3D4
    sw   x2, 0(x1)
    lw   x3, 0(x1)
    CHECK x3, 0xA1B2C3D4
    lw   x4, 0(x1)
    add  x5, x4, x0          # load-use stall
    CHECK x5, 0xA1B2C3D4
    lb   x6, 0(x1)
    CHECK x6, 0xFFFFFFD4
    lb   x6, 1(x1)
    CHECK x6, 0xFFFFFFC3
    lbu  x7, 2(x1)
    CHECK x7, 0xB2
    lbu  x7, 3(x1)
    CHECK x7, 0xA1
    lh   x8, 0(x1)
    CHECK x8, 0xFFFFC3D4
    lhu  x9, 2(x1)
    CHECK x9, 0xA1B2
    li   x10, 0x55
    sb   x10, 5(x1)
    sh   x2, 10(x1)
    lw   x11, 4(x1)
    CHECK x11, 0x5500
    lw   x12, 8(x1)
    CHECK x12, 0xC3D40000
    li   x13, 0x77
    sw   x13, 16(x1)
    lw   x14, 16(x1)         # store->load
    sw   x14, 20(x1)         # load-use on store data
    lw   x15, 20(x1)
    CHECK x15, 0x77
    # ---- 4. branches (taken / not taken, all six)
    li   x29, 4
    li   x1, -1
    li   x2, 1
    li   x3, 0
    beq  x3, x0, b1
    j    fail
b1: bne  x1, x2, b2
    j    fail
b2: blt  x1, x2, b3          # -1 < 1 signed
    j    fail
b3: bge  x2, x1, b4
    j    fail
b4: bltu x2, x1, b5          # 1 < 0xFFFFFFFF unsigned
    j    fail
b5: bgeu x1, x2, b6
    j    fail
b6: beq  x1, x2, fail        # not taken
    bne  x1, x1, fail
    blt  x2, x1, fail
    bge  x1, x2, fail
    bltu x1, x2, fail
    bgeu x2, x1, fail
    li   x4, 0
    addi x4, x4, 1           # wrong-path instrs after taken branch must be flushed
    beq  x0, x0, b7
    addi x4, x4, 100
    addi x4, x4, 100
b7: CHECK x4, 1
    # ---- 5. JAL / JALR / AUIPC
    li   x29, 5
    jal  x1, f1              # x1 = return address
    addi x5, x5, 1000        # skipped by jalr return? no: executes after return
    j    j_done
f1: li   x5, 1
    jalr x0, 0(x1)           # return
j_done:
    CHECK x5, 1001
    auipc x6, 0
    jal  x7, nxt
nxt:
    sub  x8, x7, x6          # x7 = addr(nxt)=x6+8
    CHECK x8, 8
    # ---- 6. loop: sum 1..10 and data-dependent chain
    li   x29, 6
    li   x1, 0
    li   x2, 10
lp: add  x1, x1, x2
    addi x2, x2, -1
    bnez x2, lp
    CHECK x1, 55
    # fibonacci(10) using memory
    li   x1, 0x200
    li   x2, 0
    li   x3, 1
    li   x4, 10
fb: sw   x2, 0(x1)
    add  x5, x2, x3
    mv   x2, x3
    mv   x3, x5
    addi x1, x1, 4
    addi x4, x4, -1
    bnez x4, fb
    li   x1, 0x200
    lw   x6, 36(x1)          # fib(9) = 34
    CHECK x6, 34
pass:
    li   x31, 1
    li   x30, 0xFF0
    sw   x31, 0(x30)
    j    pass
fail:
    lui  x31, 0xDEAD0
    or   x31, x31, x29
    li   x30, 0xFF0
    sw   x31, 0(x30)
    j    fail
