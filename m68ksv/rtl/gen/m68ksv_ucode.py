#!/usr/bin/env python3
# Copyright (C) 2026 Rodimus
# m68ksv microcode + decode-table generator. Writes (next to this script's parent folder, rtl/):
#   m68ksv_upkg.sv  - microword field layout and codes (package m68ksv_upkg)
#   m68ksv_urom.sv  - microcode ROM (M10K, synchronous read)
#   m68ksv_drom.sv  - decode ROMs (opcode -> class, class -> routine kinds, kind x mode -> routine address)
# Run: python3 m68ksv_ucode.py            (regenerates the three files; no other inputs)
#
# Micro-cycle pipeline (see DESIGN.md): a micro-instruction that names a bus op starts that bus cycle at its own
# start; the bus occupies it and the next micro-instruction; read data is usable two micro-instructions later.
# Operands are read at e2, results written at the micro-cycle end (AU results to registers at e3, ALU at e0).
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.dirname(HERE)

# Per-CPU ROM sets (DESIGN.md 7): the 68000-family ROMs (68000 / 68008 / 68008FN / 68EC000) and the 68010 ROMs come from
# this one source, run once per member. The 68010 microcode is the 68000 microcode with in-place patches (same length,
# so every label the RTL uses keeps its address) plus appended 68010 routines; its decode ROMs are its own.
if 'GEN_CPU' not in globals():
    _src = open(os.path.abspath(__file__)).read()
    _res = {}
    for _cpu in (68000, 68010, 68020):
        _g = {'__name__': '__gen__', '__file__': os.path.abspath(__file__), 'GEN_CPU': _cpu}
        exec(compile(_src, os.path.abspath(__file__), 'exec'), _g)
        _res[_cpu] = _g['RESULT']
    _a, _b, _c = _res[68000], _res[68010], _res[68020]
    for _k in _a['shared']:
        assert _a['shared'][_k] == _b['shared'][_k], ('label / class moved between the 68000 and 68010 ROMs', _k)
        # 68020: the RTL-named labels keep their 68000 addresses; its decode classes are numbered on their own
        # (exported as CLS20_* in the package)
        assert _k.startswith('CLS_') or _a['shared'][_k] == _c['shared'][_k], ('label moved in the 68020 ROM', _k)
    open(os.path.join(RTL, 'm68ksv_upkg.sv'), 'w').write(_a['pkg'].replace('endpackage\n', _b['pkg10'] + _c['pkg20'] + 'endpackage\n'))
    open(os.path.join(RTL, 'm68ksv_urom.sv'), 'w').write(_a['urom'] + '\n' + _b['urom'] + '\n' + _c['urom'])
    open(os.path.join(RTL, 'm68ksv_drom.sv'), 'w').write(_a['drom'] + '\n' + _b['drom'] + '\n' + _c['drom'])
    with open(os.path.join(os.path.dirname(RTL), 'verify', 'tb', 'm68ksv_ualabels.h'), 'w') as _f:
        _f.write(_a['labels'] + _b['labels10'] + _c['labels20'])
    print('68000 family: %s; 68010: %s; 68020: %s' % (_a['summary'], _b['summary'], _c['summary']))
    if '-w' in sys.argv or '-l' in sys.argv:
        print(_c['dump'] if '-20' in sys.argv else _b['dump'] if '-10' in sys.argv else _a['dump'])
    sys.exit(0)
CPU = GEN_CPU
IS020 = CPU == 68020                # 68020 / 68EC020 (one ROM set; the EC020 differences are run-time conditions)
IS010 = CPU in (68010, 68020)       # the 68010 features (and its microcode patches) are the 68020's base too
SFX = {68000: '', 68010: '_010', 68020: '_020'}[CPU]      # module-name suffix of the per-member ROMs

# ---------------------------------------------------------------------------------------------------------------
# microword fields: name -> (width, [codes])
FIELDS = [
    ('sq',  4, ['NXT', 'CONT', 'FIN', 'BT', 'BF', 'CALL', 'RET', 'BODY', 'FINC', 'FINNC',
                'RSM']),                                      # 68010: resume a continued instruction (RTE format 8)
    ('nxt', 11, None),
    ('cd',  5, ['T', 'CC', 'SZL', 'CNTNZ', 'CNTGT1', 'MASKNZ', 'DBEXP', 'VSET', 'AUX', 'IRQ', 'SUP', 'DIVZ',
                'DIVOV', 'PD', 'BIT16', 'DIVOVU', 'DVNEG', 'NSET', 'SPUR',
                'CRVALID', 'CXDR', 'FMT0', 'FMT8', 'VERSOK', 'RRSET', 'SSWRM', 'SSWIF', 'SSWRW', 'LMX', 'CHKX']),          # 68010: MOVEC code valid, MOVES register -> memory, RTE format
    ('bus', 3, ['NONE', 'NPE', 'NPF', 'RD', 'WR', 'TAS', 'IACK']),
    ('ba',  4, ['FPC', 'AT', 'AUR', 'AY', 'AX', 'SP', 'VEC', 'VEC2', 'ATIRC', 'DT', 'IACKA',
                'BKPT', 'FA', 'CPS']),                        # 68010: breakpoint acknowledge (CPU space, address 0),
                                                              # fault address (re-run); 68020: coprocessor interface
                                                              # register of the F-line instruction (CPU space type 2)
    ('bs',  2, ['OPSZ', 'BYTE', 'WORD', 'SSW']),        # SSW: 68010 re-run, byte when the SSW says so
    ('bd',  2, ['LO', 'HI', 'SHB', 'L1']),
    ('bf',  2, ['DATA', 'PROG', 'SUPD', 'CPU']),
    ('dw',  5, ['NONE', 'RESL', 'RESH', 'DTL', 'DTH', 'EAVL', 'EAVH', 'PCXL', 'PCXH', 'SRT', 'IR', 'FINFO', 'FAL',
                'FAH', 'MRL', 'MRH', 'ATL', 'ATH', 'AYL', 'AYH', 'DTB3', 'TASB', 'EAV1', 'IML', 'IMH',
                'FMT', 'RC1', 'RCL', 'SRW', 'CCRW', 'X10', 'SCC']),  # X10: format-8 frame word selected by fx         # 68010: format / vector word, MOVES register (long: high
                                                              # word first), SR / CCR as data
    ('aa',  4, ['ZERO', 'AY', 'AX', 'SP', 'AT', 'FPC', 'PCX', 'DT', 'SSP',
                'FBY', 'FBX', 'FBP', 'XT', 'BFA']),            # 68020 full-format base: An / Ax / PC, 0 when BS;
                                                              # BFA: bit-field byte address (EA + offset / 8);
                                                              # XT: the memory-indirect pointer
    ('ab',  4, ['ZERO', 'INC', 'DEC', 'P2', 'M2', 'P4', 'M4', 'D16', 'D8', 'BD8', 'BD16', 'D8M2', 'XN', 'IRCH',
                'IRCZ', 'DT']),
    ('ad',  3, ['NONE', 'AT', 'AY', 'AX', 'SP', 'FPC', 'PCX', 'ATPI']),
    ('as',  2, ['OPSZ', 'BYTE', 'WORD', 'OPW']),
    ('op',  6, ['NOP', 'DEC', 'PASS', 'ADD', 'SUB', 'CMP', 'AND', 'OR', 'EOR', 'ADDX', 'SUBX', 'NEG', 'NEGX', 'NOT',
                'CLR', 'TST', 'ABCD', 'SBCD', 'NBCD', 'EXT', 'SWAP', 'SHFI', 'SHF', 'SHF1', 'BIT', 'SCC', 'TAS',
                'ADDA', 'SUBA', 'CMPA', 'MUL', 'SEXT', 'CHK', 'DIVR', 'DIVO', 'DIVZ', 'MVL', 'MVH',
                'EXTB', 'MULLL', 'MULLH', 'DVLQ', 'DVLR', 'DVLO', 'PACK', 'UNPK', 'UNPKH', 'BFP', 'BF', 'BF5',
                'CHK2']),
                                                              # 68020: EXTB.L, MUL.L, DIV.L results, PACK / UNPK
    ('xa',  5, ['ZERO', 'ONE', 'EAV', 'DX', 'DY', 'AY', 'DT', 'IM', 'RES', 'QUICK', 'IRC', 'SR', 'AT', 'FPC', 'CA',
                'IRQ8', 'OSP', 'RXE', 'RYE', 'SP', 'AX', 'EAVM',
                'CTL', 'RC', 'CCR', 'PCX', 'AYLK',                    # 68010: control register (MOVEC), extension-word register, CCR
                'RCO', 'RCC', 'RCL']),                                # 68020: data register cx[8:6] (bit-field offset),
                                                                      # cx[14:12] (bit-field insert value; bit 15 ignored),
                                                                      # cx[2:0] (CAS compare register)
    ('xb',  4, ['ZERO', 'EAV', 'DX', 'DY', 'AX', 'AY', 'DT', 'RES', 'IM', 'SR', 'AT', 'M2', 'M4', 'RYE',
                'RC', 'RCH']),                                # 68020: data registers of the extension word (cx[14:12] / [2:0])
    ('xd',  4, ['NONE', 'DX', 'DY', 'AX', 'AY', 'DT', 'AT', 'IM', 'IMH', 'SR', 'CCR', 'MREG', 'PCX', 'OSP', 'RXE',
                'RYE']),
    ('xs',  2, ['OPSZ', 'BYTE', 'WORD', 'LONG']),
    ('fl',  1, None),
    ('ms',  6, ['NONE', 'LDMASK', 'MNEXT', 'LDCNTSH', 'CNTDEC', 'EXCENT', 'DINIT', 'DSTEP', 'RSTO1', 'RSTO0',
                'LDCNTRST', 'VILL', 'VPRIV', 'VLA', 'VLF', 'VTRAP', 'VCHK', 'VTRAPV', 'VDIV0', 'VTRACE', 'VINT',
                'DTSHL8', 'HALT', 'SETIPL', 'STOPW', 'VRST1', 'LDCNTMUL', 'LDCNTDIV', 'LDAEPC', 'IRCIR',
                'LDCX', 'VFMT', 'VCPV']),                     # 68010: cx <= IRC, vector 14 (format error); 68020: vector 13
                                                              # (coprocessor protocol violation)
    ('bn',  1, None),          # address error: access word I/N = 1 (exception-processing access)
    ('ai',  1, None),          # address error: stacked IR = the next opcode (after the final prefetch)
    ('iq',  1, None),          # interrupt decision latched on this word's e2 (the 68000's IRC -> IR micro-word: the
                               # first word of the final prefetch, set automatically on NPF words; RESET differs)
    ('pl',  1, None),          # address error on this word's cycle after a bus wait: the next word (which loads the PC
                               # at its T1) ran its PC load during the wait (fx68k), the stacked PC is fpc; derived below
    ('lk',  2, None),          # address error on this word's cycle: its An write is kept - 1: after a bus wait (the 68000
                               # writes An in the cycle's second micro-word, which runs during the wait; b/w only), 2: always
                               # (the 68000 writes it at the faulting word's own T3)
    ('fh',  2, ['NONE', 'LO', 'CM', 'HD']),
                               # flags of a long ALU op in two steps, as the 68000's 16-bit ALU: LO writes the low word's
                               # flags (N Z of bits 15-0, X V C out of bit 15; byte / word ops: their normal flags) and holds
                               # X V C of the long op; CM (with op PASS RES, fl) writes the held flags, N Z of the long RES;
                               # HD (no fl) only holds this long op's X V C, its carry-in X taken from before the LO word
    ('lh',  2, None),          # the ALU register write of this word merges only the low word (1: the 68000 writes the high
                               # word of a long result later, a PASS RES word completes it) / only the high word (2: MOVEM.l
                               # to registers writes the high word read one access earlier first)
    ('pu',  4, ['NONE', 'T1FPC', 'T1PCX', 'T1AUR', 'FPC', 'FPCM2', 'FPCP2', 'PCX', 'AT', 'VEC']),
                               # the 68000's PC register (pc68, stacked by a bus error) is loaded in this word: at its
                               # start (T1*, e0: AU -> PC) or at its e2 (bus -> PC), from fpc / fpc - 2 / fpc + 2 / PCX /
                               # AUR / AT / the vector address (see PU below)
]
# 68010-only fields: above the 68000 microword (the 68000-family ROM is UW0 bits wide and never sets them; in the RTL
# they are constant 0 outside the 68010 build)
FIELDS10 = [
    ('sf',  2, ['NONE', 'SFC', 'DFC', 'SSW']),   # function code of the access from SFC / DFC (MOVES) / the SSW (re-run)
    ('xe',  3, ['NONE', 'RCD', 'CTLW', 'RCH', 'RCL']),   # ALU destination: RCD register named by the extension word (cx[15:12]),
                                            # 68020 RCH: data register cx[2:0] (Dh / Dr of MUL.L / DIV.L), RCL:
                                            # data register cx[14:12] (Dl / Dq; bit 15 ignored as Musashi),
                                            # CTLW the control register named by cx[11:0] (USP through the register file)
    ('fx',  6, ['NONE', 'FMT8', 'SSW', 'DOB', 'IIB', 'DIB', 'I0', 'I1', 'IR', 'IRN', 'SLAH', 'SLAL', 'SLBH', 'SLBL',
                'AURH', 'AURL', 'LSSW', 'LFAH', 'LFAL', 'LDOB', 'LDIB', 'LIIB', 'LI0', 'LI1', 'LIR', 'LIRN', 'LATH',
                'LATL', 'LAURH', 'LAURL', 'LSR', 'MSLA', 'MSLB', 'RSTR', 'MAUR', 'G0ON', 'G0OFF',
                'SSW20', 'LSSW20', 'DIBH']), # 68020 format B: the SSW in the 68020 layout (push / RTE: software
                                            # completion when DF / RB / RC were cleared); DIBH: data input buffer
                                            # high word (address error: the fault address, as WinUAE)
                                            # format-8 frame (m68ksv_eu): 1-15 word sources of a push (dw X10);
                                            # LSSW-LAURL loads straight from the read data of this word's bus cycle
                                            # (RTE; LSR: also into DT); MSLA-MAUR moves at the end of the word
    ('ly',  2, None),                       # format-8 frame layout of this bus word's fault: bit 0 slot B holds
                                            # {MOVEM mask, count} instead of RES, bit 1 slot A {SRT, vector} instead of IM
    ('rr',  1, None),                       # the re-run cycle of RTE format 8 (a fault on it keeps the resume state)
    ('x1',  3, ['NONE', 'VG0', 'SWDONE', 'SRF', 'LMCAND', 'LMDZ', 'LMC', 'LMOFF']),
                                            # 68010 misc: vector 2 / 3 of the group-0 fault; software-completed cycle
                                            # (DIB / IIB); SR and trace state from the frame; loop mode (DBcc
                                            # displacement -4 seen / entry check / fast loop word / leave)
]
# 68020-only fields: above the 68010's (constant 0 in the other ROM sets and gated by IS020 in the RTL)
FIELDS20 = [
    ('c2',  6, ['NONE', 'FULLX', 'XBDN', 'XBDL', 'XNOPRE', 'XNIND', 'XNPOST', 'XODN', 'XODL', 'ISEC', 'MUL64',
                'DVZL', 'DVOVL', 'DVOVL2', 'TOPW', 'TOPL', 'BFMOD', 'BFEXT', 'BF5', 'SZB', 'CHK2X', 'ZSET',
                'FMT1', 'FMT2', 'FMT9', 'FMTA', 'FMTB', 'MSET',
                'CPRD', 'CPGEN', 'CPNULL', 'CPAGAIN']),   # coprocessor: cpSAVE / cpGEN, response null / busy or come again
                                            # extra branch conditions (c2 != NONE overrides cd)
    ('xw',  1, None),                       # index register / size / scale of the AU's XN operand from the saved
                                            # full-format extension word (xw) instead of IRC
    ('m2',  5, ['NONE', 'LDXW', 'XP', 'MULL', 'DVLINIT', 'DVLHI', 'DVLSTEP', 'BFINIT', 'LDCX2', 'SWCX', 'LDCNTF',
                'CLRM', 'FLOW', 'RMCON', 'RMCOFF', 'AEPC']),     # FLOW: change of flow (T0 trace) on this path (taken Bcc / DBcc);
                                            # RMCON / RMCOFF: CAS / CAS2 locked sequence (RMC) from this read / ends here
                                            # XP (on a read): the data goes to the indirect pointer XT, not DT
                                            # 68020 misc operations (end of word, as ms)
                                            # AEPC: address error of a JMP: PCX = its address + 2 (WinUAE, 2026-11-16)
    ('d2',  4, ['NONE', 'PPCH', 'PPCL', 'F2', 'F1', 'FB', 'RUL', 'RUH', 'SRTS', 'CPW']),   # CPW: coprocessor command / condition word
                                            # 68020 write data (overrides dw): instruction address (format 2),
                                            # format / vector words
]
UW0 = sum(w for _, w, _ in FIELDS)
UW10 = UW0 + sum(w for _, w, _ in FIELDS10)
FIELDS = FIELDS + FIELDS10 + FIELDS20
FW = {n: w for n, w, _ in FIELDS}
FC = {n: ({c: i for i, c in enumerate(cs)} if cs else None) for n, _, cs in FIELDS}
FPOS = {}
p = 0
for n, w, _ in FIELDS:
    FPOS[n] = p
    p += w
UW = p if IS020 else UW10 if IS010 else UW0

# ---------------------------------------------------------------------------------------------------------------
# micro-routines
CODE = []        # list of dicts
LABELS = {}

def L(name):
    assert name not in LABELS, name
    LABELS[name] = len(CODE)

def U(**kw):
    """one micro-instruction. au=(aa, ab, ad[, as]); alu=(op, xa, xb, xd[, xs]); bus=(bus, ba[, extra...])."""
    w = {}
    if 'au' in kw:
        t = kw.pop('au')
        w['aa'], w['ab'], w['ad'] = t[0], t[1], t[2]
        if len(t) > 3: w['as'] = t[3]
    if 'alu' in kw:
        t = kw.pop('alu')
        w['op'], w['xa'], w['xb'], w['xd'] = t[0], t[1], t[2], t[3]
        if len(t) > 4: w['xs'] = t[4]
    if 'b' in kw:
        t = kw.pop('b')
        w['bus'] = t[0]
        w['ba'] = t[1] if len(t) > 1 else ('FPC' if t[0] in ('NPE', 'NPF') else 'AT')
    w.update(kw)
    if 'L' in w:
        L(w.pop('L'))
    CODE.append(w)

def nop(n=1, **kw):
    for i in range(n):
        U(**(kw if i == n - 1 else {}))

# shorthand
def RD(ba, **kw):  return dict(b=('RD', ba), **kw)

# ---- reset / test entry ----------------------------------------------------------------------------------------
L('RESET')                                     # SR = 2700, vec = 0 set by the reset logic; vectors in supervisor program space
for _i in range(4):                            # first bus cycle 22 phases after RESET is released (fx68k)
    U()
U(b=('RD', 'VEC'), bd='HI', bf='PROG')
U()
U(b=('RD', 'VEC2'), bd='LO', bf='PROG')
U(ms='VRST1')
U(b=('RD', 'VEC'), bd='HI', bf='PROG', au=('DT', 'ZERO', 'SP'))
U()
U(b=('RD', 'VEC2'), bd='LO', bf='PROG')
U(sq='NXT', nxt='VECJMP')

L('TLFIN')                                                      # harness test start: dispatch from IRN
U(sq='FIN')

# ---- exception sequences ---------------------------------------------------------------------------------------
# group 1 / 2 frame: PCX and vec already set
L('EXC12')                                                       # entered with PCX, vec and AT = SSP - 2 set
U(ms='EXCENT')
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'))
L('EXC12_2')
U()
U(b=('WR', 'AT'), dw='SRT', au=('AT', 'P2', 'AT'))
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='PCXH')
U(sq='NXT', nxt='VECTAIL')
L('VECTAIL')
U(b=('RD', 'VEC'), bd='HI', bf='SUPD')
U()
U(b=('RD', 'VEC2'), bd='LO', bf='SUPD')
U()
L('VECJMP')
U(b=('NPE', 'DT'))
U()
L('VECJMP_G0')                                     # group-0 state ends here (fx68k): the first refill still double-faults
U()
U(b=('NPF',))
U(sq='FIN')
L('JMPDT')
U(b=('NPE', 'DT'))
U()
U(b=('NPF',))
U(sq='FIN')

