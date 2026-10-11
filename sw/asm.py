#!/usr/bin/env python3
"""Minimal RV32I assembler -> $readmemh hex (one 32-bit word per line).

Supports: all RV32I base integer instructions (except FENCE/ECALL/EBREAK/CSR),
labels, ABI register names, pseudo-ops: nop, li, mv, j, ret, not, neg, beqz, bnez,
and one test helper:  CHECK rd, imm   ->  li x30, imm ; bne rd, x30, fail
(`li` always expands to LUI+ADDI so label addresses are stable.)

usage: asm.py prog.S out.hex
"""
import re, sys

ABI = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
       'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
       's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
       't3':28,'t4':29,'t5':30,'t6':31}
def reg(s):
    s = s.strip()
    if s in ABI: return ABI[s]
    m = re.fullmatch(r'x(\d+)', s)
    if m and int(m.group(1)) < 32: return int(m.group(1))
    raise ValueError(f'bad register {s!r}')

R = {'add':(0,0),'sub':(0,0x20),'sll':(1,0),'slt':(2,0),'sltu':(3,0),'xor':(4,0),
     'srl':(5,0),'sra':(5,0x20),'or':(6,0),'and':(7,0)}
I = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SH = {'slli':(1,0),'srli':(5,0),'srai':(5,0x20)}
L = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
S = {'sb':0,'sh':1,'sw':2}
B = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v
def enc_r(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm,rs1,f3,rd,op):
    assert -2048 <= imm < 2048, f'imm12 out of range: {imm}'
    return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm,rs2,rs1,f3,op):
    assert -2048 <= imm < 2048
    imm &= 0xfff
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def enc_b(imm,rs2,rs1,f3):
    assert -4096 <= imm < 4096 and imm % 2 == 0, f'branch offset {imm}'
    imm &= 0x1fff
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|\
           (((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|0x63
def enc_u(imm20,rd,op): return ((imm20&0xfffff)<<12)|(rd<<7)|op
def enc_j(imm,rd):
    assert -(1<<20) <= imm < (1<<20) and imm % 2 == 0
    imm &= 0x1fffff
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|\
           (((imm>>12)&0xff)<<12)|(rd<<7)|0x6f

def num(s): return int(s.strip(), 0)

def expand(line):
    """pseudo-instruction expansion -> list of (mnemonic, [operands])"""
    m = line.split(None, 1)
    op = m[0].lower()
    args = [a.strip() for a in m[1].split(',')] if len(m) > 1 else []
    if op == 'nop':  return [('addi', ['x0','x0','0'])]
    if op == 'mv':   return [('addi', [args[0], args[1], '0'])]
    if op == 'not':  return [('xori', [args[0], args[1], '-1'])]
    if op == 'neg':  return [('sub', [args[0], 'x0', args[1]])]
    if op == 'j':    return [('jal', ['x0', args[0]])]
    if op == 'ret':  return [('jalr', ['x0', '0(ra)'])]
    if op == 'beqz': return [('beq', [args[0], 'x0', args[1]])]
    if op == 'bnez': return [('bne', [args[0], 'x0', args[1]])]
    if op == 'li':
        v = num(args[1]) & 0xffffffff
        lo = sx(v, 12)
        hi = ((v - lo) >> 12) & 0xfffff
        return [('lui', [args[0], str(hi)]), ('addi', [args[0], args[0], str(lo)])]
    if op == 'check':
        v = num(args[1]) & 0xffffffff
        lo = sx(v, 12); hi = ((v - lo) >> 12) & 0xfffff
        return [('lui', ['x30', str(hi)]), ('addi', ['x30','x30',str(lo)]),
                ('bne', [args[0], 'x30', 'fail'])]
    return [(op, args)]

def assemble(text):
    items, labels, pc = [], {}, 0
    for raw in text.splitlines():
        line = raw.split('#')[0].strip()
        while ':' in line:
            lab, line = line.split(':', 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if not line: continue
        for ins in expand(line):
            items.append((pc, ins)); pc += 4
    words = []
    for pc, (op, a) in items:
        def tgt(x):  # label or numeric offset
            return labels[x] - pc if x in labels else num(x)
        def memop(x):
            m = re.fullmatch(r'(.*)\((.+)\)', x.strip())
            return num(m.group(1) or '0'), reg(m.group(2))
        if op in R:
            f3, f7 = R[op]; w = enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]), 0x33)
        elif op in I:
            w = enc_i(num(a[2]), reg(a[1]), I[op], reg(a[0]), 0x13)
        elif op in SH:
            f3, f7 = SH[op]; w = enc_i((f7<<5)|(num(a[2])&0x1f), reg(a[1]), f3, reg(a[0]), 0x13)
        elif op in L:
            off, rs = memop(a[1]); w = enc_i(off, rs, L[op], reg(a[0]), 0x03)
        elif op in S:
            off, rs = memop(a[1]); w = enc_s(off, reg(a[0]), rs, S[op], 0x23)
        elif op in B:
            w = enc_b(tgt(a[2]), reg(a[1]), reg(a[0]), B[op])
        elif op == 'jal':  w = enc_j(tgt(a[1]), reg(a[0]))
        elif op == 'jalr':
            off, rs = memop(a[1]); w = enc_i(off, rs, 0, reg(a[0]), 0x67)
        elif op == 'lui':   w = enc_u(num(a[1]), reg(a[0]), 0x37)
        elif op == 'auipc': w = enc_u(num(a[1]), reg(a[0]), 0x17)
        else: raise ValueError(f'unknown instruction: {op} {a}')
        words.append(w & 0xffffffff)
    return words

if __name__ == '__main__':
    words = assemble(open(sys.argv[1]).read())
    with open(sys.argv[2], 'w') as f:
        for w in words: f.write(f'{w:08x}\n')
    print(f'assembled {len(words)} instructions -> {sys.argv[2]}')