# group 0 (address / bus error): vec, FA, FINFO set by hardware. An address error enters at EXC0A (one more idle
# micro-cycle: the 68000 sequencer stays stopped while the faulting cycle runs on); a bus error enters at EXC0 after the
# micro-cycle start has been held while BERR is asserted (fx68k wClk), which takes the place of that micro-cycle
L('EXC0A')
U()
L('EXC0')                                                        # 4 clocks after the aborted cycle, 8 more idle
U(ms='LDAEPC')
U()
U(au=('SSP', 'M2', 'AT'))
U(ms='EXCENT')
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'))
U()
U(b=('WR', 'AT'), dw='SRT', au=('AT', 'P2', 'AT'))
U()
U(b=('WR', 'AT'), dw='PCXH', au=('AT', 'M4', 'AT'))
U()
U(b=('WR', 'AT'), dw='IR', au=('AT', 'M2', 'AT'))
U()
U(b=('WR', 'AT'), dw='FAL', au=('AT', 'M4', 'AT'))
U()
U(b=('WR', 'AT'), dw='FINFO', au=('AT', 'P2', 'AT'))
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='FAH')
U(sq='NXT', nxt='VECTAIL')

def exc_entry(label, vec, pcoff):
    L(label)
    U(alu=('ADD', 'FPC', pcoff, 'PCX', 'LONG'), ms=vec, au=('SSP', 'M2', 'AT'), sq='NXT',
      nxt='EXC12C' if pcoff == 'M2' else 'EXC12')

# CHK / zero divide enter before the final prefetch: an address error on the first frame write stacks fpc - 2 (fx68k)
L('EXC12C')
U(ms='EXCENT')
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'), sq='NXT', nxt='EXC12_2')

exc_entry('EXC_ILL', 'VILL', 'M4')
exc_entry('EXC_PRIV', 'VPRIV', 'M4')
exc_entry('EXC_LA', 'VLA', 'M4')
exc_entry('EXC_LF', 'VLF', 'M4')
exc_entry('EXC_TRACE', 'VTRACE', 'M4')
exc_entry('EXC_CHK', 'VCHK', 'M2')            # before the final prefetch: next PC = fpc - 2
exc_entry('EXC_TRAPV', 'VTRAPV', 'M4')
exc_entry('EXC_DIV0', 'VDIV0', 'M2')          # before the final prefetch: next PC = fpc - 2

# interrupt: PC lo, IACK, SR, PC hi, vector
L('EXC_INT')                                       # 68000: n6, PC lo, IACK, n4, SR, PC hi, vector, refill
U(alu=('ADD', 'FPC', 'M4', 'PCX', 'LONG'), ms='EXCENT')
U(ms='SETIPL')
U(au=('SSP', 'M2', 'AT'))
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'))
U()
U(b=('IACK', 'IACKA'), bf='CPU', bs='WORD', bd='LO')                 # both data strobes (fx68k); vector on D7-D0
U()
U(ms='VINT')
U(ms='IRCIR')                                    # spurious (BERR on IACK): the BERR hold adds the 68000's extra time
L('EXC_INT_W')
U(b=('WR', 'AT'), dw='SRT', au=('AT', 'P2', 'AT'))
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='PCXH')
U(sq='NXT', nxt='VECTAIL')

L('HALTA')                                        # double bus fault: HALT output four clocks after the aborted cycle
U()                                               # (address error: from HALTA; bus error: from HALT, see EXC0A)
L('HALT')
U()
L('HALT_L')
U(ms='HALT', sq='NXT', nxt='HALT_L')

# ---- EA routines -------------------------------------------------------------------------------------------------
# each ends with the bus idle (or in its second half) and CONT; read operands land in DT, immediates in IM.
EATAB = {}           # kind -> list of 16 labels (None = skip)
SKIP = 'SKIP'

def ea_read_set(kind, lng):
    tab = [SKIP, SKIP] + [None] * 14
    def rd_tail(first_ba, extra_first=None, at_from_first=False):
        # issue the read (word/byte or long hi) at first_ba; long: then lo at AT+2
        kw = dict(extra_first or {})
        if not lng:
            U(b=('RD', first_ba), **kw)
            U(sq='CONT')
        else:
            U(b=('RD', first_ba), bd='HI', **kw)
            U(au=('AT', 'P2', 'NONE'))
            U(b=('RD', 'AUR'), bd='LO')
            U(sq='CONT')
    sfx = kind
    L(sfx + '_AI'); tab[2] = sfx + '_AI'
    rd_tail('AY', dict(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG')))
    L(sfx + '_PI'); tab[3] = sfx + '_PI'
    if not lng:
        rd_tail('AY', dict(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), au=('AY', 'INC', 'AY')))
    else:
        U(b=('RD', 'AY'), bd='HI', alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'))
        U(au=('AT', 'P2', 'NONE'))
        U(b=('RD', 'AUR'), bd='LO')
        U(sq='CONT', au=('AY', 'INC', 'AY'))                         # An after the low-word read (68000)
    L(sfx + '_PD'); tab[4] = sfx + '_PD'
    U(au=('AY', 'DEC', 'AY'))
    rd_tail('AY', dict(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG')))
    L(sfx + '_D16'); tab[5] = sfx + '_D16'
    U(b=('NPE',), au=('AY', 'D16', 'AT'))
    U()
    rd_tail('AT')
    L(sfx + '_D8'); tab[6] = sfx + '_D8'
    U(au=('AY', 'D8', 'AT'))
    U(b=('NPE',), au=('AT', 'XN', 'AT'))
    U()
    rd_tail('AT')
    L(sfx + '_AW'); tab[7] = sfx + '_AW'
    U(b=('NPE',), au=('ZERO', 'D16', 'AT'))
    U()
    rd_tail('AT')
    L(sfx + '_AL'); tab[8] = sfx + '_AL'
    U(b=('NPE',), au=('ZERO', 'IRCH', 'AT'))
    U()
    U(b=('NPE',), au=('AT', 'IRCZ', 'AT'))
    U()
    rd_tail('AT')
    L(sfx + '_P16'); tab[9] = sfx + '_P16'
    U(b=('NPE',), au=('FPC', 'BD16', 'AT'))
    U()
    rd_tail('AT', dict(bf='PROG'))
    if lng: CODE[-2]['bf'] = 'PROG'
    L(sfx + '_P8'); tab[10] = sfx + '_P8'
    U(au=('FPC', 'D8M2', 'AT'))
    U(b=('NPE',), au=('AT', 'XN', 'AT'))
    U()
    rd_tail('AT', dict(bf='PROG'))
    if lng: CODE[-2]['bf'] = 'PROG'

    tab[11] = 'IMML' if lng else 'IMMW'
    EATAB[kind] = tab

L('IMMW')
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM'))
U(sq='CONT')
L('IMML')
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IMH', 'WORD'))
U()
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM', 'WORD'))
U(sq='CONT')

ea_read_set('RDW', False)
ea_read_set('RDL', True)

def ea_addr_set(kind, movem):
    """address only: AT = effective address (ext words prefetched); (An)+ / -(An) update An unless movem."""
    tab = [None] * 16
    L(kind + '_AI'); tab[2] = kind + '_AI'
    U(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), sq='CONT')
    L(kind + '_PI'); tab[3] = kind + '_PI'
    if movem:
        U(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), sq='CONT')
    else:
        U(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), au=('AY', 'INC', 'AY'), sq='CONT')
    L(kind + '_PD'); tab[4] = kind + '_PD'
    if movem:
        U(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), sq='CONT')
    else:
        U(au=('AY', 'DEC', 'AY'))
        U(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG'), sq='CONT')
    L(kind + '_D16'); tab[5] = kind + '_D16'
    U(b=('NPE',), au=('AY', 'D16', 'AT'))
    U(sq='CONT')
    L(kind + '_D8'); tab[6] = kind + '_D8'
    U(au=('AY', 'D8', 'AT'))
    U(b=('NPE',), au=('AT', 'XN', 'AT'))
    U(sq='CONT')
    L(kind + '_AW'); tab[7] = kind + '_AW'
    U(b=('NPE',), au=('ZERO', 'D16', 'AT'))
    U(sq='CONT')
    L(kind + '_AL'); tab[8] = kind + '_AL'
    U(b=('NPE',), au=('ZERO', 'IRCH', 'AT'))
    U()
    U(b=('NPE',), au=('AT', 'IRCZ', 'AT'))
    U(sq='CONT')
    L(kind + '_P16'); tab[9] = kind + '_P16'
    U(b=('NPE',), au=('FPC', 'BD16', 'AT'))
    U(sq='CONT')
    L(kind + '_P8'); tab[10] = kind + '_P8'
    U(au=('FPC', 'D8M2', 'AT'))
    U(b=('NPE',), au=('AT', 'XN', 'AT'))
    U(sq='CONT')
    EATAB[kind] = tab

ea_addr_set('ADDR', False)
# TAS: the read-modify-write cycle starts from An for (An) / (An)+ / -(An); other modes use the ADDR routines + TASM
_t = list(EATAB['ADDR'])
L('TAS_AI'); _t[2] = 'TAS_AI'
U(b=('TAS', 'AY'), bs='BYTE', sq='NXT', nxt='TASM_2')
L('TAS_PI'); _t[3] = 'TAS_PI'
U(b=('TAS', 'AY'), bs='BYTE', au=('AY', 'INC', 'AY', 'BYTE'), sq='NXT', nxt='TASM_2')
L('TAS_PD'); _t[4] = 'TAS_PD'
U(au=('AY', 'DEC', 'AY', 'BYTE'))
U(b=('TAS', 'AY'), bs='BYTE', sq='NXT', nxt='TASM_2')
EATAB['TAS'] = _t
EATAB['IMMW'] = ['IMMW'] * 16
EATAB['IMML'] = ['IMML'] * 16

# ---- instruction bodies -----------------------------------------------------------------------------------------
def npf_body(label, extra, **kw):
    """final prefetch (with the word's own operation), extra idle micro-cycles, FIN"""
    L(label)
    U(b=('NPF',), **kw)
    for _ in range(extra):
        U()
    U(sq='FIN')

L('NOP')
U(b=('NPF',))
U(sq='FIN')

# <ea>,Dn  (ADD SUB AND OR CMP) and <ea>,An (ADDA SUBA CMPA)
# The 68000's ALU is 16 bits wide: a long result reaches the register low word first, the high word one or two words
# later, and a long op's flags come in two steps (low word, then long - fields lh / fh, lockstep WRTRACE / ABORTCHK)
npf_body('ALU_DN', 0, alu=('DEC', 'EAV', 'DX', 'DX'), fl=1)
npf_body('ALU_AN', 0, alu=('DEC', 'EAV', 'AX', 'AX'), fl=1)
npf_body('ALU_CP2', 1, alu=('DEC', 'EAV', 'DX', 'DX'), fl=1)        # CMP.l
npf_body('ALU_CPA', 1, alu=('DEC', 'EAV', 'AX', 'AX'), fl=1)        # CMPA
L('ALU_DN2')                                                        # .l from memory: long flags at once
U(b=('NPF',), alu=('DEC', 'EAV', 'DX', 'DX'), fl=1, lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DX', 'LONG'), sq='FIN')
L('ALU_AN2')                                                        # ADDA / SUBA .l from memory
U(b=('NPF',), alu=('DEC', 'EAV', 'AX', 'AX'), fl=1, lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'AX', 'LONG'), sq='FIN')
L('ALU_DN4')                                                        # .l from Dn / #imm
U(b=('NPF',), alu=('DEC', 'EAV', 'DX', 'DX'), fl=1, fh='LO', lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DX', 'LONG'), fl=1, fh='CM')
U(sq='FIN')
L('ALU_AN4')                                                        # ADDA / SUBA .w, .l from An / Dn / #imm
U(b=('NPF',), alu=('DEC', 'EAV', 'AX', 'AX'), fl=1, lh=1)
U()
U()
U(alu=('PASS', 'RES', 'ZERO', 'AX', 'LONG'), sq='FIN')

# read-modify-write on memory: B = DT (operand), A = decoded source; result back to AT
L('RMW')
U(b=('NPF',), alu=('DEC', 'CA', 'EAV', 'NONE'), fl=1, fh='LO', au=('AT', 'P2', 'NONE'), sq='BT', cd='SZL', nxt='RMW_L')
U()
U(b=('WR', 'AT'), dw='RESL')
U(sq='FIN')
L('RMW_L')
U()
U(b=('WR', 'AUR'), dw='RESL', alu=('PASS', 'RES', 'ZERO', 'NONE', 'LONG'), fl=1, fh='CM')
U()
U(b=('WR', 'AT'), dw='RESH')
U(sq='FIN')
# BCHG / BCLR / BSET on memory: Z is set two words after the final prefetch (68000), the same op again there
L('RMWB')
U(b=('NPF',), alu=('DEC', 'CA', 'EAV', 'NONE'))
U()
U(b=('WR', 'AT'), dw='RESL', alu=('DEC', 'CA', 'EAV', 'NONE'), fl=1)
U(sq='FIN')
# memory operand, no write (CMPI TST BTST)
npf_body('RMEM', 0, alu=('DEC', 'CA', 'EAV', 'NONE'), fl=1)
L('RMEM2')                                        # BTST Dn,#imm: Z two words after the prefetch (68000)
U(b=('NPF',))
U()
U(alu=('DEC', 'CA', 'EAV', 'NONE'), fl=1, sq='FIN')
# register operand Dy (NEG NOT CLR NEGX ADDI SUBI ... EOR Dn,Dn  Scc Dn  NBCD Dn  TAS Dn  bit ops on Dn  EXT SWAP)
for _x in (0, 1):
    npf_body('RDY' + ('', '2')[_x], _x, alu=('DEC', 'CA', 'DY', 'DY'), fl=1)
L('RDY2L')                                                          # NEGX / CLR / NEG / NOT .l Dn
U(b=('NPF',), alu=('DEC', 'CA', 'DY', 'DY'), fl=1, lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DY', 'LONG'), sq='FIN')
L('RDY2N')                                                          # NBCD Dn: Dn written two words later
U(b=('NPF',), alu=('DEC', 'CA', 'DY', 'NONE'), fl=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DY'), sq='FIN')
L('RDY2T')                                                          # BTST on Dn: Z two words after the prefetch
U(b=('NPF',))
U()
U(alu=('DEC', 'CA', 'DY', 'DY'), fl=1, sq='FIN')
# long ops on Dn, 8 clocks (68000: low word and its flags with the final prefetch, the long flags two words later,
# the high word after them)
L('RDY4')
U(b=('NPF',), alu=('DEC', 'CA', 'DY', 'DY'), fl=1, fh='LO', lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DY', 'LONG'), fl=1, fh='CM')
U(sq='FIN')
# bit ops on Dn: two more clocks for bit numbers 16-31 (BCLR: two more again)
for _lab, _base in (('RDYB', 1), ('RDYBC', 2)):
    # the 68000 writes Dn and Z after the BIT16 decision (bit < 16: in the word after it, else one word later)
    L(_lab)
    U(b=('NPF',), alu=('NOP', 'CA', 'DY', 'NONE'))
    U(sq='BT', cd='BIT16', nxt=_lab + '_H')
    U(alu=('DEC', 'CA', 'DY', 'DY'), fl=1, **({'sq': 'FIN'} if _base == 1 else {}))
    for _ in range(_base - 2):
        U()
    if _base > 1: U(sq='FIN')
    L(_lab + '_H')
    U()
    U(alu=('DEC', 'CA', 'DY', 'DY'), fl=1, **({'sq': 'FIN'} if _base == 1 else {}))
    for _ in range(_base - 2):
        U()
    if _base > 1: U(sq='FIN')
# Scc Dn: two more clocks when the condition is true
L('SCC_D')
U(b=('NPF',), alu=('DEC', 'CA', 'DY', 'NONE'), fl=1, sq='BT', cd='CC', nxt='SCC_DT')
U(alu=('PASS', 'RES', 'ZERO', 'DY', 'BYTE'), sq='FIN')
L('SCC_DT')
U()
U(alu=('PASS', 'RES', 'ZERO', 'DY', 'BYTE'), sq='FIN')
L('ADDQA')                                        # (68000: An low word first)
U(b=('NPF',), alu=('DEC', 'QUICK', 'AY', 'AY', 'LONG'), lh=1)
U()
U()
U(alu=('PASS', 'RES', 'ZERO', 'AY', 'LONG'), sq='FIN')
L('MOVEQ')
U(b=('NPF',), alu=('PASS', 'IRQ8', 'ZERO', 'DX', 'LONG'), fl=1)
U(sq='FIN')

# MOVE destinations (source operand = EAV)
L('MV_DN')
U(b=('NPF',), alu=('PASS', 'EAV', 'ZERO', 'DX'), fl=1)
U(sq='FIN')
L('MV_AN')
U(b=('NPF',), alu=('SEXT', 'EAV', 'ZERO', 'AX'))
U(sq='FIN')
L('MV_AI')
U(b=('WR', 'AX'), dw='EAV1', alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1, au=('AX', 'P2', 'AT'),
  sq='BT', cd='SZL', nxt='MV_AI_L')
U()
U(b=('NPF',))
U(sq='FIN')
L('MV_AI_L')
U()
U(b=('WR', 'AT'), dw='RESL')
U()
U(b=('NPF',))
U(sq='FIN')
L('MV_PI')                                        # (68000: An written with the final prefetch)
U(b=('WR', 'AX'), dw='EAV1', alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1, au=('AX', 'P2', 'AT'),
  sq='BT', cd='SZL', nxt='MV_PI_L')
U()
U(b=('NPF',), au=('AX', 'INC', 'AX'))
U(sq='FIN')
L('MV_PI_L')
U(au=('AX', 'INC', 'AX'))
U(b=('WR', 'AT'), dw='RESL')
U()
U(b=('NPF',))
U(sq='FIN')
L('MV_PD')                                        # (68000: An written at the write's own T3)
U(b=('NPF',), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1, au=('AX', 'DEC', 'NONE', 'OPW'), sq='BT', cd='SZL', nxt='MV_PD_L')
U()
U(b=('WR', 'AUR'), dw='RESL', au=('AX', 'DEC', 'AX', 'OPW'), lk=2)
U(sq='FIN')
L('MV_PD_L')
U(au=('AX', 'DEC', 'AX', 'OPW'))
U(b=('WR', 'AX'), dw='RESL')
U(au=('AX', 'DEC', 'AX', 'WORD'))
U(b=('WR', 'AX'), dw='RESH')
U(sq='FIN')

def mv_tail_at():
    """write EAV at AT (long: hi at AT, lo at AT+2), then NPF + FIN"""
    U(b=('WR', 'AT'), dw='RESL', au=('AT', 'P2', 'NONE'), sq='BT', cd='SZL', nxt=None)
    return len(CODE) - 1

def mv_dest(label, prologue):
    L(label)
    prologue()
    i = len(CODE)
    U(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE'), sq='BT', cd='SZL', nxt=label + '_L')
    U()
    U(b=('NPF',))
    U(sq='FIN')
    L(label + '_L')
    U()
    U(b=('WR', 'AUR'), dw='RESL')
    U()
    U(b=('NPF',))
    U(sq='FIN')

# for long destinations the first write is the high word: handled by dw EAVL meaning "low word of the sized
# operand" for B/W, and the RTL maps EAVL to the high word on the first write of a long (see m68ksv_eu: dw_hi)
mv_dest('MV_D16', lambda: (U(b=('NPE',), au=('AX', 'D16', 'AT'), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1), U()))
mv_dest('MV_D8', lambda: (U(au=('AX', 'D8', 'AT'), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1),
                          U(b=('NPE',), au=('AT', 'XN', 'AT')), U()))
mv_dest('MV_AW', lambda: (U(b=('NPE',), au=('ZERO', 'D16', 'AT'), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1), U()))
# MOVE b/w destinations after a register / #imm source: flags with the write (68000 rmdw2); abs.L: with the second
# extension word (ralw2)
def mv_dest_r(label, prologue, wfl=True):
    L(label)
    prologue()
    U(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE'), **(dict(alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1) if wfl else {}))
    U()
    U(b=('NPF',))
    U(sq='FIN')
mv_dest_r('MV_D16R', lambda: (U(b=('NPE',), au=('AX', 'D16', 'AT')), U()))
mv_dest_r('MV_D8R', lambda: (U(au=('AX', 'D8', 'AT')),
                            U(b=('NPE',), au=('AT', 'XN', 'AT')), U()))
mv_dest_r('MV_ALA', lambda: (U(b=('NPE',), au=('ZERO', 'IRCH', 'AT')), U(),
                             U(b=('NPE',), au=('AT', 'IRCZ', 'AT'), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1), U()), wfl=False)
# abs.L destination after a memory source: np, write(s), np, np
L('MV_ALB')
U(b=('NPE',), au=('ZERO', 'IRCH', 'AT'), alu=('PASS', 'EAV', 'ZERO', 'NONE'), fl=1)
U()
U(b=('WR', 'ATIRC'), dw='EAV1', au=('AT', 'IRCZ', 'AT'), sq='BT', cd='SZL', nxt='MV_ALB_L')
U()
L('MV_ALB_T')
U(b=('NPE',))
U()
U(b=('NPF',))
U(sq='FIN')
L('MV_ALB_L')
U(au=('AT', 'P2', 'NONE'))
U(b=('WR', 'AUR'), dw='RESL')
U(sq='NXT', nxt='MV_ALB_T')

# MOVE.l to memory: the 68000 sets the flags in two or three steps around the two writes (MVL: N Z of the low word,
# V = C = 0; MVH: N of the high word, Z &= high word zero, V C kept); where they sit differs between register / #imm
# sources (R) and memory sources (M) - visible when a write faults (fx68k, MAME). Final flags = the long's.
def mvl(label, pre, w1, w2, post, writes, npf=None):
    """pre: prologue words (list of dicts); w1 / w2 / post: flag op (None, 'MVL', 'MVH') of the first write, the second
    write and the final prefetch; writes: (first write kw, second write kw)"""
    L(label)
    for kw in pre:
        U(**kw)
    def fl(op):
        return dict(alu=(op, 'EAV', 'ZERO', 'NONE', 'LONG'), fl=1) if op else dict(alu=('PASS', 'EAV', 'ZERO', 'NONE', 'LONG'))
    U(**writes[0], **fl(w1))
    U(**writes[2]) if len(writes) > 2 else U()
    U(**writes[1], **fl(w2))
    U()
    U(b=('NPF',), **(fl(post) if post else {}), **(npf or {}))
    U(sq='FIN')
def F(op):
    return dict(alu=(op, 'EAV', 'ZERO', 'NONE', 'LONG'), fl=1) if op else dict(alu=('PASS', 'EAV', 'ZERO', 'NONE', 'LONG'))
for _p, (_w1, _w2, _po) in (('R', (None, 'MVL', 'MVH')), ('M', ('MVL', 'MVH', None))):
    mvl('MVL_AI_' + _p, [], _w1, _w2, _po, (dict(b=('WR', 'AX'), dw='EAV1', au=('AX', 'P2', 'AT')), dict(b=('WR', 'AT'), dw='RESL')))
    mvl('MVL_PI_' + _p, [], _w1, _w2, _po, (dict(b=('WR', 'AX'), dw='EAV1', au=('AX', 'P2', 'AT')), dict(b=('WR', 'AT'), dw='RESL')),
        npf=dict(au=('AX', 'INC', 'AX')))
_r = _p == 'R'
for _p, _f in (('R', ('PASS', 'MVH', 'MVL', 'MVH')), ('M', ('MVL', 'MVH', None, None))):
    _pre0 = F(_f[0] if _f[0] != 'PASS' else None)
    mvl('MVL_D16_' + _p, [dict(b=('NPE',), au=('AX', 'D16', 'AT'), **_pre0), {}], _f[1], _f[2], _f[3],
        (dict(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE')), dict(b=('WR', 'AUR'), dw='RESL')))
    mvl('MVL_D8_' + _p, [dict(au=('AX', 'D8', 'AT'), **_pre0), dict(b=('NPE',), au=('AT', 'XN', 'AT')), {}], _f[1], _f[2], _f[3],
        (dict(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE')), dict(b=('WR', 'AUR'), dw='RESL')))
mvl('MVL_AW', [dict(b=('NPE',), au=('ZERO', 'D16', 'AT'), **F('MVL')), {}], 'MVH', None, None,
    (dict(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE')), dict(b=('WR', 'AUR'), dw='RESL')))
mvl('MVL_ALA', [dict(b=('NPE',), au=('ZERO', 'IRCH', 'AT'), **F(None)), {}, dict(b=('NPE',), au=('AT', 'IRCZ', 'AT'), **F('MVL')), {}],
    'MVH', None, None, (dict(b=('WR', 'AT'), dw='EAV1', au=('AT', 'P2', 'NONE')), dict(b=('WR', 'AUR'), dw='RESL')))
L('MVL_PD')                                      # (68000: An written at the second write's T3)
U(b=('NPF',), au=('AX', 'M2', 'AT'), **F('MVL'))
U()
U(b=('WR', 'AT'), dw='RESL', au=('AT', 'M2', 'NONE'), **F('MVH'))
U()
U(b=('WR', 'AUR'), dw='RESH', au=('AT', 'M2', 'AX'), lk=2)
U(sq='FIN')
L('MVL_ALB')                                     # abs.L after a memory source: np, write, write, np, np
U(b=('NPE',), au=('ZERO', 'IRCH', 'AT'), **F(None))
U()
U(b=('WR', 'ATIRC'), dw='EAV1', au=('AT', 'IRCZ', 'AT'), **F('MVL'))
U(au=('AT', 'P2', 'NONE'))
U(b=('WR', 'AUR'), dw='RESL', **F('MVH'))
U(sq='NXT', nxt='MV_ALB_T')

# Bcc / BRA
L('BCC_S')
U(au=('FPC', 'BD8', 'AT'), sq='BT', cd='CC', nxt='BR_TAKEN')
U()
U(b=('NPF',))
U(sq='FIN')
L('BCC_W')
U(au=('FPC', 'BD16', 'AT'), sq='BT', cd='CC', nxt='BR_TAKEN')
U()
L('BR_SKIPW')
U(b=('NPE',))
U()
U(b=('NPF',))
U(sq='FIN')
L('BR_TAKEN')
U(b=('NPE', 'AT'))
U()
L('BR_T2')
U(b=('NPF',))
U(sq='FIN')
# BSR
L('BSR_S')
U(au=('SP', 'M4', 'SP'), alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'))
U(b=('WR', 'SP'), dw='PCXH', au=('FPC', 'BD8', 'AT'))
L('BSR_T')
U(au=('SP', 'P2', 'NONE'))
U(b=('WR', 'AUR'), dw='PCXL')
U()
L('BSR_TGT')
U(b=('NPE', 'AT'))
U(sq='NXT', nxt='BR_T2')
L('BSR_W')
U(au=('SP', 'M4', 'SP'), alu=('ADD', 'FPC', 'ZERO', 'PCX', 'LONG'))
U(b=('WR', 'SP'), dw='PCXH', au=('FPC', 'BD16', 'AT'), sq='NXT', nxt='BSR_T')
# DBcc
L('DBCC')                                         # condition false: the target is fetched at once
U(alu=('SUB', 'ONE', 'DY', 'NONE', 'WORD'), au=('FPC', 'BD16', 'AT'), sq='BT', cd='CC', nxt='DB_T')
U(b=('NPE', 'AT'), au=('FPC', 'ZERO', 'PCX'), sq='BT', cd='DBEXP', nxt='DB_EXP')
U(sq='NXT', nxt='DB_T2')
L('DB_T')                                         # condition true (as BR_SKIPW, the 68000 loads no PC in its first word)
U(sq='NXT', nxt='DB_SKIPW')
L('DB_SKIPW')
U(b=('NPE',))
U()
U(b=('NPF',))
U(sq='FIN')
L('DB_EXP')                                       # counter expired: refetch from the next instruction
U(au=('PCX', 'ZERO', 'NONE'))
U(b=('NPE', 'AUR'))
U(sq='NXT', nxt='DB_T2')
L('DB_T2')                                        # as BR_T2; Dn (counted down) written with the final prefetch (68000)
U(b=('NPF',), alu=('PASS', 'RES', 'ZERO', 'DY', 'WORD'))
U(sq='FIN')
# Scc Dn (memory form uses RMW)
# JMP / JSR per mode
def jmp_jsr(name, jsr):
    tab = [None] * 16
    def tail(pcx_off):
        pass
    for mi, nm in [(2, 'AI'), (5, 'D16'), (6, 'D8'), (7, 'AW'), (8, 'AL'), (9, 'P16'), (10, 'P8')]:
        lab = '%s_%s' % (name, nm)
        L(lab); tab[mi] = lab
        if mi == 2:
            U(b=('NPE', 'AY'), **(dict(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG')) if jsr else {}))
        else:
            pk = dict(alu=('ADD', 'FPC', 'ZERO', 'PCX', 'LONG')) if jsr else {}
            if mi == 5:
                U(au=('AY', 'D16', 'AT'), **pk)
            elif mi == 6:
                U(au=('AY', 'D8', 'AT'), **pk); U(au=('AT', 'XN', 'AT')); U()
            elif mi == 7:
                U(au=('ZERO', 'D16', 'AT'), **pk)
            elif mi == 8:
                U(b=('NPE',), au=('ZERO', 'IRCH', 'AT')); U(**pk)
            elif mi == 9:
                U(au=('FPC', 'BD16', 'AT'), **pk)
            elif mi == 10:
                U(au=('FPC', 'D8M2', 'AT'), **pk); U(au=('AT', 'XN', 'AT')); U()
            U(b=('NPE', 'ATIRC' if mi == 8 else 'AT'))
        if jsr:                          # SP at the first push's T3 (68000)
            U(au=('SP', 'M4', 'NONE'))
            U(b=('WR', 'AUR'), dw='PCXH', au=('SP', 'M4', 'SP'), lk=2)
            U(au=('SP', 'P2', 'NONE'))
            U(b=('WR', 'AUR'), dw='PCXL')
            U()
        else:
            U()
        U(b=('NPF',))
        U(sq='FIN')
    EATAB[name] = tab

jmp_jsr('JMP', False)
jmp_jsr('JSR', True)

# LEA / PEA per mode
def lea_pea(name, pea):
    tab = [None] * 16
    for mi, nm in [(2, 'AI'), (5, 'D16'), (6, 'D8'), (7, 'AW'), (8, 'AL'), (9, 'P16'), (10, 'P8')]:
        lab = '%s_%s' % (name, nm)
        L(lab); tab[mi] = lab
        if mi == 2:
            src = 'AY'
        else:
            src = 'AT'
            if mi == 5: U(b=('NPE',), au=('AY', 'D16', 'AT')); U()
            elif mi == 6: U(au=('AY', 'D8', 'AT')); U(b=('NPE',), au=('AT', 'XN', 'AT')); U(); U()
            elif mi == 7: U(b=('NPE',), au=('ZERO', 'D16', 'AT')); U()
            elif mi == 8: U(b=('NPE',), au=('ZERO', 'IRCH', 'AT')); U(); U(b=('NPE',), au=('AT', 'IRCZ', 'AT')); U()
            elif mi == 9: U(b=('NPE',), au=('FPC', 'BD16', 'AT')); U()
            elif mi == 10: U(au=('FPC', 'D8M2', 'AT')); U(b=('NPE',), au=('AT', 'XN', 'AT')); U(); U()
        if not pea:
            if mi == 2:
                U(b=('NPF',), alu=('PASS', src, 'ZERO', 'AX', 'LONG'))
            else:                        # An written in the last address word (68000)
                CODE[-1]['op'], CODE[-1]['xa'], CODE[-1]['xb'], CODE[-1]['xd'], CODE[-1]['xs'] = 'PASS', src, 'ZERO', 'AX', 'LONG'
                if mi == 8:                  # abs.L: the high word first, with the first extension word
                    CODE[-3].update(op='PASS', xa='AT', xb='ZERO', xd='AX', xs='LONG', lh=2)
                U(b=('NPF',))
            U(sq='FIN')
        else:
            late = mi in (7, 8)          # PEA abs: pushes before the final prefetch
            if not late:
                U(b=('NPF',), au=('SP', 'M4', 'NONE'), **(dict(alu=('PASS', 'AY', 'ZERO', 'AT', 'LONG')) if mi == 2 else {}))
                U()
            else:
                CODE[-1]['aa'], CODE[-1]['ab'], CODE[-1]['ad'] = 'SP', 'M4', 'NONE'
            U(b=('WR', 'AUR'), dw='ATH', au=('SP', 'M4', 'SP'), lk=2)      # SP at the first push's T3 (68000)
            U(au=('SP', 'P2', 'NONE'))
            U(b=('WR', 'AUR'), dw='ATL')
            if not late:
                U(sq='FIN')
            else:
                U()
                U(b=('NPF',))
                U(sq='FIN')
    EATAB[name] = tab

lea_pea('LEA', False)
lea_pea('PEA', True)

# RTS / RTR / RTE
L('RTS')
U(b=('RD', 'SP'), bd='HI', au=('SP', 'P2', 'AT'))
U()
U(b=('RD', 'AT'), bd='LO')
U(sq='NXT', nxt='RTSJ')
L('RTSJ')                                         # as JMPDT; SP at the target fetch's T3 (68000)
U(b=('NPE', 'DT'), au=('SP', 'P4', 'SP'), lk=2)
U()
U(b=('NPF',))
U(sq='FIN')
for _lab, _xd, _xs in (('RTR', 'CCR', 'BYTE'), ('RTE', 'SR', 'WORD')):
    L(_lab)
    U(b=('RD', 'SP'), bd='LO', au=('SP', 'P2', 'AT'))
    U()
    U(b=('RD', 'AT'), bd='HI', au=('AT', 'P2', 'AT'), alu=('PASS', 'DT', 'ZERO', 'IM', 'WORD'))
    U()
    U(b=('RD', 'AT'), bd='LO', au=('AT', 'P2', 'SP'))
    U(alu=('PASS', 'IM', 'ZERO', _xd, _xs), sq='NXT', nxt='JMPDT')

# LINK / UNLK
L('LINK')                                         # An = SP - 4 before the pushes, SP written after them (fx68k)
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'DT', 'LONG'), au=('SP', 'M4', 'AT'))
U(alu=('PASS', 'AY', 'ZERO', 'IM', 'LONG'))
U(b=('WR', 'AT'), dw='IMH', au=('AT', 'ZERO', 'AY'), lk=2)       # An at the first push's T3, SP with the final prefetch
U(au=('AT', 'P2', 'NONE'))
U(b=('WR', 'AUR'), dw='IML')
U()
U(b=('NPF',), au=('AT', 'DT', 'SP'))
U(sq='FIN')
L('UNLK')
U(b=('RD', 'AY'), bd='HI', au=('AY', 'P2', 'AT'))
U()
U(b=('RD', 'AT'), bd='LO')
U()
U(b=('NPF',), au=('AY', 'P4', 'SP'))                               # SP with the final prefetch, An after it (68000)
U(alu=('PASS', 'DT', 'ZERO', 'AY', 'LONG'), sq='FIN')

# TRAP / TRAPV / CHK / ILLEGAL
L('TRAP')
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VTRAP', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12')
L('TRAPV')                                        # taken: the frame follows the prefetch with no idle cycle
U(b=('NPF',), alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VTRAPV', au=('SSP', 'M2', 'AT'), sq='BT', cd='VSET', nxt='EXC12')
U(sq='FIN')
L('CHK')
U(alu=('CHK', 'EAV', 'DX', 'NONE', 'WORD'), fl=1)
U(sq='BT', cd='AUX', nxt='EXC_CHK')               # Dn > bound
U(sq='BT', cd='NSET', nxt='EXC_CHK')              # Dn < 0
U(b=('NPF',))
U(sq='FIN')

# MOVE USP / EXG / EXT / SWAP
L('MVUSP_TO')
U(b=('NPF',), alu=('PASS', 'AY', 'ZERO', 'OSP', 'LONG'))
U(sq='FIN')
L('MVUSP_FROM')
U(b=('NPF',), alu=('PASS', 'OSP', 'ZERO', 'AY', 'LONG'))
U(sq='FIN')
L('EXG')
U(b=('NPF',), alu=('PASS', 'RXE', 'ZERO', 'DT', 'LONG'))
U(alu=('PASS', 'RYE', 'ZERO', 'RXE', 'LONG'), au=('DT', 'ZERO', 'AY'))     # AD_AY = Dy for EXG Dx,Dy (m68ksv_eu)
U(sq='FIN')

# SR / CCR writes: MOVE to SR / CCR, ANDI / ORI / EORI to SR / CCR (the queue is refilled from fpc - 2)
for _lab, _xd, _xs in (('SRW', 'SR', 'WORD'), ('CCRW', 'CCR', 'BYTE')):
    L(_lab)                                       # MOVE to SR / CCR
    U(alu=('DEC', 'CA', 'SR', _xd, _xs), au=('FPC', 'M2', 'AT'))
    U(sq='NXT', nxt='BR_TAKEN')
    L(_lab + 'I')                                 # ANDI / ORI / EORI to SR / CCR
    U(alu=('DEC', 'CA', 'SR', _xd, _xs), au=('FPC', 'M2', 'AT'))
    U()
    U()
    U(sq='NXT', nxt='BR_TAKEN')
# MOVE from SR to Dn (memory form uses RMW with A = SR, no flags)
L('MVFSR_DN')
U(b=('NPF',), alu=('PASS', 'SR', 'ZERO', 'DY', 'WORD'))
U()
U(sq='FIN')

# STOP / RESET
L('STOP')
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'SR', 'WORD'))
U()
U(b=('NPF',))
L('STOP_W')
U(ms='STOPW', sq='FINNC', cd='IRQ', nxt='STOP_W')
L('RESETI')                                       # RESET output asserted for 124 clocks, from the third clock
U()
U(ms='RSTO1')
U(ms='LDCNTRST')
L('RESETI_L')
U(ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='RESETI_L')
U(ms='RSTO0')
U(b=('NPF',))
U(sq='FIN')

# shifts / rotates on Dn
L('SHR')
U(b=('NPF',), alu=('NOP', 'DX', 'DY', 'NONE'), ms='LDCNTSH')          # count register read on port X
U(alu=('SHFI', 'DX', 'DY', 'NONE'), fl=1, fh='LO', sq='BF', cd='CNTNZ', nxt='SHR_E0')
L('SHR_L')
U(alu=('SHF', 'ZERO', 'DY', 'DY'), fl=1, ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='SHR_L')
L('SHR_E')
U(sq='FINC', cd='SZL', nxt='SHR_X')
L('SHR_X')
U(sq='FIN')
L('SHR_E0')                                       # count 0: .l flags again on the long operand (68000)
U(sq='FINC', cd='SZL', nxt='SHR_X0')
L('SHR_X0')
U(alu=('SHFI', 'DX', 'DY', 'NONE'), fl=1, sq='FIN')

# multiply / divide
L('MUL')                                          # 38 + 2n clocks (MULU: n = ones, MULS: n = 01 / 10 pairs)
U(b=('NPF',), alu=('SHFI', 'EAV', 'DX', 'AT', 'LONG'), ms='LDCNTMUL')    # Dn -> AT (SHFI passes B)
# first count step apart: the 68000 loads its PC one word later, and clears Dn's low word here (Z set)
U(ms='CNTDEC', alu=('CLR', 'ZERO', 'DX', 'DX', 'WORD'), fl=1)
L('MUL_L')
U(ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='MUL_L')
U(alu=('NOP', 'EAVM', 'AT', 'NONE', 'LONG'))   # operands into the registered DSP multiplier
U(alu=('MUL', 'EAVM', 'AT', 'DX', 'LONG'), fl=1, sq='FIN')
# DIVU / DIVS: the quotient is computed one bit per micro-cycle, then idle micro-cycles make up the 68000's
# data-dependent time (MC68000 DIVU / DIVS microcode timing, J. Cwik's analysis; checked against the suite, fx68k, MAME):
# DIVU 76 + 2 x (per step of the first 15: 0 if the remainder's msb was set, 1 if it then subtracted, else 2) clocks,
# DIVS 2 x (61 + zeros in quotient bits 15-1 + {-1 / +2 / 0 / +1} by divisor / dividend sign) clocks; overflow found
# at the start: DIVU 10, DIVS 16 (+2 for a negative dividend).
L('DIV')
U(alu=('PASS', 'EAV', 'DX', 'NONE', 'LONG'), ms='DINIT')
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), sq='BT', cd='DIVZ', nxt='DIV_Z')     # PCX for the zero-divide frame
U(sq='BT', cd='DIVOVU', nxt='DIV_OV')
U(sq='BT', cd='DIVOV', nxt='DIV_OVS')
L('DIV_L')
U(ms='DSTEP', sq='BT', cd='CNTGT1', nxt='DIV_L')
U(ms='LDCNTDIV')
L('DIV_W')
U(ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='DIV_W')
U(sq='BT', cd='DIVOV', nxt='DIV_OV')            # late overflow (DIVS quotient out of range)
U(b=('NPF',), alu=('DIVR', 'ZERO', 'DX', 'DX', 'LONG'), fl=1)
U(sq='FIN')
L('DIV_Z')                                         # zero divide: flags as the 68000 microcode leaves them
U(alu=('DIVZ', 'ZERO', 'DX', 'NONE', 'LONG'), fl=1, ms='VDIV0', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12C')
L('DIV_OVS')                                       # DIVS overflow found at the start
U()
U(sq='BT', cd='DVNEG', nxt='DIV_OVN')
L('DIV_OV')
U(b=('NPF',), alu=('DIVO', 'ZERO', 'DX', 'NONE', 'LONG'), fl=1)
U(sq='FIN')
L('DIV_OVN')
U(sq='NXT', nxt='DIV_OV')

# ADDX / SUBX / ABCD / SBCD: register and -(Ay),-(Ax) forms; CMPM
npf_body('XREG', 0, alu=('DEC', 'DY', 'DX', 'DX'), fl=1)
L('XREG2')                                                          # ABCD / SBCD Dy,Dx
U(b=('NPF',), alu=('DEC', 'DY', 'DX', 'NONE'), fl=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DX'), sq='FIN')
L('XREG4')                                                          # ADDX / SUBX .l Dy,Dx
U(b=('NPF',), alu=('DEC', 'DY', 'DX', 'DX'), fl=1, fh='LO', lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DX', 'LONG'), fl=1, fh='CM')
U(sq='FIN')
L('XMEM')                                         # Ax written in its read's first word (68000)
U(au=('AY', 'DEC', 'AY', 'OPW'))
U(b=('RD', 'AY'))
U(au=('AX', 'DEC', 'NONE'))
U(b=('RD', 'AUR'), alu=('PASS', 'DT', 'ZERO', 'IM'), au=('AX', 'DEC', 'AX'), lk=2)
U()
U(b=('NPF',), alu=('DEC', 'IM', 'DT', 'NONE'), fl=1)
U()
U(b=('WR', 'AX'), dw='RESL')
U(sq='FIN')
L('XMEM_L')                                       # .l: An is written in the high-word read's first word (68000)
U(au=('AY', 'M2', 'AT'))
U(b=('RD', 'AT'), bd='LO')
U(au=('AT', 'M2', 'NONE'))
U(b=('RD', 'AUR'), bd='HI', au=('AT', 'M2', 'AY'), lk=2)
U(au=('AX', 'M2', 'AT'))
U(b=('RD', 'AT'), bd='LO', alu=('PASS', 'DT', 'ZERO', 'IM', 'LONG'))
U(au=('AT', 'M2', 'NONE'))
U(b=('RD', 'AUR'), bd='HI', au=('AT', 'M2', 'AX'), lk=2)
# low word (high half not read yet): its flags (68000: with the high-word read); the whole operand next, its flags held
# until the final prefetch
U(alu=('DEC', 'IM', 'DT', 'NONE', 'LONG'), au=('AX', 'P2', 'AT'), fl=1, fh='LO')
U(b=('WR', 'AT'), dw='RESL', alu=('DEC', 'IM', 'DT', 'NONE', 'LONG'), fh='HD')
U()
U(b=('NPF',), alu=('PASS', 'RES', 'ZERO', 'NONE', 'LONG'), fl=1, fh='CM')
U()
U(b=('WR', 'AX'), dw='RESH')
U(sq='FIN')
L('CMPM')                                         # (68000: Ay + 2 per word read, Ax at the end)
U(b=('RD', 'AY'), bd='L1', au=('AY', 'INC', 'AY', 'OPW'), sq='BT', cd='SZL', nxt='CMPM_L')
U()
U(b=('RD', 'AX'), alu=('PASS', 'DT', 'ZERO', 'IM'))
U()
U(b=('NPF',), alu=('CMP', 'IM', 'DT', 'NONE'), fl=1, au=('AX', 'INC', 'AX'))
U(sq='FIN')
L('CMPM_L')
U()
U(b=('RD', 'AY'), bd='LO', au=('AY', 'P2', 'AY'))
U()
U(b=('RD', 'AX'), bd='HI', alu=('PASS', 'DT', 'ZERO', 'IM', 'LONG'))
U(au=('AX', 'P2', 'NONE'))
U(b=('RD', 'AUR'), bd='LO')
U()
U(b=('NPF',), alu=('CMP', 'IM', 'DT', 'NONE', 'LONG'), fl=1, au=('AX', 'INC', 'AX'))
U(sq='FIN')

# TAS on memory (address-only EA first)
L('TASM')
U(b=('TAS', 'AT'), bs='BYTE')
L('TASM_2')
U()
U(dw='TASB')
U()
U()
U(b=('NPF',), alu=('TAS', 'ZERO', 'DT', 'NONE', 'BYTE'), fl=1)
U(sq='FIN')

# MOVEP
L('MOVEP_RM')                                     # memory -> register
U(b=('NPE',), au=('AY', 'D16', 'AT'))
U()
U(b=('RD', 'AT'), bs='BYTE', bd='SHB', au=('AT', 'P2', 'AT'))
U()
U(b=('RD', 'AT'), bs='BYTE', bd='SHB', au=('AT', 'P2', 'AT'), sq='BT', cd='SZL', nxt='MOVEP_RM_L')
U()
L('MOVEP_RM_E')
U(b=('NPF',), alu=('PASS', 'DT', 'ZERO', 'DX'))
U(sq='FIN')
L('MOVEP_RM_L')
U()
U(b=('RD', 'AT'), bs='BYTE', bd='SHB', au=('AT', 'P2', 'AT'), alu=('SWAP', 'ZERO', 'DT', 'DX', 'LONG'), lh=2)
U()
U(b=('RD', 'AT'), bs='BYTE', bd='SHB', au=('AT', 'P2', 'AT'))
U(sq='NXT', nxt='MOVEP_RM_E')
L('MOVEP_MR')                                     # register -> memory (DT = Dx, word form swapped)
U(b=('NPE',), au=('AY', 'D16', 'AT'), alu=('PASS', 'DX', 'ZERO', 'DT', 'LONG'), sq='BT', cd='SZL', nxt='MOVEP_MR_L')
U(alu=('SWAP', 'ZERO', 'DT', 'DT', 'LONG'))
L('MOVEP_MR_2')
U(b=('WR', 'AT'), bs='BYTE', dw='DTB3', au=('AT', 'P2', 'AT'), ms='DTSHL8')
U()
U(b=('WR', 'AT'), bs='BYTE', dw='DTB3', au=('AT', 'P2', 'AT'), ms='DTSHL8')
U()
U(b=('NPF',))
U(sq='FIN')
L('MOVEP_MR_L')
U()
U(b=('WR', 'AT'), bs='BYTE', dw='DTB3', au=('AT', 'P2', 'AT'), ms='DTSHL8')
U()
U(b=('WR', 'AT'), bs='BYTE', dw='DTB3', au=('AT', 'P2', 'AT'), ms='DTSHL8')
U(sq='NXT', nxt='MOVEP_MR_2')

# MOVEM: one routine per direction x size x EA mode (EATAB kinds MVRMW / MVRML / MVMRW / MVMRL). The mask is fetched
# first; every bus cycle follows the previous one with no idle cycle (68000: R->M 8 + 4n, M->R 12 + 4n clocks for (An)).
# M->R reads one extra word after the last register.
def movem_prologue(mode, mr):
    """mask fetch + address into AT; returns the routine's own extra words count (the next word decides on the mask)"""
    if mode in ('AI', 'PI'):
        U(b=('NPE',), ms='LDMASK')
        U()
        return 'AY'                       # the first access uses An directly (AT = An + / - 2 after it)
    if mode == 'PD':
        U(b=('NPE',), ms='LDMASK', au=('AY', 'DEC', 'AT', 'WORD'))
        return 'PD'
    U(b=('NPE',), ms='LDMASK')
    U()
    if mode == 'D16':  U(b=('NPE',), au=('AY', 'D16', 'AT')); return 'AT'
    if mode == 'AW':   U(b=('NPE',), au=('ZERO', 'D16', 'AT')); return 'AT'
    if mode == 'P16':  U(b=('NPE',), au=('FPC', 'BD16', 'AT')); return 'AT'
    if mode == 'D8':   U(au=('AY', 'D8', 'AT')); U(b=('NPE',), au=('AT', 'XN', 'AT')); return 'AT'
    if mode == 'P8':   U(au=('FPC', 'D8M2', 'AT')); U(b=('NPE',), au=('AT', 'XN', 'AT')); return 'AT'
    if mode == 'AL':   U(b=('NPE',), au=('ZERO', 'IRCH', 'AT')); U(); U(b=('NPE',), au=('AT', 'IRCZ', 'AT')); return 'AT'
    raise SystemExit(mode)

MODES = {'AI': 2, 'PI': 3, 'PD': 4, 'D16': 5, 'D8': 6, 'AW': 7, 'AL': 8, 'P16': 9, 'P8': 10}
# shared loops; each ends with the final prefetch (and the An update where the mode needs one)
def movem_loop(lab, mr, lng, pd, bf='DATA'):
    L(lab)
    if not mr:
        st = ('AT', 'M2', 'AT') if pd else ('AT', 'P2', 'AT')
        if not lng:
            U(b=('WR', 'AT'), dw='MRL', au=st, ms='MNEXT')
        else:
            U(b=('WR', 'AT'), dw='MRL' if pd else 'MRH', au=st)
            U()
            U(b=('WR', 'AT'), dw='MRH' if pd else 'MRL', au=st, ms='MNEXT')
        U(sq='BT', cd='MASKNZ', nxt=lab)
        U(b=('NPF',), **(dict(au=('AT', 'P2', 'AY')) if pd else {}))     # -(An): An = address of the last word
        U(sq='FIN')
    else:
        if not lng:
            U(b=('RD', 'AT'), bd='LO', bf=bf, au=('AT', 'P2', 'AT'), alu=('SEXT', 'DT', 'ZERO', 'MREG', 'WORD'), ms='MNEXT')
        else:
            # the high word (read one access earlier) is written with the next read, the low word with the one after (68000)
            U(b=('RD', 'AT'), bd='LO', bf=bf, au=('AT', 'P2', 'AT'), alu=('PASS', 'DT', 'ZERO', 'MREG', 'LONG'), lh=2)
            U()
            U(b=('RD', 'AT'), bd='HI', bf=bf, au=('AT', 'P2', 'AT'), alu=('PASS', 'DT', 'ZERO', 'MREG', 'LONG'), ms='MNEXT')
        U(sq='BT', cd='MASKNZ', nxt=lab)
        U(b=('NPF',), au=('AT', 'M2', 'ATPI'))                           # (An)+: An = address after the last register
        U(sq='FIN')
for _mr in (False, True):
    for _lng in (False, True):
        movem_loop('MVLP_%d%d0' % (_mr, _lng), _mr, _lng, False)
        if _mr:
            movem_loop('MVLP_%d%dP' % (_mr, _lng), _mr, _lng, False, 'PROG')      # PC-relative: program space
            movem_loop('MVLP_%d%dI' % (_mr, _lng), _mr, _lng, False)              # (An)+: no interrupt sample at the end
        else:
            movem_loop('MVLP_%d%d1' % (_mr, _lng), _mr, _lng, True)

for _k, _mr, _lng, _modes in (('MVRMW', False, False, ('AI', 'PD', 'D16', 'D8', 'AW', 'AL')),
                              ('MVRML', False, True, ('AI', 'PD', 'D16', 'D8', 'AW', 'AL')),
                              ('MVMRW', True, False, ('AI', 'PI', 'D16', 'D8', 'AW', 'AL', 'P16', 'P8')),
                              ('MVMRL', True, True, ('AI', 'PI', 'D16', 'D8', 'AW', 'AL', 'P16', 'P8'))):
    _t = [None] * 16
    for _m in _modes:
        lab = '%s_%s' % (_k, _m)
        L(lab); _t[MODES[_m]] = lab
        src = movem_prologue(_m, _mr)
        lp = 'MVLP_%d%d%s' % (_mr, _lng, 'P' if _m in ('P16', 'P8') else '1' if src == 'PD' else
                              'I' if (_mr and _m == 'PI') else '0')
        if not _mr:
            # registers -> memory: the word after the mask / last extension fetch decides; empty mask: final prefetch
            if src == 'AY':
                CODE[-1]['aa'], CODE[-1]['ab'], CODE[-1]['ad'] = 'AY', 'ZERO', 'AT'
                CODE[-1]['sq'], CODE[-1]['cd'], CODE[-1]['nxt'] = 'BT', 'MASKNZ', lp
            else:
                U(sq='BT', cd='MASKNZ', nxt=lp)
            U(b=('NPF',))
            U(sq='FIN')
        else:
            # memory -> registers: the first read is issued unconditionally (a register or the extra word)
            if src == 'AY':
                U(b=('RD', 'AY'), bd='HI' if _lng else 'LO', au=('AY', 'P2', 'AT'))
            else:
                U()
                U(b=('RD', 'AT'), bd='HI' if _lng else 'LO', au=('AT', 'P2', 'ATPI' if _m == 'PI' else 'AT'),
                  **(dict(bf='PROG') if _m in ('P16', 'P8') else {}))
            U(sq='BT', cd='MASKNZ', nxt=lp)
            U(b=('NPF',), au=('AT', 'M2', 'ATPI'))
            U(sq='FIN')
    EATAB[_k] = _t

N68K = len(CODE)            # end of the 68000 microcode; the 68010 routines are appended after it
UA10_EXPORT = ['TASM_NPF', 'DBL1']  # 68010 labels the RTL needs (package U10_*)
UA20_EXPORT = ['TASM_NPF']           # 68020 labels the RTL needs (package U20_*; extended by m68ksv_ucode020.py)
if IS010:
    exec(compile(open(os.path.join(HERE, 'm68ksv_ucode010.py')).read(), os.path.join(HERE, 'm68ksv_ucode010.py'), 'exec'))
N010 = len(CODE)            # end of the 68010 microcode (68020 ROM: 68010 part without loop mode)
if IS020:
    exec(compile(open(os.path.join(HERE, 'm68ksv_ucode020.py')).read(), os.path.join(HERE, 'm68ksv_ucode020.py'), 'exec'))

# ---------------------------------------------------------------------------------------------------------------
# resolve + encode
CODE = [c for c in CODE]
def enc(w, addr):
    v = 0
    for n, wd, cs in FIELDS:
        if n == 'nxt':
            t = w.get('nxt')
            if t is None:
                x = addr + 1
            elif isinstance(t, int):
                x = t
            else:
                assert t in LABELS, 'undefined label ' + t
                x = LABELS[t]
        elif n in ('fl', 'bn', 'ai', 'iq', 'lk', 'pl', 'lh', 'ly', 'rr', 'xw'):
            x = int(w.get(n, 0))
        else:
            c = w.get(n)
            if c is None:
                x = 0
            else:
                assert c in FC[n], 'bad code %s=%s at %d' % (n, c, addr)
                x = FC[n][c]
        assert x < (1 << wd), (n, x, addr)
        assert IS010 or x == 0 or FPOS[n] < UW0, ('68010 field in the 68000 microcode', n, addr)
        assert IS020 or x == 0 or FPOS[n] < UW10, ('68020 field in the 68000 / 68010 microcode', n, addr)
        v |= x << FPOS[n]
    return v

def check():
    # cp5 (m68ksv_eu aepc_f / aeir_n): no instruction-ending word names a bus cycle (an address error never meets a FIN
    # word's dispatch); 68000 family: from a group-0 entry to its last IR / access-word push no word loads pc68, moves
    # IRN / IR or prefetches, so the stacked PC / IR are taken live
    for i, w in enumerate(CODE):
        if w.get('sq') in ('FIN', 'FINC', 'FINNC', 'RSM') and w.get('bus', 'NONE') != 'NONE':
            raise SystemExit('instruction end in a bus word at %d' % i)
    # cp5 (m68ksv_eu fa_d, ft_*): every word that names a bus cycle continues with NXT / BT to words that do not (its
    # second micro-word never starts a cycle, so ba_q still holds its address at a bus error), and the second word of a
    # frame read of the held flags (fx LI0) is no FH_CM word (hold_xvc does not change between a CM word's e3 and e0).
    # Checked on every word, dead ones too: a 68010 / 68020 RTE may resume at any micro-address its frame names
    for i, w in enumerate(CODE):
        if w.get('bus', 'NONE') == 'NONE': continue
        sq = w.get('sq', 'NXT'); t_ = w.get('nxt')
        nx = i + 1 if t_ is None else (t_ if isinstance(t_, int) else LABELS[t_])
        if sq not in ('NXT', 'BT', 'BF'):
            raise SystemExit('bus word with sequencer %s at %d' % (sq, i))
        for s_ in ([nx, i + 1] if sq in ('BT', 'BF') else [nx]):
            if s_ < len(CODE) and CODE[s_].get('bus', 'NONE') != 'NONE':
                raise SystemExit('bus word followed by a bus word at %d' % i)
            if s_ < len(CODE) and w.get('fx') == 'LI0' and CODE[s_].get('fh') == 'CM':
                raise SystemExit('FH_CM word ends a fx LI0 read at %d' % i)
            # (68010 lp_ir: IR does not change in the word that rebuilds a loop, x1 SRF, so its loopable() is current)
            if s_ < len(CODE) and CODE[s_].get('x1') == 'SRF':
                raise SystemExit('x1 SRF word ends a bus cycle at %d' % i)
    if not IS010:
        assert CODE[LABELS['EXC0']].get('ms') == 'LDAEPC' and LABELS['EXC0A'] + 1 == LABELS['EXC0'], 'EXC0 layout'
        i = LABELS['EXC0A']
        while True:
            w = CODE[i]
            if w.get('pu', 'NONE') != 'NONE' or w.get('bus') in ('NPE', 'NPF') or w.get('ms') == 'IRCIR' or \
               w.get('sq') in ('FIN', 'FINC', 'FINNC', 'RSM', 'CONT', 'BODY'):
                raise SystemExit('group-0 entry changes pc68 / IR / IRN before its pushes at %d' % i)
            if w.get('dw') == 'FINFO': break
            assert w.get('sq', 'NXT') == 'NXT' and w.get('nxt') is None, ('group-0 entry not straight-line', i)
            i += 1
    for i, w in enumerate(CODE):
        if w.get('bus', 'NONE') != 'NONE' and i + 1 < len(CODE):
            nw = CODE[i + 1]
            sq = w.get('sq', 'NXT')
            # the fall-through successor must not start a bus cycle
            if sq == 'NXT' and w.get('nxt') is None and nw.get('bus', 'NONE') != 'NONE':
                raise SystemExit('bus conflict at %d' % i)
        # dispatch reads the registered decode result, ready four clocks after the final prefetch starts
        if w.get('sq') in ('FIN', 'FINC', 'FINNC') and w.get('bus', 'NONE') == 'NPF':
            raise SystemExit('FIN in NPF start at %d' % i)
        # 68010: the word that restores AUR from the frame (fx MAUR) never ends a bus cycle (no bus word, no bus word
        # before it): a fault there would have its AUR capture (m68ksv_eu f8cap2, one clock after the e3) see the
        # restored value
        if w.get('bus', 'NONE') != 'NONE':
            sq = w.get('sq', 'NXT')
            succ = []
            if sq in ('NXT', 'BT', 'BF', 'CALL'):
                t_ = w.get('nxt')
                succ.append(i + 1 if t_ is None else (LABELS[t_] if isinstance(t_, str) else t_))
            if sq in ('BT', 'BF'):
                succ.append(i + 1)
            for s_ in succ:
                if s_ < len(CODE) and CODE[s_].get('fx') == 'MAUR':
                    raise SystemExit('fx MAUR after a bus word at %d' % i)
        if w.get('fx') == 'MAUR' and w.get('bus', 'NONE') != 'NONE':
            raise SystemExit('fx MAUR in a bus word at %d' % i)
        # prefetch addresses come from the m68ksv_eu ba_pf sources only
        if w.get('bus') in ('NPE', 'NPF') and w.get('ba', 'FPC') not in ('FPC', 'AT', 'AUR', 'AY', 'AX', 'SP', 'ATIRC', 'DT', 'FA'):
            raise SystemExit('prefetch address source at %d' % i)
        # the multiplier product is valid one clock after its operands: they must be latched one word earlier
        if w.get('op') == 'MUL':
            pw = CODE[i - 1]
            if (pw.get('xa'), pw.get('xb'), pw.get('sq', 'NXT')) != (w.get('xa'), w.get('xb'), 'NXT') or pw.get('nxt') is not None:
                raise SystemExit('MUL operands not latched one word earlier at %d' % i)
        # register read port A is shared by the address unit and the bus address: both must name one register
        ba = w.get('ba')
        if w.get('bus', 'NONE') != 'NONE' and ba in ('AY', 'AX', 'SP') and w.get('aa') in ('AY', 'AX', 'SP') and ba != w['aa']:
            raise SystemExit('port A conflict at %d' % i)
        # register-file copies (m68ksv_eu): copy XN serves X or N, copy BW serves B or D, never both in one word
        xop = w.get('op', 'NOP') != 'NOP' or w.get('ms') in ('LDCNTSH', 'DINIT')
        x_reg = xop and w.get('xa') in ('EAV', 'DX', 'DY', 'AY', 'AX', 'RXE', 'RYE', 'SP', 'OSP', 'CA', 'CTL', 'RC', 'AYLK')
        b_reg = xop and w.get('xb') in ('EAV', 'DX', 'DY', 'AX', 'AY', 'RYE')
        d_reg = w.get('dw') in ('EAVL', 'EAVH', 'EAV1', 'MRL', 'MRH', 'AYL', 'AYH', 'RC1', 'RCL')
        if x_reg and w.get('ab') == 'XN':
            raise SystemExit('register copy XN conflict at %d' % i)
        if b_reg and d_reg:
            raise SystemExit('register copy BW conflict at %d' % i)
        # the address-unit register write at e3 takes the adder output: the word must compute it
        if w.get('ad') in ('AY', 'AX', 'SP', 'ATPI') and w.get('aa', 'ZERO') == 'ZERO' and w.get('ab', 'ZERO') == 'ZERO':
            raise SystemExit('AU register write without an AU operation at %d' % i)

# exception sequences (and reset) run word cycles whatever the size of the instruction they interrupt
for _i in list(range(LABELS['RESET'], LABELS['TLFIN'])) + list(range(LABELS['EXC12'], LABELS['HALT'])):
    if CODE[_i].get('bus', 'NONE') in ('RD', 'WR') and 'bs' not in CODE[_i]:
        CODE[_i]['bs'] = 'WORD'
CODE[LABELS['MV_PD'] + 2]['ai'] = 1
# interrupt sample points: every final-prefetch word, except RESET, whose IRC -> IR word is its second micro-word
for _w in CODE:
    if _w.get('bus') == 'NPF': _w['iq'] = 1
# where the 68000's last IRC -> IR micro-word comes with another access (MAME m68000-sdf.cpp word names in brackets),
# the sample moves to the micro-instruction that starts that access and the final prefetch does not sample
def _iq(lab, on, off):
    for o in on:
        assert CODE[LABELS[lab] + o].get('bus', 'NONE') != 'NONE', (lab, o)
        CODE[LABELS[lab] + o]['iq'] = 1
    for o in off:
        assert CODE[LABELS[lab] + o].get('bus') == 'NPF', (lab, o)
        CODE[LABELS[lab] + o]['iq'] = 0
_iq('MV_PI', [0], [2]); _iq('MV_PI_L', [1], [3])                  # rmiw1 / mmiw1 / mmil2: the (last) write
for _p in ('R', 'M'):
    _iq('MVL_PI_' + _p, [2], [4])                                  # rmil2 / mmil2: low-word write
_iq('MVL_AI_R', [2], [4])                                          # rmrl2
_iq('MVL_D16_R', [4], [6]); _iq('MVL_D8_R', [5], [7])              # rmdl3
_iq('XMEM', [3], [5])                                              # asbb4 / asxw4: destination read
_iq('XMEM_L', [9], [11])                                           # asxl7: first write
_iq('CMPM', [2], [4]); _iq('CMPM_L', [3], [7])                     # cmmw3 / cmml4
_iq('LINK', [2], [6])                                              # link3: first push
_iq('UNLK', [2], [4])                                              # unlk2: low-word read
_iq('MOVEP_RM', [4], []); _iq('MOVEP_RM_L', [3], []); _iq('MOVEP_RM_E', [], [0])   # mpiw3: last read
for _k in ('MVMRW_PI', 'MVMRL_PI'):                                # popm2: first data read
    _iq(_k, [2], [4])
_iq('MVLP_10I', [], [2]); _iq('MVLP_11I', [], [4])
# the 68000's PC-register loads (field pu): where fx68k's PC register is loaded relative to m68ksv's micro-words, and
# which m68ksv value it takes (verify/tools/pcderive.py on lockstep PCTRACE runs: each load lands on the same m68ksv
# word, the e0 = fx68k T1 (AU -> PC) or the e2 = fx68k T3 (bus -> PC), and equals one m68ksv value there). Words
# seen with both a T1 and an e2 load from fpc have the T1 code (fpc does not change between them). MOVEM: the word and
# long routines of one direction and EA mode share the prologue, so a load seen in one size is set in both. Not modelled: bser6's
# PC <- fault address (EXC0+10), which no frame can stack (any fault before the refill halts).
PU = {
    ('RDW_PD', 0): 'T1FPC', ('RDW_AW', 0): 'T1FPC', ('RDW_AL', 2): 'T1FPC', ('RDL_AW', 0): 'T1FPC',
    ('RDL_AL', 2): 'T1FPC', ('ADDR_AW', 0): 'T1FPC', ('ADDR_AL', 2): 'T1FPC', ('TAS_PD', 0): 'T1FPC',
    ('ALU_DN', 0): 'T1FPC', ('ALU_DN2', 0): 'T1FPC', ('ALU_AN2', 0): 'T1FPC', ('ALU_DN4', 0): 'T1FPC',
    ('ALU_AN4', 0): 'T1FPC', ('RMW', 0): 'T1FPC', ('RMEM2', 0): 'T1FPC', ('RDY', 0): 'T1FPC',
    ('RDY2', 0): 'T1FPC', ('RDY4', 0): 'T1FPC', ('RDYB', 0): 'T1FPC', ('RDYBC', 0): 'T1FPC',
    ('ADDQA', 0): 'T1FPC', ('MV_AI', 0): 'T1FPC', ('MV_PI', 0): 'T1FPC', ('MV_PD', 0): 'T1FPC',
    ('MV_D16', 0): 'T1FPC', ('MV_D8', 1): 'T1FPC', ('MV_AW', 0): 'T1FPC', ('MV_ALA', 2): 'T1FPC',
    ('MV_ALB', 0): 'T1FPC', ('MVL_AI_R', 0): 'T1FPC', ('MVL_PI_R', 0): 'T1FPC', ('MVL_AI_M', 0): 'T1FPC',
    ('MVL_PI_M', 0): 'T1FPC', ('MVL_D16_R', 0): 'T1FPC', ('MVL_D8_R', 1): 'T1FPC', ('MVL_D16_M', 0): 'T1FPC',
    ('MVL_D8_M', 1): 'T1FPC', ('MVL_AW', 0): 'T1FPC', ('MVL_ALA', 2): 'T1FPC', ('MVL_PD', 0): 'T1FPC',
    ('MVL_ALB', 0): 'T1FPC', ('DBCC', 2): 'T1AUR', ('DB_EXP', 0): 'T1AUR', ('JSR_D16', 2): 'T1PCX',
    ('JSR_D8', 4): 'T1PCX', ('JSR_AW', 1): 'T1FPC', ('JSR_AL', 2): 'T1FPC', ('JSR_P16', 2): 'T1PCX',
    ('JSR_P8', 4): 'T1PCX', ('LEA_AI', 0): 'T1FPC', ('PEA_AI', 0): 'T1FPC', ('PEA_D16', 2): 'T1FPC',
    ('PEA_D8', 4): 'T1FPC', ('PEA_AW', 0): 'T1FPC', ('PEA_AL', 2): 'T1FPC', ('PEA_P16', 2): 'T1FPC',
    ('PEA_P8', 4): 'T1FPC', ('LINK', 1): 'T1FPC', ('UNLK', 0): 'T1FPC', ('MVUSP_TO', 0): 'T1FPC',
    ('MVUSP_FROM', 0): 'T1FPC', ('EXG', 0): 'T1FPC', ('MVFSR_DN', 0): 'T1FPC', ('SHR', 0): 'T1FPC',
    ('DIV', 0): 'T1FPC', ('XREG', 0): 'T1FPC', ('XREG2', 0): 'T1FPC', ('XREG4', 0): 'T1FPC',
    ('XMEM', 0): 'T1FPC', ('XMEM_L', 0): 'T1FPC', ('CMPM', 0): 'T1FPC', ('TASM_2', 1): 'T1FPC',
    ('MVRMW_AI', 1): 'T1FPC', ('MVRMW_PD', 1): 'T1FPC', ('MVRMW_D16', 3): 'T1FPC', ('MVRMW_AW', 3): 'T1FPC',
    ('MVRML_AI', 1): 'T1FPC', ('MVRML_PD', 1): 'T1FPC', ('MVRML_D16', 3): 'T1FPC', ('MVRML_AW', 3): 'T1FPC',
    ('MVMRW_AI', 2): 'T1FPC', ('MVMRW_PI', 2): 'T1FPC', ('MVMRW_D16', 4): 'T1FPC', ('MVMRW_D8', 6): 'T1FPC',
    ('MVMRW_AW', 4): 'T1FPC', ('MVMRW_P16', 4): 'T1FPC', ('MVMRW_P8', 6): 'T1FPC', ('MVMRL_AI', 2): 'T1FPC',
    ('MVMRL_PI', 2): 'T1FPC', ('MVMRL_D16', 4): 'T1FPC', ('MVMRL_D8', 6): 'T1FPC', ('MVMRL_AW', 4): 'T1FPC',
    ('MVMRL_AL', 6): 'T1FPC', ('MVMRL_P16', 4): 'T1FPC', ('EXC12', 0): 'PCX', ('VECTAIL', 0): 'VEC',
    ('VECJMP_G0', 1): 'FPC', ('JMPDT', 2): 'FPC', ('EXC12C', 0): 'FPCM2', ('EXC_INT', 1): 'PCX',
    ('IMMW', 0): 'FPC', ('IMML', 2): 'FPC', ('NOP', 0): 'FPC', ('RMW', 1): 'FPCM2', ('RMEM', 0): 'FPC',
    ('SCC_D', 0): 'FPC', ('MOVEQ', 0): 'FPC', ('MV_DN', 0): 'FPC', ('MV_AN', 0): 'FPC', ('MV_D16', 4): 'FPC',
    ('MV_D8', 5): 'FPC', ('MV_AW', 4): 'FPC', ('MV_ALA', 6): 'FPC', ('MV_ALB_T', 0): 'FPC',
    ('MV_ALB_T', 2): 'FPC', ('MVL_D16_R', 6): 'FPC', ('MVL_D8_R', 7): 'FPC', ('MVL_D16_M', 6): 'FPC',
    ('MVL_D8_M', 7): 'FPC', ('MVL_AW', 6): 'FPC', ('MVL_ALA', 8): 'FPC', ('BCC_S', 2): 'FPC',
    ('BR_SKIPW', 0): 'FPC', ('BR_SKIPW', 2): 'FPC', ('DB_SKIPW', 2): 'FPC', ('BR_TAKEN', 0): 'FPCM2',
    ('BR_T2', 0): 'FPC', ('BSR_TGT', 0): 'AT', ('JMP_AI', 2): 'FPC', ('JMP_D16', 3): 'FPC', ('JMP_D8', 5): 'FPC',
    ('JMP_AW', 3): 'FPC', ('JMP_AL', 4): 'FPC', ('JMP_P16', 3): 'FPC', ('JMP_P8', 5): 'FPC',
    ('JSR_AI', 6): 'FPC', ('JSR_D16', 7): 'FPC', ('JSR_D8', 9): 'FPC', ('JSR_AL', 8): 'FPC',
    ('JSR_P16', 7): 'FPC', ('JSR_P8', 9): 'FPC', ('LEA_D16', 2): 'FPC', ('LEA_D8', 4): 'FPC',
    ('LEA_AW', 2): 'FPC', ('LEA_AL', 2): 'FPC', ('LEA_AL', 4): 'FPC', ('LEA_P16', 2): 'FPC',
    ('LEA_P8', 4): 'FPC', ('PEA_AW', 6): 'FPC', ('PEA_AL', 8): 'FPC', ('TRAPV', 1): 'FPCM2', ('CHK', 1): 'FPCM2',
    ('CHK', 3): 'FPC', ('RESETI', 0): 'FPC', ('MUL_L', 0): 'FPCM2', ('MOVEP_RM_E', 0): 'FPC',
    ('MOVEP_MR_2', 4): 'FPC', ('MVRMW_D16', 0): 'FPC', ('MVRMW_D8', 2): 'FPCP2', ('MVRMW_AW', 0): 'FPC',
    ('MVRML_D16', 0): 'FPC', ('MVRML_D8', 2): 'FPCP2', ('MVRML_AW', 0): 'FPC', ('MVMRW_D16', 0): 'FPC',
    ('MVMRW_D8', 0): 'FPC', ('MVMRW_AW', 0): 'FPC', ('MVMRW_P16', 0): 'FPC', ('MVMRW_P8', 0): 'FPC',
    ('MVMRL_D16', 0): 'FPC', ('MVMRL_D8', 0): 'FPC', ('MVMRL_AW', 0): 'FPC', ('MVMRL_AL', 0): 'FPC',
    ('MVMRL_AL', 4): 'FPC', ('MVMRL_P16', 0): 'FPC', ('MVMRL_P8', 0): 'FPC', ('JSR_AW', 7): 'FPC',
    ('MVMRL_P8', 6): 'T1FPC', ('MVMRW_AL', 0): 'FPC', ('MVMRW_AL', 4): 'FPC', ('MVMRW_AL', 6): 'T1FPC',
    ('MVRML_AL', 0): 'FPC', ('MVRML_AL', 5): 'T1FPC', ('MVRMW_AL', 0): 'FPC', ('MVRMW_AL', 5): 'T1FPC'}
# routines split from one above (same bus and PC structure, different register / flag timing) share its PC loads
for _new, _old in (('ALU_CP2', 'ALU_DN2'), ('ALU_CPA', 'ALU_AN2'), ('RDY2L', 'RDY2'), ('RDY2N', 'RDY2'), ('RDY2T', 'RDY2'),
                   ('RMWB', 'RMW'), ('RTSJ', 'JMPDT'), ('MV_D16R', 'MV_D16'), ('MV_D8R', 'MV_D8'), ('DB_T2', 'BR_T2')):
    for (_lab, _o), _v in list(PU.items()):
        if _lab == _old: PU[(_new, _o)] = _v
for (_lab, _o), _v in PU.items():
    assert CODE[LABELS[_lab] + _o].get('pu') is None, (_lab, _o)
    CODE[LABELS[_lab] + _o]['pu'] = _v
# address error after a bus wait (BR / HALT held the cycle): fx68k runs the cycle's second micro-word during the wait,
# so when that word loads the PC at its T1 (pu T1*) the fault stacks fpc (the value it loads there - lockstep HALT / BR
# sweeps: DBcc, JSR (d16,An) / (d8,An,Xn) / (d16,PC) / (d8,PC,Xn), MOVEM (d8,An,Xn) / (d8,PC,Xn) -> registers)
PL = []
for _i, _w in enumerate(CODE):
    if _w.get('bus', 'NONE') == 'NONE': continue
    _sq = _w.get('sq', 'NXT')
    _nx = LABELS[_w['nxt']] if isinstance(_w.get('nxt'), str) else _w.get('nxt', _i + 1)
    _succ = [_i + 1] if _sq == 'NXT' and _w.get('nxt') is None else [_nx] if _sq == 'NXT' else \
            [_nx, _i + 1] if _sq in ('BT', 'BF') else []
    if _succ and all(CODE[_k].get('pu', 'NONE') in ('T1FPC', 'T1PCX', 'T1AUR') for _k in _succ):
        _w['pl'] = 1; PL.append(_i)
# (An)+ word reads whose An write sits in the cycle's second micro-word (MAME pinw2; CMPM.w alike)
for _lab, _o in (('RDW_PI', 0), ('CMPM', 0)):
    assert CODE[LABELS[_lab] + _o].get('ad') in ('AY', 'AX'), (_lab, _o)
    CODE[LABELS[_lab] + _o]['lk'] = 1
# RESET: rset2, its second micro-word, samples (no access); the final prefetch does not
CODE[LABELS['RESETI'] + 1]['iq'] = 1
CODE[LABELS['RESETI_L'] + 2]['iq'] = 0
assert CODE[LABELS['RESETI_L'] + 2].get('bus') == 'NPF'
# I/N = 1 for exception-processing accesses (MAME SSW_N: interrupt stacking and IACK, group-0 stacking)
for _i in range(LABELS['EXC0'], min(v for v in LABELS.values() if v > LABELS['EXC0'])):     # EXC0's own pushes only
    if CODE[_i].get('bus', 'NONE') == 'WR': CODE[_i]['bn'] = 1
for _i in range(LABELS['EXC_INT'], LABELS['EXC_INT'] + 15):
    if CODE[_i].get('bus', 'NONE') in ('WR', 'IACK'): CODE[_i]['bn'] = 1

check()

# ---------------------------------------------------------------------------------------------------------------
# checkpoint 6: 68000-family microcode compaction (DESIGN.md 3). The routines above share many identical tails (idle
# words, final prefetch, FIN); merging words that behave the same brings the 68000-family ROM under 1,024 words, the
# cheapest M10K depth (1,024 x 10 per block instead of 2,048 x 5). Two words behave the same when every field but nxt is
# equal and their successors behave the same (partition refinement). Successors as m68ksv_eu forms them: nxt for NXT /
# CALL / BT / BF / FINC / FINNC, plus upc + 1 for BT / BF / CALL (placed right after the word; a copy is made where the
# first one is not); FIN / CONT / BODY / RET / RSM ignore nxt. The reset / exception block (RESET .. HALT_L) and the Bcc /
# BSR routines (BCC_S .. DBCC) stay word for word at their addresses: m68ksv_eu compares upc / ua_r with those labels
# (package UA_*, the same in the 68010 / 68020 ROMs, which are not compacted - their micro-addresses are architectural:
# format-8 / format-B frames store them). Proof: a bisimulation check from every old address (fields equal, successors
# related, every label related). M68KSV_UAREL=<file> writes the old / new address pairs (A/B harness: dbg_upc).
# labels m68ksv_eu names (package UA_*): the same address in every ROM set (checked by the driver at the top)
SHARED_UA = ['RESET', 'TLFIN', 'EXC0', 'HALT', 'EXC0A', 'HALTA', 'EXC_ILL', 'EXC_PRIV', 'EXC_INT', 'EXC_TRACE', 'EXC_LA',
             'EXC_LF', 'VECJMP_G0', 'BCC_S', 'BCC_W', 'BSR_S', 'BSR_W']
def compact000():
    global CODE
    old = list(CODE); N = len(old)
    sqs = [w.get('sq', 'NXT') for w in old]
    USES = ('NXT', 'CALL', 'BT', 'BF', 'FINC', 'FINNC')      # sequencer codes that read nxt (m68ksv_eu upc_next)
    POS = ('BT', 'BF', 'CALL')                                # ... and upc + 1
    def tgt(i):
        t = old[i].get('nxt')
        return i + 1 if t is None else (t if isinstance(t, int) else LABELS[t])
    def succ(i):
        s = []
        if sqs[i] in USES: s.append(('t', tgt(i)))
        if sqs[i] in POS: s.append(('f', i + 1))
        return s
    r0 = range(LABELS['RESET'], LABELS['HALT_L'] + 1)
    r1 = range(LABELS['BCC_S'], LABELS['DBCC'])
    assert r0.start == 0 and r0.stop <= r1.start
    pinned = set(r0) | set(r1)
    for k in SHARED_UA: assert LABELS[k] in pinned, ('RTL-named label outside the pinned blocks', k)
    for i in range(N):
        for _, s_ in succ(i): assert s_ < N, ('successor beyond the ROM', i)
        if sqs[i] in POS: assert (i in pinned) == (i + 1 in pinned), ('upc + 1 link across a pinned block edge', i)
    assert all(v < N for v in LABELS.values())
    nm = ((1 << FW['nxt']) - 1) << FPOS['nxt']
    # partition refinement
    ids = {}
    cls = [ids.setdefault(('pin', i) if i in pinned else (enc(old[i], i) & ~nm, sqs[i]), len(ids)) for i in range(N)]
    while True:
        ids2 = {}
        new = [ids2.setdefault((cls[i],) + tuple((t, cls[s_]) for t, s_ in succ(i)), len(ids2)) for i in range(N)]
        if len(ids2) == len(ids): break
        ids, cls = ids2, new
    # layout: pinned words in place; the first word of every other class in the old order; an upc + 1 successor right
    # after its BT / BF / CALL word (a copy when its class is already placed); a chain never runs into the Bcc block
    SIZE = 1024
    node = [None] * SIZE
    placed = {}
    for i in sorted(pinned):
        node[i] = i; placed[cls[i]] = i
    cur = r0.stop; prev_pos = False
    for i in range(N):
        if i in pinned:
            prev_pos = False; continue
        c = cls[i]
        if c in placed and not prev_pos:
            continue
        if not prev_pos:
            n_ = 1; j = i
            while sqs[j] in POS: j += 1; n_ += 1
            if cur < r1.stop and cur + n_ > r1.start: cur = r1.stop
        assert cur < SIZE and node[cur] is None, 'compacted 68000 microcode does not fit 1,024 words'
        node[cur] = i
        placed.setdefault(c, cur)
        cur += 1
        prev_pos = sqs[i] in POS
    end = max(cur, r1.stop)
    ncode = []
    for a in range(end):
        i = node[a]
        if i is None:
            ncode.append({}); continue             # gap before the Bcc block: never reached (idle word)
        w = dict(old[i]); w.pop('nxt', None)
        if sqs[i] in USES:
            nt = placed[cls[tgt(i)]]
            if nt != a + 1: w['nxt'] = nt
        if sqs[i] in POS: assert node[a + 1] is not None and cls[node[a + 1]] == cls[i + 1]
        ncode.append(w)
    nl = {k: placed[cls[v]] for k, v in LABELS.items()}
    # bisimulation check: from every old address, the word at its new address has the same fields (nxt aside) and
    # sequencer code, and the successors are related again
    rel = set(); todo = [(i, placed[cls[i]]) for i in range(N)] + [(LABELS[k], nl[k]) for k in LABELS]
    while todo:
        i, a = todo.pop()
        if (i, a) in rel: continue
        rel.add((i, a))
        wn = ncode[a]
        assert (enc(wn, a) & ~nm) == (enc(old[i], i) & ~nm) and wn.get('sq', 'NXT') == sqs[i], ('compaction: word differs', i, a)
        if sqs[i] in USES:
            tn = wn.get('nxt')
            todo.append((tgt(i), a + 1 if tn is None else tn))
        if sqs[i] in POS: todo.append((i + 1, a + 1))
    for k in SHARED_UA: assert nl[k] == LABELS[k], k
    CODE[:] = ncode
    LABELS.clear(); LABELS.update(nl)
    if os.environ.get('M68KSV_UAREL'):
        with open(os.environ['M68KSV_UAREL'], 'w') as f_:
            for i, a in sorted(rel): f_.write('%d %d\n' % (i, a))
    return N, len(set(cls)), len(ncode)

COMPACT = None
LABELS_PRE = dict(LABELS)          # before the compaction (68000 family): the addresses the 68010 / 68020 ROMs keep
if CPU == 68000:
    COMPACT = compact000()
    assert len(CODE) <= 1024
    check()

# ---------------------------------------------------------------------------------------------------------------
# decode: opcode[15:6] -> 4 classes (by source category Dn / An / memory / #imm) + memory-mode validity code
CLASSES = {}      # name -> dict(k1, k2, body, aluop, ca, sz, nofl, priv)
CLS_ORDER = []
def C(name, body, k1='NONE', k2='NONE', op='NOP', ca='ZERO', sz='STD', nofl=0, priv=0):
    if name in CLASSES:
        return name
    CLASSES[name] = dict(body=body, k1=k1, k2=k2, op=op, ca=ca, sz=sz, nofl=nofl, priv=priv)
    CLS_ORDER.append(name)
    return name

KINDS = ['NONE', 'RD', 'ADDR', 'IMM', 'JMP', 'JSR', 'LEA', 'PEA', 'IMMB', 'TAS', 'MVRM', 'MVMR', 'XWD', 'CLRW']
SZR = ['STD', 'MOVE', 'A8', 'B', 'W', 'L', 'BIT', 'B6']
CAS = ['ZERO', 'DX', 'IM', 'QUICK', 'SR', 'DY', 'EAV', 'CCR']    # decoded ALU A source (xa=CA); CCR: 68010
VALID = ['NOEA', 'ALL', 'ALT', 'CTRL', 'MALT', 'CTRLPD', 'CTRLPI', 'DATA',
         'CALT']                                    # 68020 (4-bit validity in its drom1): alterable control modes

ILL = C('ILL', 'EXC_ILL')
C('LINEA', 'EXC_LA')
C('LINEF', 'EXC_LF')

def mode_ok(valid, mi):
    if valid == 'NOEA': return True
    if mi > 11: return False
    s = {'ALL': range(0, 12), 'ALT': range(0, 9), 'CTRL': [2, 5, 6, 7, 8, 9, 10], 'MALT': [2, 3, 4, 5, 6, 7, 8],
         'CALT': [2, 5, 6, 7, 8],
         'CTRLPD': [2, 4, 5, 6, 7, 8], 'CTRLPI': [2, 3, 5, 6, 7, 8, 9, 10], 'DATA': [0] + list(range(2, 12))}[valid]
    return mi in s

def decode_hi(hi):
    """hi = opcode[15:6]. returns (dict cat -> class name, validity for the memory category)"""
    op = hi << 6
    line = op >> 12
    r = {'m0': ILL, 'm1': ILL, 'mm': ILL, 'mi': ILL}
    v = 'ALL'
    o8 = (op >> 8) & 1
    s76 = (op >> 6) & 3
    def every(c):
        for k in r: r[k] = c
    def ea_cls(m0=None, m1=None, mm=None, mi=None):
        if m0: r['m0'] = m0
        if m1: r['m1'] = m1
        if mm: r['mm'] = mm
        if mi: r['mi'] = mi
    if line == 0:
        if o8 == 1:
            # dynamic bit ops / MOVEP
            bop = s76
            names = ['BTST', 'BCHG', 'BCLR', 'BSET']
            r['m1'] = C('MOVEP_RM' if bop < 2 else 'MOVEP_MR', 'MOVEP_RM' if bop < 2 else 'MOVEP_MR', sz='B6')
            r['m0'] = C(names[bop] + '_RD', ['RDY2T', 'RDYB', 'RDYBC', 'RDYB'][bop], op='BIT', ca='DX', sz='BIT')
            if bop == 0:
                r['mm'] = C('BTST_RM', 'RMEM', k1='RD', op='BIT', ca='DX', sz='BIT')
                r['mi'] = C('BTST_RI', 'RMEM2', k1='RD', op='BIT', ca='DX', sz='BIT')
                v = 'DATA'
            else:
                r['mm'] = C(names[bop] + '_RM', 'RMWB', k1='RD', op='BIT', ca='DX', sz='BIT')
                if DEC010 and bop == 2:     # 68010: BCLR Dn,<ea> 10(1/1) + ea (table 7-17)
                    r['mm'] = C('BCLR_RM10', 'RMWB10', k1='RD', op='BIT', ca='DX', sz='BIT')
                v = 'ALT'
            return r, v
        sub = (op >> 9) & 7
        if sub == 4:   # static bit ops
            bop = s76
            names = ['BTST', 'BCHG', 'BCLR', 'BSET']
            r['m0'] = C(names[bop] + '_ID', ['RDY2T', 'RDYB', 'RDYBC', 'RDYB'][bop], k1='IMMB', op='BIT', ca='IM', sz='BIT')
            if bop == 0:
                r['mm'] = C('BTST_IM', 'RMEM', k1='IMMB', k2='RD', op='BIT', ca='IM', sz='BIT')
                v = 'DATA'
            else:
                r['mm'] = C(names[bop] + '_IM', 'RMWB', k1='IMMB', k2='RD', op='BIT', ca='IM', sz='BIT')
                if DEC010 and bop == 2:     # 68010: BCLR #,<ea> 14(2/1) + ea
                    r['mm'] = C('BCLR_IM10', 'RMWB10', k1='IMMB', k2='RD', op='BIT', ca='IM', sz='BIT')
                v = 'ALT'
            return r, v
        if DEC010 and sub == 7 and s76 != 3:      # MOVES (68010): extension word first, then the address
            r['mm'] = C('MOVES10', 'MOVES10', k1='XWD', k2='ADDR', priv=1)
            return r, 'MALT'
        if DEC020 and s76 == 3 and sub in (0, 1, 2):     # CHK2 / CMP2 .B / .W / .L (68020)
            r['mm'] = C('CHK2_' + 'BWL'[sub], 'CHK220', k1='XWD', k2='ADDR', sz='BWL'[sub])
            return r, 'CTRL'
        if DEC020 and s76 == 3 and sub in (5, 6, 7):     # CAS .B / .W / .L, CAS2 .W / .L (68020)
            r['mm'] = C('CAS_' + 'BWL'[sub - 5], 'CAS20', k1='XWD', k2='ADDR', sz='BWL'[sub - 5])
            if sub != 5:
                r['mi'] = C('CAS2_' + 'BWL'[sub - 5], 'CAS220', sz='BWL'[sub - 5])
            return r, 'MALT'
        if s76 == 3 or sub == 7:
            return r, 'NOEA'      # MOVES (010+) / CAS etc: illegal on the 68000
        opn = {0: 'OR', 1: 'AND', 2: 'SUB', 3: 'ADD', 5: 'EOR', 6: 'CMP'}.get(sub)
        if opn is None:
            return r, 'NOEA'
        alu = {'OR': 'OR', 'AND': 'AND', 'SUB': 'SUB', 'ADD': 'ADD', 'EOR': 'EOR', 'CMP': 'CMP'}[opn]
        r['m0'] = C(opn + 'I_D' + str(s76), ('RDY2' if opn == 'CMP' else 'RDY4') if s76 == 2 else 'RDY', k1='IMM', op=alu, ca='IM')
        if DEC010 and opn == 'CMP' and s76 == 2:     # 68010: CMPI.l #,Dn 12(3/0) (table 7-11; 68000: 14)
            r['m0'] = C('CMPI_D2_10', 'RDY', k1='IMM', op=alu, ca='IM')
        elif DEC010 and s76 == 2:                    # 68010: ADDI / SUBI / ANDI / ORI / EORI .l #,Dn 14(3/0) (68000: 16)
            r['m0'] = C(opn + 'I_D2_10', 'RDY2C10', k1='IMM', op=alu, ca='IM')
        if opn == 'CMP':
            r['mm'] = C('CMPI_M', 'RMEM', k1='IMM', k2='RD', op='CMP', ca='IM')
            if DEC020:                        # 68020: CMPI #,(d16,PC) / (d8,PC,Xn) (data modes, no #imm)
                return r, 'DATA'
        else:
            r['mm'] = C(opn + 'I_M', 'RMW', k1='IMM', k2='RD', op=alu, ca='IM')
        if opn in ('OR', 'AND', 'EOR') and s76 < 2:
            if s76 == 0:
                r['mi'] = C(opn + 'I_CCR', 'CCRWI', k1='IMM', op=alu, ca='IM', sz='B')
            else:
                r['mi'] = C(opn + 'I_SR', 'SRWI', k1='IMM', op=alu, ca='IM', sz='W', priv=1)
        v = 'ALT'
        return r, v
    if line in (1, 2, 3):
        dmode = (op >> 6) & 7
        dreg = (op >> 9) & 7
        szn = {1: 'B', 3: 'W', 2: 'L'}[line]
        if dmode == 1:
            if line == 1:
                return r, 'ALL'
            body = 'MV_AN'
        elif dmode == 7:
            if dreg == 0: body = 'MV_AW'
            elif dreg == 1: body = 'MV_ALB'
            else: return r, 'ALL'
        else:
            body = ['MV_DN', None, 'MV_AI', 'MV_PI', 'MV_PD', 'MV_D16', 'MV_D8'][dmode]
        nm = 'MOVE_%s_%s' % (szn, body)
        c = C(nm, body, k1='RD', op='PASS', sz='MOVE')
        if body in ('MV_D16', 'MV_D8'):            # register / #imm sources: their own body (flag timing)
            every(c)
            cr = C(nm + 'G', body + 'R', k1='RD', op='PASS', sz='MOVE')
            r['m0'] = r['mi'] = cr
            if line != 1: r['m1'] = cr
        elif body == 'MV_ALB':
            ca = C('MOVE_%s_MV_ALA' % szn, 'MV_ALA', k1='RD', op='PASS', sz='MOVE')
            r['m0'] = r['m1'] = r['mi'] = ca
            r['mm'] = c
        else:
            every(c)
        if szn == 'L' and body not in ('MV_DN', 'MV_AN'):
            lb = {'MV_AI': ('MVL_AI_R', 'MVL_AI_M'), 'MV_PI': ('MVL_PI_R', 'MVL_PI_M'), 'MV_PD': ('MVL_PD', 'MVL_PD'),
                  'MV_D16': ('MVL_D16_R', 'MVL_D16_M'), 'MV_D8': ('MVL_D8_R', 'MVL_D8_M'), 'MV_AW': ('MVL_AW', 'MVL_AW'),
                  'MV_ALB': ('MVL_ALA', 'MVL_ALB')}[body]
            cr = C(nm + 'R', lb[0], k1='RD', op='PASS', sz='MOVE')
            r['m0'] = r['mi'] = cr
            if line != 1: r['m1'] = cr
            if DEC010 and body == 'MV_PD':    # 68010: MOVE.L Dn / An,-(An) 14(1/2) (table 7-7)
                cr10 = C(nm + 'R10', 'MVL_PD10', k1='RD', op='PASS', sz='MOVE')
                r['m0'] = cr10
                if line != 1: r['m1'] = cr10
            r['mm'] = C(nm + 'M', lb[1], k1='RD', op='PASS', sz='MOVE')
        if line == 1:
            r['m1'] = ILL                     # MOVE.b An,<ea> is illegal
        return r, 'ALL'
    if line == 4:
        o = op & 0xffc0
        if o8 == 1:
            if s76 == 3:
                r['mm'] = C('LEA', 'EXC_ILL', k1='LEA', sz='L')
                if DEC020 and ((op >> 9) & 7) == 4:        # EXTB.L Dn (68020: 49C0)
                    r['m0'] = C('EXTB20', 'EXTB20', sz='L')
                return r, 'CTRL'
            if s76 == 2:
                c = C('CHK', 'CHK', k1='RD', sz='W')
                ea_cls(m0=c, mm=c, mi=c)
                return r, 'ALL'
            if DEC020 and s76 == 0:           # CHK.L <ea>,Dn (68020)
                c = C('CHKL20', 'CHKL20', k1='RD', sz='L')
                ea_cls(m0=c, mm=c, mi=c)
                return r, 'ALL'
            return r, 'NOEA'                  # CHK.l (020)
        sub = (op >> 9) & 7
        if sub in (0, 1, 2, 3) and s76 != 3:
            nm = ['NEGX', 'CLR', 'NEG', 'NOT'][sub]
            alu = ['NEGX', 'CLR', 'NEG', 'NOT'][sub]
            r['m0'] = C(nm + '_D' + str(s76), 'RDY2L' if s76 == 2 else 'RDY', op=alu)
            r['mm'] = C(nm + '_M', 'RMW', k1='RD', op=alu)
            if DEC010 and nm == 'CLR':            # 68010: CLR does not read its destination
                r['mm'] = C('CLR_M10', 'EXC_ILL', k1='CLRW', op='CLR')
            return r, 'ALT'
        if o == 0x40c0:   # MOVE from SR
            r['m0'] = C('MVFSR_D', 'MVFSR_DN', sz='W')
            r['mm'] = C('MVFSR_M', 'RMW', k1='RD', op='PASS', ca='SR', sz='W', nofl=1)
            if DEC010:    # 68010: privileged, no read of a memory destination
                r['m0'] = C('MVFSR_D10', 'MVFSR_DN10', sz='W', priv=1)
                r['mm'] = C('MVFSR_M10', 'MVFSR_M10', k1='ADDR', sz='W', priv=1)
            return r, 'ALT'
        if o == 0x42c0:   # MOVE from CCR (010+)
            if DEC010:
                r['m0'] = C('MVFCCR_D10', 'MVFCCR_DN10', sz='W')
                r['mm'] = C('MVFCCR_M10', 'MVFCCR_M10', k1='ADDR', sz='W')
                return r, 'ALT'
            return r, 'NOEA'
        if o == 0x44c0:   # MOVE to CCR
            c = C('MVTCCR', 'CCRW', k1='RD', op='PASS', ca='EAV', sz='W')
            ea_cls(m0=c, mm=c, mi=c)
            return r, 'DATA'
        if o == 0x46c0:   # MOVE to SR
            c = C('MVTSR', 'SRW', k1='RD', op='PASS', ca='EAV', sz='W', priv=1)
            ea_cls(m0=c, mm=c, mi=c)
            if DEC020:    # (68020 T0 trace: Musashi traces MOVE <ea>,SR but not MOVE Dn,SR - its own class)
                r['m0'] = C('MVTSR_D20', 'SRW', k1='RD', op='PASS', ca='EAV', sz='W', priv=1)
            return r, 'DATA'
        if o == 0x4800:   # NBCD
            r['m0'] = C('NBCD_D', 'RDY2N', op='NBCD', sz='B')
            r['mm'] = C('NBCD_M', 'RMW', k1='RD', op='NBCD', sz='B')
            if DEC020: r['m1'] = C('LINKL20', 'LINKL20', sz='L')      # LINK.L An,#d32 (68020: 4808)
            return r, 'ALT'
        if o == 0x4840:   # SWAP / PEA (BKPT 010+)
            r['m0'] = C('SWAP', 'RDY', op='SWAP', sz='L')
            r['mm'] = C('PEA', 'EXC_ILL', k1='PEA', sz='L')
            if DEC010: r['m1'] = C('BKPT10', 'BKPT10')
            return r, 'CTRL'
        if o in (0x4880, 0x48c0):   # EXT / MOVEM reg->mem
            r['m0'] = C('EXT', 'RDY', op='EXT', sz='B6')
            r['mm'] = C('MOVEM_RM', 'EXC_ILL', k1='MVRM', sz='B6')
            return r, 'CTRLPD'
        if DEC020 and o in (0x4c00, 0x4c40):     # MUL.L / DIV.L (68020): extension word, then the source
            b = 'MULL20' if o == 0x4c00 else 'DIVL20'
            ea_cls(m0=C(b + '_D', b, k1='XWD', sz='L'), mm=C(b + '_M', b, k1='XWD', k2='RD', sz='L'),
                   mi=C(b + '_M', b, k1='XWD', k2='RD', sz='L'))
            return r, 'DATA'
        if o in (0x4c80, 0x4cc0):   # MOVEM mem->reg
            r['mm'] = C('MOVEM_MR', 'EXC_ILL', k1='MVMR', sz='B6')
            return r, 'CTRLPI'
        if (op & 0xff00) == 0x4a00:
            if s76 == 3:   # TAS
                r['m0'] = C('TAS_D', 'RDY', op='TAS', sz='B')
                r['mm'] = C('TAS_M', 'TASM', k1='TAS', sz='B')
                return r, 'ALT'
            r['m0'] = C('TST_D', 'RDY', op='TST')
            r['mm'] = C('TST_M', 'RMEM', k1='RD', op='TST')
            if DEC020:                        # 68020: TST An (word / long), #imm, PC-relative
                if s76 != 0: r['m1'] = C('TST_A20', 'RMEM', op='TST')
                r['mi'] = C('TST_M', 'RMEM', k1='RD', op='TST')
                return r, 'ALL'
            return r, 'ALT'
        if o == 0x4e40:
            return r, 'NOEA'                  # 4E40-4E7F: decoded by the special table (RTL)
        if o == 0x4e80:
            r['mm'] = C('JSR', 'EXC_ILL', k1='JSR', sz='L')
            return r, 'CTRL'
        if o == 0x4ec0:
            r['mm'] = C('JMP', 'EXC_ILL', k1='JMP', sz='L')
            return r, 'CTRL'
        return r, 'NOEA'
    if line == 5:
        if s76 == 3:
            c = (op >> 8) & 15
            r['m0'] = C('SCC_D', 'SCC_D', op='SCC', sz='B')
            r['m1'] = C('DBCC', 'DBCC', sz='W')
            r['mm'] = C('SCC_M', 'RMW', k1='RD', op='SCC', sz='B')
            if DEC010: r['mm'] = C('SCC_M10', 'SCCW10', k1='ADDR', op='SCC', sz='B')     # 68010: no read
            return r, 'ALT'
        alu = 'SUB' if o8 else 'ADD'
        r['m0'] = C(alu + 'Q_D' + str(s76), 'RDY4' if s76 == 2 else 'RDY', op=alu, ca='QUICK')
        r['m1'] = C(alu + 'Q_A', 'ADDQA', op=alu + 'A', ca='QUICK') if s76 != 0 else ILL
        if DEC010 and s76 == 1:                      # 68010: ADDQ / SUBQ .w #,An 4(1/0) (table 7-11; 68000: 8)
            r['m1'] = C(alu + 'Q_AW10', 'ADDQAW10', op=alu + 'A', ca='QUICK')
        r['mm'] = C(alu + 'Q_M', 'RMW', k1='RD', op=alu, ca='QUICK')
        return r, 'ALT'
    if line == 6:
        cc = (op >> 8) & 15
        if cc == 1:
            every(C('BSR', 'BSR_S', sz='L'))   # short / word chosen by the RTL from the displacement byte
        else:
            every(C('BCC', 'BCC_S', sz='L'))
        return r, 'NOEA'
    if line == 7:
        if o8 == 0:
            every(C('MOVEQ', 'MOVEQ', sz='L'))
        return r, 'NOEA'
    if line in (8, 9, 0xb, 0xc, 0xd):
        nm = {8: 'OR', 9: 'SUB', 0xb: 'CMP', 0xc: 'AND', 0xd: 'ADD'}[line]
        if s76 == 3:
            if line == 8:
                c = C('DIVS' if o8 else 'DIVU', 'DIV', k1='RD', sz='W')
                ea_cls(m0=c, mm=c, mi=c); return r, 'ALL'
            if line == 0xc:
                c = C('MULS' if o8 else 'MULU', 'MUL', k1='RD', op='MUL', sz='W')
                ea_cls(m0=c, mm=c, mi=c); return r, 'ALL'
            alu = {9: 'SUBA', 0xb: 'CMPA', 0xd: 'ADDA'}[line]
            # CMPA: 2 idle clocks; ADDA / SUBA: 4, except .l from memory: 2
            if alu == 'CMPA':
                every(C(alu, 'ALU_CPA', k1='RD', op=alu, sz='A8'))
            else:
                every(C(alu + str(o8), 'ALU_AN4', k1='RD', op=alu, sz='A8'))
                if o8 and DEC010:           # 68010: ADDA / SUBA .l <ea>,An 6(1/0) + ea (table 7-9)
                    every(C(alu + 'L10', 'ALU_AN2', k1='RD', op=alu, sz='A8'))
                if o8:
                    r['mm'] = C(alu + 'LM', 'ALU_AN2', k1='RD', op=alu, sz='A8')
            return r, 'ALL'
        if o8 == 0:
            # .l: 4 idle clocks from a register or #imm, 2 from memory; CMP.l: 2
            if s76 == 2:
                c = C(nm + '_DNL', 'ALU_CP2' if nm == 'CMP' else 'ALU_DN4', k1='RD', op=nm)
                if DEC010 and nm != 'CMP':  # 68010: .l <ea>,Dn 6(1/0) + ea, also from Dn / #imm (table 7-9)
                    c = C(nm + '_DNL10', 'ALU_DN2', k1='RD', op=nm)
                cm = C(nm + '_DNLM', 'ALU_CP2' if nm == 'CMP' else 'ALU_DN2', k1='RD', op=nm)
            else:
                c = cm = C(nm + '_DN', 'ALU_DN', k1='RD', op=nm)
            ea_cls(m0=c, m1=c if (s76 != 0 and line not in (8, 0xc)) else None, mm=cm, mi=c)
            return r, 'ALL'
        # o8 == 1: <Dn>,<ea> forms and the specials
        if line == 0xb:
            r['m0'] = C('EOR_D' + str(s76), 'RDY4' if s76 == 2 else 'RDY', op='EOR', ca='DX')
            if DEC010 and s76 == 2:                  # 68010: EOR.l Dn,Dn 6(1/0) (table 7-9; 68000: 8)
                r['m0'] = C('EOR_D2_10', 'RDY2C10', op='EOR', ca='DX')
            r['m1'] = C('CMPM', 'CMPM')
            r['mm'] = C('EOR_M', 'RMW', k1='RD', op='EOR', ca='DX')
            return r, 'ALT'
        r['mm'] = C(nm + '_M', 'RMW', k1='RD', op=nm, ca='DX')
        if line in (9, 0xd):
            x = 'SUBX' if line == 9 else 'ADDX'
            r['m0'] = C(x + '_R' + str(s76), 'XREG4' if s76 == 2 else 'XREG', op=x)
            if DEC010 and s76 == 2:         # 68010: ADDX / SUBX .l Dy,Dx 6(1/0) (table 7-20)
                r['m0'] = C(x + '_R2_10', 'XREG2L10', op=x)
            r['m1'] = C(x + '_M' + str(s76), 'XMEM_L' if s76 == 2 else 'XMEM', op=x)
        elif DEC020 and line == 8 and s76 in (1, 2):    # PACK / UNPK (68020): Dy,Dx,#adj / -(Ay),-(Ax),#adj
            b = 'PACK20' if s76 == 1 else 'UNPK20'
            r['m0'] = C(b + 'R', b + 'R')
            r['m1'] = C(b + 'M', b + 'M')
        elif s76 == 0:
            x = 'SBCD' if line == 8 else 'ABCD'
            r['m0'] = C(x + '_R', 'XREG2', op=x, sz='B')
            r['m1'] = C(x + '_M', 'XMEM', op=x, sz='B')
        elif line == 0xc and s76 == 1:
            r['m0'] = C('EXG_DD', 'EXG', sz='L')
            r['m1'] = C('EXG_AA', 'EXG', sz='L')
        elif line == 0xc and s76 == 2:
            r['m1'] = C('EXG_DA', 'EXG', sz='L')
        return r, 'ALT'
    if line == 0xa:
        every(C('LINEA', 'EXC_LA')); return r, 'NOEA'
    if line == 0xf:
        if DEC020:    # 68020: coprocessor instructions probe the coprocessor (m68ksv_ucode020.py LINEF20), cpSAVE /
                      # cpRESTORE (type 4 / 5) privileged; types 6 / 7: F-line exception at once
            t = (op >> 6) & 7
            every(C('LINEF20', 'LINEF20') if t < 4 else C('LINEF20P', 'LINEF20', priv=1) if t < 6 else C('LINEF', 'EXC_LF'))
            return r, 'NOEA'
        every(C('LINEF', 'EXC_LF')); return r, 'NOEA'
    if line == 0xe:
        if s76 == 3:
            if (op >> 11) & 1:
                if DEC020:                    # bit fields (68020): extension word, then the address
                    bop = (op >> 8) & 7       # TST EXTU CHG EXTS CLR FFO SET INS
                    r['m0'] = C('BF20R', 'BF20R', k1='XWD', sz='L')
                    r['mm'] = C('BF20M', 'BF20M', k1='XWD', k2='ADDR', sz='L')
                    return r, ('CALT' if bop in (2, 4, 6, 7) else 'CTRL')
                return r, 'NOEA'              # bit field (020)
            r['mm'] = C('SHM', 'RMW', k1='RD', op='SHF1', sz='W')
            return r, 'MALT'
        every(C('SHR', 'SHR'))
        return r, 'NOEA'
    return r, 'NOEA'

# 4E40-4E7F special table
def decode_4e(lo):
    if lo < 0x10: return C('TRAP', 'TRAP')
    if lo < 0x18: return C('LINK', 'LINK', sz='L')
    if lo < 0x20: return C('UNLK', 'UNLK', sz='L')
    if lo < 0x28: return C('MVUSP_TO', 'MVUSP_TO', sz='L', priv=1)
    if lo < 0x30: return C('MVUSP_FROM', 'MVUSP_FROM', sz='L', priv=1)
    t = {0x30: C('RESETI', 'RESETI', priv=1), 0x31: C('NOP', 'NOP'), 0x32: C('STOP', 'STOP', priv=1),
         0x33: C('RTE', 'RTE', priv=1), 0x35: C('RTS', 'RTS', sz='L'), 0x36: C('TRAPV', 'TRAPV'),
         0x37: C('RTR', 'RTR', sz='L')}
    if DEC010:    # 68010: RTE reads the format word, RTD, MOVEC
        t.update({0x33: C('RTE10', 'RTE10', priv=1), 0x34: C('RTD10', 'RTD10', sz='L'),
                  0x3a: C('MOVEC_R', 'MOVEC_R', priv=1), 0x3b: C('MOVEC_W', 'MOVEC_W', priv=1)})
    if DEC020:    # 68020: RTE with formats 0 / 1 / 2 / 9 / A / B
        t[0x33] = C('RTE20', 'RTE20', priv=1)
    return t.get(lo, ILL)

# 68010: the 68000 classes are created first, in the 68000 order, so that every class the RTL names (CLS_*) keeps its
# number; 68010 classes (new names) follow
DEC010 = False
DEC020 = False
if IS010:
    for hi in range(1024): decode_hi(hi)
    for lo in range(64): decode_4e(lo)
    C('TRAP', 'TRAP')
DEC010 = IS010
DEC020 = IS020
ROM1 = []
for hi in range(1024):
    r, v = decode_hi(hi)
    ROM1.append((r, v))
SPEC4E = [decode_4e(lo) for lo in range(64)]

# extra fixed classes used by the RTL
C('TRAP', 'TRAP')
if IS020:
    C('TRAPCC20', 'TRAPCC20')         # TRAPcc (5xFA / 5xFB / 5xFC: Scc's mode 7 / 2-4 slots), selected by the RTL
    # 68020 T0 trace (change of flow): the instructions Musashi's 68020 handlers trace with T0 (m68k_in.lst
    # m68ki_trace_t0), unconditional ones by a class bit; taken Bcc / DBcc by m2 FLOW in their microcode
    for _n in CLS_ORDER:
        if _n in ('JMP', 'JSR', 'BSR', 'RTS', 'RTR', 'RTD10', 'RTE20', 'NOP', 'STOP', 'MVUSP_TO', 'MOVEC_R', 'MOVEC_W',
                  'MOVES10', 'ORI_SR', 'ANDI_SR', 'EORI_SR', 'MVTSR', 'CAS_B', 'CAS_W', 'CAS_L', 'CAS2_W', 'CAS2_L'):
            CLASSES[_n]['flow'] = 1
if IS020:
    # 68020: classes with identical contents share one number (the 68000 + 68010 + 68020 names exceed 256); the RTL
    # takes the numbers it names from CLS20_* in the package
    _uk = {}
    CLS_UNIQ = []
    CLSN = {}
    for _n in CLS_ORDER:
        _key = tuple(sorted(CLASSES[_n].items()))
        if _key not in _uk:
            _uk[_key] = len(CLS_UNIQ)
            CLS_UNIQ.append(_n)
        CLSN[_n] = _uk[_key]
else:
    CLS_UNIQ = CLS_ORDER
    CLSN = {n: i for i, n in enumerate(CLS_ORDER)}
assert len(CLS_UNIQ) <= 256, len(CLS_UNIQ)

# ROM3: (kind', mi) -> routine address; kind' list
K3 = ['RDW', 'RDL', 'ADDR', 'IMMW', 'IMML', 'JMP', 'JSR', 'LEA', 'PEA', 'TAS', 'MVRMW', 'MVRML', 'MVMRW', 'MVMRL', 'XWD',
      'CLRW']                 # XWD / CLRW: 68010 (MOVES extension word; CLR without the read)
SKIPV = 2047

def eatab_addr(k, mi):
    if k not in EATAB: return LABELS['EXC_ILL']          # 68010 kinds in the 68000 tables
    t = EATAB[k][mi]
    if t is None: return LABELS['EXC_ILL']
    if t == SKIP: return SKIPV
    return LABELS[t]

# ---------------------------------------------------------------------------------------------------------------
# emit (strings; the driver at the top writes the files)
def emit_pkg():
    o = []
    o.append('// Generated by rtl/gen/m68ksv_ucode.py - do not edit.\n')
    o.append('package m68ksv_upkg;\n')
    o.append('localparam int UW = %d;\n' % UW0)
    o.append('localparam int UA000_W = 10;          // 68000-family microcode address width (compacted ROM, checkpoint 6)\n')
    for n, w, cs in FIELDS:
        o.append('localparam int F_%s_LSB = %d, F_%s_W = %d;\n' % (n.upper(), FPOS[n], n.upper(), w))
    for n, w, cs in FIELDS:
        if not cs: continue
        pfx = {'op': 'OP'}.get(n, n.upper())
        for i, c in enumerate(cs):
            o.append('localparam logic [%d:0] %s_%s = %d\'d%d;\n' % (w - 1, pfx, c, w, i))
    o.append('localparam logic [10:0] UA_RESET = 11\'d%d, UA_TLFIN = 11\'d%d, UA_EXC0 = 11\'d%d, UA_HALT = 11\'d%d;\n'
             % (LABELS['RESET'], LABELS['TLFIN'], LABELS['EXC0'], LABELS['HALT']))
    o.append('localparam logic [10:0] UA_EXC0A = 11\'d%d, UA_HALTA = 11\'d%d;\n' % (LABELS['EXC0A'], LABELS['HALTA']))
    o.append('localparam logic [10:0] UA_ILL = 11\'d%d, UA_PRIV = 11\'d%d, UA_INT = 11\'d%d, UA_TRACE = 11\'d%d;\n'
             % (LABELS['EXC_ILL'], LABELS['EXC_PRIV'], LABELS['EXC_INT'], LABELS['EXC_TRACE']))
    o.append('localparam logic [10:0] UA_LA = 11\'d%d, UA_LF = 11\'d%d;\n' % (LABELS['EXC_LA'], LABELS['EXC_LF']))
    o.append('localparam logic [10:0] UA_VECJMP_G0 = 11\'d%d;\n' % (LABELS['VECJMP_G0'],))
    o.append('localparam logic [10:0] UA_SKIP = 11\'d%d;\n' % (SKIPV,))
    o.append('localparam logic [10:0] UA_BCC_S = 11\'d%d, UA_BCC_W = 11\'d%d, UA_BSR_S = 11\'d%d, UA_BSR_W = 11\'d%d;\n'
             % (LABELS['BCC_S'], LABELS['BCC_W'], LABELS['BSR_S'], LABELS['BSR_W']))
    for i, k in enumerate(KINDS):
        o.append('localparam logic [3:0] K_%s = 4\'d%d;\n' % (k, i))
    for i, k in enumerate(K3):
        o.append('localparam logic [3:0] K3_%s = 4\'d%d;\n' % (k, i))
    for i, s in enumerate(SZR):
        o.append('localparam logic [2:0] SZR_%s = 3\'d%d;\n' % (s, i))
    for i, s in enumerate(CAS):
        o.append('localparam logic [2:0] CA_%s = 3\'d%d;\n' % (s, i))
    for i, s in enumerate(VALID):
        if i < 8: o.append('localparam logic [2:0] V_%s = 3\'d%d;\n' % (s, i))
        else:     o.append('localparam logic [3:0] V_%s = 4\'d%d;\n' % (s, i))     # 68020 only (4-bit field)
    o.append('localparam logic [7:0] CLS_ILL = 8\'d%d, CLS_BCC = 8\'d%d, CLS_BSR = 8\'d%d;\n'
             % (CLSN['ILL'], CLSN['BCC'], CLSN['BSR']))
    o.append(emit_umask())
    o.append('endpackage\n')
    return ''.join(o)

def emit_umask():
    """checkpoint 5: for every coded microword field, the codes that occur in this ROM set (any word, dead words too, and
    the zero padding / reset word): UM<set>_<FIELD>, bit c set when code c occurs. The RTL gates the decode of a code
    that never occurs (m68ksv_eu UM_*), so the logic behind it folds away in that build - exact, since the micro-word
    can hold only ROM words (or the reset value 0)"""
    tag = {68000: '000', 68010: '010', 68020: '020'}[CPU]
    words = [enc(w, i) for i, w in enumerate(CODE)]
    o = ['// codes occurring in the %s ROM set (bit c = code c; m68ksv_eu UM_*)\n' % {68000: '68000-family', 68010: '68010', 68020: '68020'}[CPU]]
    for n, w, cs in FIELDS:
        if n not in ('sq', 'cd', 'dw', 'ad', 'xa', 'xb', 'xd', 'ms', 'fx'): continue     # the fields m68ksv_eu gates
        m = 1                                   # code 0: the ROM padding and the reset value of the micro-word
        for v in words: m |= 1 << ((v >> FPOS[n]) & ((1 << w) - 1))
        o.append("localparam logic [%d:0] UM%s_%s = %d'h%x;\n" % ((1 << w) - 1, tag, n.upper(), 1 << w, m))
    m = 1                                       # decoded-class source codes of drom2 (c_ca resets to 0)
    for n in CLS_UNIQ: m |= 1 << CAS.index(CLASSES[n]['ca'])
    o.append("localparam logic [7:0] UM%s_CA = 8'h%x;\n" % (tag, m))
    return ''.join(o)

def emit_pkg10():
    """68010 additions to the package: its microword width and the addresses of its own labels the RTL uses"""
    o = ['// 68010 ROM set\n', 'localparam int UW10 = %d;\n' % UW]
    for k in UA10_EXPORT:
        o.append('localparam logic [10:0] U10_%s = 11\'d%d;\n' % (k, LABELS[k]))
    o.append(emit_umask())
    return ''.join(o)

def rom_module(name, aw, dw, words, pad=0, style='M10K'):
    """synchronous-read ROM as an initialised array (the form Quartus 17 infers as M10K; the case-table form was
    built in logic for the partial urom / drom2 tables, 2026-11-15 compile). Every entry is written. style 'logic'
    (checkpoint 6, RES = 1): the same table built in LUTs, the output register kept (same timing as the M10K form)."""
    n = 1 << aw
    o = ['module %s (\n    input  logic clk,\n    input  logic [%d:0] a,\n    output logic [%d:0] q\n);\n' % (name, aw - 1, dw - 1),
         '(* romstyle = "%s" *) logic [%d:0] rom [0:%d];\ninitial begin\n' % (style, dw - 1, n - 1)]
    for i in range(n):
        v = words[i] if i < len(words) else pad
        o.append("    rom[%d] = %d'h%x;\n" % (i, dw, v))
    o.append('end\nalways_ff @(posedge clk) q <= rom[a];\nendmodule\n')
    return ''.join(o)

def rom_module_split(name, dw, words):
    """checkpoint 6, 68010 ROM (1,025 - 1,536 words; its micro-addresses are architectural, so it is not compacted):
    1,024 words + a 512-word tail as two M10K ROMs instead of one 2,048-deep ROM (1,024 x 10 / 512 x 20 per block
    instead of 2,048 x 5). So that the select mux is not on the paths that start at the ROM output, both ROMs are read
    one clock ahead, like the RES = 1 micro ROM (address = the value ua_r is loaded with, clock enable = that load,
    m68ksv_eu ua_n / ua_ce), the mux sits in front of a register, and q is that register: the word at the ua_r of the
    previous clock in every clock, as a single ROM addressed by ua_r. Addresses 1,536 - 2,047 give the zero word, as the
    padding of the single ROM did (an RTE may resume at any address its frame names)"""
    assert 1024 < len(words) <= 1536
    o = ['module %s (\n    input  logic clk,\n    input  logic ce,\n    input  logic [10:0] an,\n    output logic [%d:0] q\n);\n' % (name, dw - 1),
         '(* romstyle = "M10K" *) logic [%d:0] rom0 [0:1023];\n' % (dw - 1),
         '(* romstyle = "M10K" *) logic [%d:0] rom1 [0:511];\ninitial begin\n' % (dw - 1)]
    for i in range(1536):
        v = words[i] if i < len(words) else 0
        o.append("    rom%d[%d] = %d'h%x;\n" % (i >> 10, i & 1023, dw, v))
    o.append('end\nlogic [%d:0] q0, q1;\nlogic        s0, s1;\n' % (dw - 1))
    o.append('always_ff @(posedge clk) if (ce) q0 <= rom0[an[9:0]];      // each ROM read in a block of its own (M10K template)\n'
             'always_ff @(posedge clk) if (ce) q1 <= rom1[an[8:0]];\n'
             'always_ff @(posedge clk) begin\n    if (ce) begin\n        s0 <= !an[10];\n        s1 <= an[10] && !an[9];\n    end\n'
             '    q <= ({%d{s0}} & q0) | ({%d{s1}} & q1);\nend\nendmodule\n' % (dw, dw))
    return ''.join(o)

def emit_urom():
    o = ['// Generated by rtl/gen/m68ksv_ucode.py - do not edit.\n',
         '// Microcode ROM%s: %d words x %d bits, synchronous read (M10K)%s.\n' % ({68000: '', 68010: ' (68010)', 68020: ' (68020)'}[CPU], len(CODE), UW,
         {68000: '; compacted to the 1,024-deep shape (checkpoint 6)', 68010: '; 1,024 + 512 words, read one clock ahead (checkpoint 6)', 68020: ''}[CPU])]
    words = [enc(w, i) for i, w in enumerate(CODE)]
    if CPU == 68000:
        o.append(rom_module('m68ksv_urom', 10, UW, words))          # m68ksv_eu: address ua_r[UA000_W-1:0]
    elif CPU == 68010:
        o.append(rom_module_split('m68ksv_urom_010', UW, words))
    else:
        o.append(rom_module('m68ksv_urom' + SFX, 11, UW, words))
    return ''.join(o)

# ---------------------------------------------------------------------------------------------------------------
# checkpoint 6, RES = 1 (logic-heavy setting): two-level control store m68ksv_ucs<SFX> (DESIGN.md 3.1). The micro ROM
# holds, per micro-address, nxt, one index per nano group and the "direct" fields; each nano ROM holds the distinct
# value combinations of its group of fields (index 0 = all zero: the padding / reset word). Timing as m68ksv_urom: the
# micro ROM is read one clock ahead (address = the value ua_r is loaded with, clock enable = when it is loaded), the
# nano ROMs read the indices at the next clock edge and nxt / direct fields go through registers, so q is the word at
# the ua_r of the previous clock in every clock, as m68ksv_urom's q.
UCS_GROUPS = {          # nano groups, chosen by a search over field partitions (REPORT.md checkpoint 6): fewest M10K
    68000: [['sq', 'bus', 'ba', 'aa', 'ab', 'ad', 'xa', 'xd', 'fl', 'iq', 'pl', 'lk', 'pu'],
            ['cd', 'bs', 'bd', 'bf', 'dw', 'as', 'op', 'xb', 'xs', 'ms', 'bn', 'ai', 'fh']],          # direct: lh
    68010: [[n for n, _, _ in FIELDS if n != 'nxt' and FPOS[n] < UW10]],                               # one nano
    68020: [['sq', 'cd', 'ba', 'dw', 'aa', 'ab', 'ad', 'bn', 'iq', 'lk', 'fh', 'lh', 'sf', 'rr'],
            ['bd', 'op', 'xa', 'xb', 'xd', 'xs', 'ms', 'pl', 'xe', 'fx'],
            ['bus', 'bs', 'bf', 'as', 'fl', 'ai', 'pu', 'ly', 'x1', 'c2', 'xw', 'm2', 'd2']],
}
def m10k_blocks(d, w):
    """M10K blocks of a d-deep, w-wide single-port ROM in its cheapest mode (Cyclone V: 256 x 40 .. 8192 x 1)"""
    return min(-(-d // md) * -(-w // mw) for md, mw in ((256, 40), (512, 20), (1024, 10), (2048, 5), (4096, 2), (8192, 1)))

def emit_ucs():
    words = [enc(w, i) for i, w in enumerate(CODE)]
    depth = 1024 if CPU == 68000 else 1536 if CPU == 68010 else 2048
    assert len(words) <= depth
    fv = lambda v, n: (v >> FPOS[n]) & ((1 << FW[n]) - 1)
    ufields = [n for n, _, _ in FIELDS if FPOS[n] < UW]
    orv = 0
    for v in words: orv |= v
    zero = [n for n in ufields if fv(orv, n) == 0 and n != 'nxt']              # constant 0 in this ROM set: not stored
    groups = [[n for n in g if n not in zero] for g in UCS_GROUPS[CPU]]
    grouped = set(n for g in groups for n in g)
    assert all(n in ufields for n in grouped), 'nano group field outside this ROM set'
    direct = [n for n in ufields if n != 'nxt' and n not in zero and n not in grouped]
    nw = 10 if CPU == 68000 else 11
    assert all(fv(v, 'nxt') < (1 << nw) for v in words)
    tabs = []
    for g in groups:
        t = [tuple(0 for _ in g)]; ix = {t[0]: 0}
        for v in words:
            k = tuple(fv(v, n) for n in g)
            if k not in ix: ix[k] = len(t); t.append(k)
        ib = max(1, (len(t) - 1).bit_length())
        tabs.append((g, t, ix, ib, sum(FW[n] for n in g)))
    # micro word, from bit 0: nxt, the direct fields, the nano indices
    mpos = {'nxt': (0, nw)}; p = nw
    for n in direct:
        mpos[n] = (p, FW[n]); p += FW[n]
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):
        mpos['i%d' % gi] = (p, ib); p += ib
    mw = p
    def mword(v):
        m = fv(v, 'nxt')
        for gi, (g, t, ix, ib, bw) in enumerate(tabs):
            m |= ix[tuple(fv(v, n) for n in g)] << mpos['i%d' % gi][0]
        for n in direct: m |= fv(v, n) << mpos[n][0]
        return m
    mwords = [mword(v) for v in words] + [0] * (depth - len(words))
    def nword(gi, k):
        g = tabs[gi][0]; v = 0; o_ = 0
        for n, x in zip(g, k): v |= x << o_; o_ += FW[n]
        return v
    # self-check: every micro-address rebuilds its word (padding: the zero word)
    for a in range(depth):
        m = mwords[a]; v = (m & ((1 << nw) - 1)) << FPOS['nxt']
        for gi, (g, t, ix, ib, bw) in enumerate(tabs):
            k = t[(m >> mpos['i%d' % gi][0]) & ((1 << ib) - 1)]
            for n, x in zip(g, k): v |= x << FPOS[n]
        for n in direct: v |= ((m >> mpos[n][0]) & ((1 << FW[n]) - 1)) << FPOS[n]
        assert v == (words[a] if a < len(words) else 0), ('control store rebuild', a)
    name = 'm68ksv_ucs' + SFX
    if CPU == 68010: mblk = m10k_blocks(1024, mw) + m10k_blocks(512, mw)
    else: mblk = m10k_blocks(depth, mw)
    nblk = [m10k_blocks(1 << ib, bw) for (g, t, ix, ib, bw) in tabs]
    o = ['// Generated by rtl/gen/m68ksv_ucode.py - do not edit.\n',
         '// Two-level control store%s (checkpoint 6, RES = 1, logic-heavy setting): micro ROM %s x %d bits {nxt%s, %s} (%d M10K),\n'
         % ({68000: '', 68010: ' (68010)', 68020: ' (68020)'}[CPU], '1,024 + 512' if CPU == 68010 else '%d' % depth, mw,
            ', ' + ' '.join(direct) if direct else '', ', '.join('nano %d index' % i for i in range(len(tabs))), mblk)]
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):
        o.append('//   nano %d: %d x %d bits (%d distinct values; %d M10K): %s\n' % (gi, 1 << ib, bw, len(t), nblk[gi], ' '.join(g)))
    o.append('//   not stored (constant 0 in this ROM set): %s\n' % (' '.join(zero) if zero else '-'))
    o.append('// q = the micro-word at ua_r of the previous clock, as m68ksv_urom%s (ce / an: m68ksv_eu ua_ce / ua_n).\n' % SFX)
    aw_ = 10 if CPU == 68000 else 11                     # 68000 family: m68ksv_eu passes ua_n[UA000_W-1:0]
    o.append('module %s (\n    input  logic clk,\n    input  logic ce,\n    input  logic [%d:0] an,\n    output logic [%d:0] q\n);\n' % (name, aw_ - 1, UW - 1))
    if CPU == 68010:
        o.append('(* romstyle = "M10K" *) logic [%d:0] mrom0 [0:1023];\n(* romstyle = "M10K" *) logic [%d:0] mrom1 [0:511];\n' % (mw - 1, mw - 1))
    else:
        o.append('(* romstyle = "M10K" *) logic [%d:0] mrom [0:%d];\n' % (mw - 1, depth - 1))
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):
        o.append('(* romstyle = "M10K" *) logic [%d:0] nrom%d [0:%d];\n' % (bw - 1, gi, (1 << ib) - 1))
    o.append('initial begin\n')
    for a, m in enumerate(mwords):
        if CPU == 68010: o.append("    mrom%d[%d] = %d'h%x;\n" % (a >> 10, a & 1023, mw, m))
        else: o.append("    mrom[%d] = %d'h%x;\n" % (a, mw, m))
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):
        for i in range(1 << ib):
            o.append("    nrom%d[%d] = %d'h%x;\n" % (gi, i, bw, nword(gi, t[i]) if i < len(t) else 0))
    o.append('end\n')
    o.append('// micro ROM: read with ua_r\'s next value, when ua_r is loaded\nlogic [%d:0] mq;\n' % (mw - 1))
    if CPU == 68010:
        o.append('logic [%d:0] mq0, mq1;\nlogic        ms0, ms1;\n' % (mw - 1))
        o.append('always_ff @(posedge clk) if (ce) mq0 <= mrom0[an[9:0]];\nalways_ff @(posedge clk) if (ce) mq1 <= mrom1[an[8:0]];\n'
                 'always_ff @(posedge clk) begin\n    if (ce) begin\n'
                 '        ms0 <= !an[10];\n        ms1 <= an[10] && !an[9];      // 1,536 - 2,047: the zero word, as the padding of one ROM\n'
                 '    end\nend\n')
        o.append('assign mq = ({%d{ms0}} & mq0) | ({%d{ms1}} & mq1);\n' % (mw, mw))
    else:
        o.append('always_ff @(posedge clk) if (ce) mq <= mrom[an[%d:0]];\n' % ((depth - 1).bit_length() - 1))
    dw_ = nw + sum(FW[n] for n in direct)
    o.append('// nano ROMs (indices from the micro ROM, read at the next clock edge); nxt and the direct fields one clock later\n')
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):
        o.append('logic [%d:0] nq%d;\n' % (bw - 1, gi))
    o.append('logic [%d:0] dq;\n' % (dw_ - 1))
    for gi, (g, t, ix, ib, bw) in enumerate(tabs):           # each ROM read in a block of its own (M10K template)
        p_, w_ = mpos['i%d' % gi]
        o.append('always_ff @(posedge clk) nq%d <= nrom%d[mq[%d:%d]];\n' % (gi, gi, p_ + w_ - 1, p_))
    o.append('always_ff @(posedge clk) dq <= mq[%d:0];\n' % (dw_ - 1))
    o.append('// the micro-word fields\n')
    for n in ufields:
        lsb, w_ = FPOS[n], FW[n]
        if n == 'nxt':
            src = ('{1\'b0, dq[%d:0]}' % (nw - 1)) if nw < w_ else 'dq[%d:0]' % (nw - 1)
        elif n in zero:
            src = "%d'd0" % w_
        elif n in direct:
            src = 'dq[%d:%d]' % (mpos[n][0] + w_ - 1, mpos[n][0])
        else:
            gi = [i for i, tb in enumerate(tabs) if n in tb[0]][0]
            g = tabs[gi][0]; off = sum(FW[x] for x in g[:g.index(n)])
            src = 'nq%d[%d:%d]' % (gi, off + w_ - 1, off)
        o.append('assign q[%d:%d] = %s;   // %s\n' % (lsb + w_ - 1, lsb, src, n))
    o.append('endmodule\n')
    global UCS_SUMMARY
    UCS_SUMMARY = (mw, mblk, [(len(t), 1 << ib, bw, nblk[gi]) for gi, (g, t, ix, ib, bw) in enumerate(tabs)], direct, zero)
    return ''.join(o)

def cls_word(n):
    c = CLASSES[n]
    k1 = KINDS.index(c['k1']); k2 = KINDS.index(c['k2'])
    body = LABELS[c['body']]
    aop = FC['op'][c['op']]
    ca = CAS.index(c['ca']); sz = SZR.index(c['sz'])
    # [10:0] body [14:11] k1 [18:15] k2 [24:19] aluop [27:25] ca [30:28] szrule [31] nofl [32] priv [33] flow (68020)
    return (body | (k1 << 11) | (k2 << 15) | (aop << 19) | (ca << 25) | (sz << 28) | (c['nofl'] << 31) | (c['priv'] << 32) |
            (c.get('flow', 0) << 33))

def loopable(op):
    """68010 loop mode (data sheet table 7-3): {loopable, idle words} of a one-word instruction; idle words = (loop-
    continued time of tables 7-6 / 7-8 / 7-10 / 7-14 / 7-16 / 7-20 - the instruction's own time) / 2 - 1. Written into
    m68ksv_drom1lp_010 for the EA modes Dn / An / (An), (An)+, -(An); m68ksv_eu reads it as lp_irn / lp_ir. (cp5: moved
    here from m68ksv_eu's loopable(), equal on all 65,536 opcodes - checked before the RTL copy was removed)"""
    sm = (op >> 3) & 7; dm = (op >> 6) & 7; sz = (op >> 6) & 3; hi = op >> 12
    b8 = (op >> 8) & 1; b12 = (op >> 12) & 1; ind = sm in (2, 3, 4)
    r = 0
    if hi in (1, 2, 3):                                          # MOVE.B / .L / .W
        if dm in (2, 3, 4) and ind: r = 0b100 | (1 if dm == 4 else 0)
        elif dm in (2, 3) and (sm == 0 or (sm == 1 and ((op >> 12) & 3) != 1)): r = 0b100
    elif hi in (8, 9, 0xc, 0xd):                                 # OR / SUB / AND / ADD (+ A, BCD, X forms)
        if dm in (3, 7):
            if ind and b12: r = 0b100 | (3 if b8 else 2)
        elif not b8:
            if ind: r = 0b100 | (2 if (hi == 9 and sz == 2) else 3)
        elif sm == 1:
            if not b12: r = 0b110 if sz == 0 else 0
            else: r = 0b100 | (0 if sz == 2 else 1)
        elif ind: r = 0b101
    elif hi == 0xb:                                              # CMPA / CMP / CMPM / EOR
        if dm in (3, 7):
            if ind: r = 0b100 | (1 if b8 else 0)
        elif not b8:
            if ind: r = 0b101
        elif sm == 1: r = 0b100 | (1 if sz == 2 else 0)
        elif ind: r = 0b101
    elif hi == 4:
        if sz != 3 and ind and not b8:
            f = (op >> 9) & 7
            if f in (0, 2, 3): r = 0b101                         # NEGX / NEG / NOT
            elif f == 1: r = 0b100                               # CLR
            elif f == 5: r = 0b100 | (2 if sz == 2 else 1)       # TST
            elif f == 4: r = 0b110 if sz == 0 else 0             # NBCD
    elif hi == 0xe:
        if sz == 3 and not ((op >> 11) & 1) and ind: r = 0b110  # memory shifts / rotates
    return r

def emit_drom():
    o = ['// Generated by rtl/gen/m68ksv_ucode.py - do not edit.\n',
         '// Decode ROMs%s (M10K, synchronous read).\n' % {68000: '', 68010: ' (68010)', 68020: ' (68020)'}[CPU],
         '// drom1: opcode[15:6] -> {valid[2:0], cls_imm, cls_mem, cls_an, cls_dn} (%d classes)\n' % len(CLS_UNIQ),
         ]
    w1 = []
    for hi, (r, v) in enumerate(ROM1):
        w1.append(CLSN[r['m0']] | (CLSN[r['m1']] << 8) | (CLSN[r['mm']] << 16) | (CLSN[r['mi']] << 24) | (VALID.index(v) << 32))
    o.append(rom_module('m68ksv_drom1' + SFX, 10, 36 if IS020 else 35, w1))
    o.append('\n// drom1 in logic (checkpoint 6, RES = 1: the logic-heavy setting)\n')
    o.append(rom_module('m68ksv_drom1' + SFX + '_lh', 10, 36 if IS020 else 35, w1, style='logic'))
    if CPU == 68010:
        # cp5: loopable() of opcode[15:6] with EA mode Dn (bits 2-0) / An (5-3) / (An), (An)+, -(An) (8-6), two read
        # ports (IRN: the loop-mode entry check, IR: a format-8 RTE rebuilding a loop)
        wl = []
        for hi in range(1024):
            assert loopable((hi << 6) | 0o30) == loopable((hi << 6) | 0o40) == loopable((hi << 6) | 0o20), hi
            wl.append(loopable(hi << 6) | (loopable((hi << 6) | 0o10) << 3) | (loopable((hi << 6) | 0o20) << 6))
        o.append('\n// drom1lp (68010): opcode[15:6] -> loopable() for EA modes {(An) (An)+ -(An), An, Dn} (two read ports)\n')
        for sfx_, st_ in (('', 'M10K'), ('_lh', 'logic')):        # _lh: in logic (checkpoint 6, RES = 1)
            o.append('module m68ksv_drom1lp_010%s (\n    input  logic clk,\n    input  logic [9:0] aa,\n    input  logic [9:0] ab,\n'
                     '    output logic [8:0] qa,\n    output logic [8:0] qb\n);\n(* romstyle = "%s" *) logic [8:0] rom [0:1023];\ninitial begin\n' % (sfx_, st_))
            for i, v in enumerate(wl): o.append("    rom[%d] = 9'h%x;\n" % (i, v))
            o.append('end\nalways_ff @(posedge clk) begin\n    qa <= rom[aa];\n    qb <= rom[ab];\nend\nendmodule\n')
    o.append('\n')
    o.append('// drom2: class -> {priv, nofl, szrule[2:0], ca[2:0], aluop[5:0], k2[3:0], k1[3:0], body[9:0]}\n')
    for i, n in enumerate(CLS_UNIQ):
        o.append('//   %3d %s\n' % (i, n))
    o.append(rom_module('m68ksv_drom2' + SFX, 8, 34 if IS020 else 33, [cls_word(n) for n in CLS_UNIQ]))
    o.append('\n')
    o.append('// drom3: {kind3, mode index} -> routine address (two read ports)\n')
    o.append('module m68ksv_drom3%s (\n    input  logic clk,\n    input  logic [7:0] aa,\n    input  logic [7:0] ab,\n'
             '    output logic [10:0] qa,\n    output logic [10:0] qb\n);\n' % SFX)
    o.append('(* romstyle = "M10K" *) logic [10:0] rom [0:255];\ninitial begin\n')
    for k in range(16):
        for mi in range(16):
            if k < len(K3):
                v = eatab_addr(K3[k], mi)
            else:
                v = LABELS['EXC_ILL']
            o.append("    rom[%d] = 11'd%d;\n" % (k * 16 + mi, v))
    o.append('end\nalways_ff @(posedge clk) begin\n    qa <= rom[aa];\n    qb <= rom[ab];\nend\nendmodule\n\n')
    o.append('// special table for 4E40-4E7F: opcode[5:0] -> class\n')
    o.append('module m68ksv_drom4e%s (\n    input  logic clk,\n    input  logic [5:0] a,\n    output logic [7:0] q\n);\n' % SFX)
    o.append('always_ff @(posedge clk) begin\n    case (a)\n')
    for lo in range(64):
        o.append("    6'd%d: q <= 8'd%d;\n" % (lo, CLSN[SPEC4E[lo]]))
    o.append("    default: q <= 8'd0;\n    endcase\nend\nendmodule\n")
    return ''.join(o)

def emit_labels():
    # UA_*: the 68000 labels at their addresses in the 68010 / 68020 ROMs (= the 68000 microcode before the compaction);
    # the RTL-named ones (package UA_*) and the reset / exception and Bcc / BSR blocks are the same in the compacted
    # 68000-family ROM, whose own addresses are UA0_* (checkpoint 6)
    o = ['// Generated by rtl/gen/m68ksv_ucode.py - do not edit. Micro-addresses of the m68ksv microcode labels.\n',
         '#pragma once\n']
    for _k, _v in sorted(LABELS_PRE.items(), key=lambda x: x[1]):
        o.append('#define UA_%s %d\n' % (_k, _v))
    o.append('// 68000-family ROM (compacted, checkpoint 6): its own label addresses\n')
    for _k, _v in sorted(LABELS.items(), key=lambda x: x[1]):
        o.append('#define UA0_%s %d\n' % (_k, _v))
    return ''.join(o)

def emit_labels10():
    o = ['// 68010 ROM set: labels of the appended 68010 routines (the 68000 labels above keep their addresses)\n']
    for _k, _v in sorted(LABELS.items(), key=lambda x: x[1]):
        if _v >= N68K: o.append('#define UA10_%s %d\n' % (_k, _v))
    return ''.join(o)

def emit_labels20():
    o = ['// 68020 ROM set: labels of the appended 68010 / 68020 routines (the 68000 labels above keep their addresses)\n']
    for _k, _v in sorted(LABELS.items(), key=lambda x: x[1]):
        if _v >= N68K: o.append('#define UA20_%s %d\n' % (_k, _v))
    return ''.join(o)

def emit_pkg20():
    """68020 additions to the package: its microword width, the addresses of its own labels and the decode classes the
    RTL uses"""
    o = ['// 68020 ROM set\n', 'localparam int UW20 = %d;\n' % UW]
    for k in UA20_EXPORT:
        o.append('localparam logic [10:0] U20_%s = 11\'d%d;\n' % (k, LABELS[k]))
    o.append('localparam logic [7:0] CLS20_ILL = 8\'d%d, CLS20_BCC = 8\'d%d, CLS20_BSR = 8\'d%d, CLS20_TRAPCC = 8\'d%d;\n'
             % (CLSN['ILL'], CLSN['BCC'], CLSN['BSR'], CLSN['TRAPCC20']))
    o.append(emit_umask())
    return ''.join(o)

def emit_dump():
    o = []
    if '-w' in sys.argv:            # bus words: address label+offset bus pu pl (for the BERR frame analysis)
        _lab = sorted(LABELS.items(), key=lambda x: x[1])
        for _i, _w in enumerate(CODE):
            if _w.get('bus', 'NONE') == 'NONE': continue
            _n = max((x for x in _lab if x[1] <= _i), key=lambda x: x[1])
            o.append('W %d %s+%d %s %s %d' % (_i, _n[0], _i - _n[1], _w['bus'], _w.get('pu', 'NONE'), int(_w.get('pl', 0))))
    if '-l' in sys.argv:
        for k, v in sorted(LABELS.items(), key=lambda x: x[1]):
            o.append('%4d %s' % (v, k))
    return '\n'.join(o)

RESULT = dict(
    shared=dict([('UA_' + k, LABELS[k]) for k in SHARED_UA] + [('CLS_' + k, CLSN[k]) for k in ('ILL', 'BCC', 'BSR')] +
                [('UW0', UW0)]),
    pkg=emit_pkg() if not IS010 else '', pkg10=emit_pkg10() if CPU == 68010 else '', pkg20=emit_pkg20() if IS020 else '',
    urom=emit_urom() + '\n' + emit_ucs(), drom=emit_drom(),
    labels=emit_labels() if not IS010 else '', labels10=emit_labels10() if CPU == 68010 else '',
    labels20=emit_labels20() if IS020 else '', dump=emit_dump(),
    summary='%d words x %d bits, %d classes, %d labels' % (len(CODE), UW, len(CLS_ORDER), len(LABELS)))
