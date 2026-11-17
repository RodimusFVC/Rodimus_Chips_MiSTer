# Copyright (C) 2026 Rodimus
# m68ksv: 68010 microcode (patches and appended routines), executed by m68ksv_ucode.py inside its 68010 run (IS010).
# In-place patches keep every word count, so all 68000 labels keep their addresses; new routines are appended.
# Sources: MC68010 / MC68012 data sheet (1985) section 5, M68000 User's Manual rev 8 sections 6 / 9 / appendix A,
# M68000 Programmer's Reference Manual (1992); Musashi (MAME) as the lockstep oracle (REPORT.md "Checkpoint 3").

def patch(lab, off, **kw):
    """change fields of an existing 68000 word in place (same address)"""
    w = CODE[LABELS[lab] + off]
    w.update(kw)

def exc_words(start):
    """exception-sequence bus words run word cycles"""
    for i in range(start, len(CODE)):
        if CODE[i].get('bus', 'NONE') in ('RD', 'WR') and 'bs' not in CODE[i]:
            CODE[i]['bs'] = 'WORD'

# LINK A7 pushes the decremented A7 (Musashi; fx68k / the 68000 microcode push the old A7)
assert CODE[LABELS['LINK'] + 1].get('xa') == 'AY'
patch('LINK', 1, xa='AYLK')

# ---- group 1 / 2 exception frame: format 0, four words (SR, PC, format / vector offset); 68010: TRAP 38(4/4) ----
_x0 = len(CODE)
patch('EXC12', 0, sq='NXT', nxt='EXC12_010')          # (EXCENT stays in the 68000 word)
patch('EXC12C', 0, sq='NXT', nxt='EXC12_010')
L('EXC12_010')                                          # entered with AT = SSP - 2
U(b=('WR', 'AT'), dw='FMT', au=('AT', 'M2', 'AT'))     # format / vector offset at SSP - 2
U()
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'))    # PC low at SSP - 4
U()
U(b=('WR', 'AT'), dw='SRT', au=('AT', 'P2', 'AT'))     # SR at SSP - 8
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='PCXH')                           # PC high at SSP - 6
U(sq='NXT', nxt='VECTAIL')                              # vector at VBR + 4 x vector (m68ksv_eu)

# interrupt: PC low before the IACK cycle as on the 68000, the format word (with the vector) after it; 46(5/4)
patch('EXC_INT', 0, sq='NXT', nxt='EXC_INT_010')
L('EXC_INT_010')
U(ms='SETIPL', au=('SSP', 'M4', 'AT'))
U(b=('WR', 'AT'), dw='PCXL', au=('AT', 'M4', 'AT'))    # PC low at SSP - 4
U()
U(b=('IACK', 'IACKA'), bf='CPU', bs='WORD', bd='LO')
U()
U(ms='VINT')
U(ms='IRCIR')
U(b=('WR', 'AT'), dw='SRT', au=('AT', 'ZERO', 'SP'))   # SR at SSP - 8, SP = SSP - 8
U(au=('AT', 'P2', 'AT'))
U(b=('WR', 'AT'), dw='PCXH', au=('AT', 'P4', 'AT'))    # PC high at SSP - 6
U()
U(b=('WR', 'AT'), dw='FMT')                            # format / vector offset at SSP - 2
U(sq='NXT', nxt='VECTAIL')
exc_words(_x0)

# ---- RTE: SR, PC, then the format word; format 0 returns, format 8 continues a suspended instruction, any other
# format is a format error (vector 14) with the stack unchanged; 68010 RTE short 24(6/0) ----
L('RTE10')
U(b=('RD', 'SP'), bd='LO', bs='WORD', au=('SP', 'P2', 'AT'), fx='LSR')
U()
U(b=('RD', 'AT'), bd='HI', bs='WORD', au=('AT', 'P2', 'AT'), alu=('PASS', 'DT', 'ZERO', 'IM', 'WORD'))     # IM = SR
U()
U(b=('RD', 'AT'), bd='LO', bs='WORD', au=('AT', 'P2', 'AT'))                                              # DT = PC
U()
U(b=('RD', 'AT'), bd='LO', bs='WORD', alu=('PASS', 'DT', 'ZERO', 'PCX', 'LONG'))                # format word
U()
U(sq='BT', cd='FMT0', nxt='RTE10_F0')
U(sq='BT', cd='FMT8', nxt='RTE10_F8')
# format error: short frame below the unchanged stack, PC = the next instruction (Musashi)
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VFMT', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12')
L('RTE10_F0')
U(alu=('PASS', 'PCX', 'ZERO', 'DT', 'LONG'), au=('AT', 'P2', 'SP'))                            # SP + 8
U(alu=('PASS', 'IM', 'ZERO', 'SR', 'WORD'), sq='NXT', nxt='JMPDT')
# format 8 (bus / address error frame, 29 words; layout in EXC0_010 below): the rest of the frame is read upwards from
# SP + 8 with SP as the pointer (the 16-bit words straight into their registers, 32-bit values through DT); the version
# number (SP + 26 bits 13-10) must be 0, else format error with SP unchanged; then the faulted cycle is re-run (unless
# SSW.RR is set: the handler completed it, its read data in DIB / IIB), SR restored and the instruction continued
# (data sheet 5.3.9 / 5.4). 68010: long RTE 110-112 clocks
def _rd(fx=None, **kw):
    U(b=('RD', 'SP'), bf='SUPD', bs='WORD', **(dict(fx=fx) if fx else {}), **kw)
L('RTE10_F8')
# validity (version word, SP + 26) and accessibility (last word, SP + 56) first, with AT as the pointer and nothing of
# the frame loaded: a bus error there is an ordinary bus error of the RTE; after it any bus error is a double fault
for _k in range(5): U(au=('AT', 'P4', 'AT'))                                # AT = frame + 26
U(b=('RD', 'AT'), bf='SUPD', bs='WORD', fx='LI0', au=('AT', 'P4', 'AT'))    # +26 version
U(au=('AT', 'P4', 'AT'))
U(sq='BF', cd='VERSOK', nxt='RTE10_VERR', au=('AT', 'P4', 'AT'))
for _k in range(4): U(au=('AT', 'P4', 'AT'))
U(au=('AT', 'P2', 'AT'))                                                    # AT = frame + 56
U(b=('RD', 'AT'), bf='SUPD', bs='WORD')                                     # +56 accessibility
U()
U(fx='G0ON', au=('SP', 'P4', 'SP'))
U(au=('SP', 'P4', 'SP'))                                                    # SP = frame + 8
_rd('LSSW', au=('SP', 'P2', 'SP'))                                          # +8  SSW
U(au=('PCX', 'P4', 'FPC'))                                                  # prefetch address = PC + 4
_rd('LFAH', au=('SP', 'P2', 'SP')); U()                                     # +10 fault address
_rd('LFAL', au=('SP', 'P4', 'SP')); U()                                     # +12
_rd('LDOB', au=('SP', 'P4', 'SP')); U()                                     # +16 data output buffer
_rd('LDIB', au=('SP', 'P4', 'SP')); U()                                     # +20 data input buffer
_rd('LIIB', au=('SP', 'P2', 'SP')); U()                                     # +24 instruction input buffer (IRC)
_rd('LI0', au=('SP', 'P2', 'SP')); U()                                      # +26 version / flags
_rd('LI1', au=('SP', 'P2', 'SP')); U()                                      # +28 resume micro-address
_rd('LIR', au=('SP', 'P2', 'SP')); U()                                      # +30 IR (decoded from now on)
_rd(bd='HI', au=('SP', 'P2', 'SP')); U()                                    # +32 PCX
_rd(bd='LO', au=('SP', 'P2', 'SP')); U()                                    # +34
_rd(bd='HI', au=('SP', 'P2', 'SP'), alu=('PASS', 'DT', 'ZERO', 'PCX', 'LONG')); U()      # +36 slot A
_rd(bd='LO', au=('SP', 'P2', 'SP')); U()                                    # +38
_rd('MSLA', bd='HI', au=('SP', 'P2', 'SP')); U(fx='RSTR')                   # +40 slot B; sequencer state from IR
_rd(bd='LO', au=('SP', 'P2', 'SP')); U()                                    # +42
_rd('LAURH', au=('SP', 'P2', 'SP')); U(fx='MSLB')                           # +44 AUR (kept until the end: every word here
_rd('LAURL', au=('SP', 'P2', 'SP')); U()                                    # +46  writes AUR)
_rd('LIRN', au=('SP', 'P2', 'SP')); U()                                     # +48 IRN
_rd(bd='HI', au=('SP', 'P2', 'SP')); U()                                    # +50 DT
_rd(bd='LO', au=('SP', 'P2', 'SP')); U()                                    # +52
_rd('LATH', au=('SP', 'P2', 'SP')); U()                                     # +54 AT
_rd('LATL', au=('SP', 'P2', 'SP')); U()                                     # +56; SP = frame + 58
U(sq='BT', cd='RRSET', nxt='RTE10_SW', fx='G0OFF')                        # the re-run is part of the instruction
U(sq='BT', cd='SSWRM', nxt='RTE10_RRTAS')
U(sq='BT', cd='SSWIF', nxt='RTE10_RRIF')
U(sq='BT', cd='SSWRW', nxt='RTE10_RRRD')
U(b=('WR', 'FA'), bs='SSW', sf='SSW', dw='X10', fx='DOB', rr=1)             # re-run: write
U()
U(sq='NXT', nxt='RTE10_END')
L('RTE10_RRRD')
U(b=('RD', 'FA'), bs='SSW', sf='SSW', rr=1)                                 # re-run: data read (destination as saved)
U()
U(sq='NXT', nxt='RTE10_END')
L('RTE10_RRIF')
U(b=('NPE', 'FA'), sf='SSW', rr=1)                                          # re-run: prefetch (IRC, fpc = FA + 2)
U()
U(sq='NXT', nxt='RTE10_END')
L('RTE10_RRTAS')                                                            # re-run: the whole read-modify-write
U(b=('TAS', 'FA'), bs='BYTE', sf='SSW', rr=1)
U()
U(dw='TASB')
U()
U()
U(sq='NXT', nxt='RTE10_END')
L('RTE10_SW')                                                               # completed by software
U(x1='SWDONE')
L('RTE10_END')
U(x1='SRF', fx='MAUR')                                                      # SR, trace state, AUR from the frame
U(sq='RSM')
L('RTE10_VERR')                                                             # wrong version: format error, SP unchanged
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VFMT', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12')

# ---- bus / address error: format 8, 29 words (26 written), pushed downwards from SSP - 2 (data sheet figure 5-9):
#  +0 SR  +2/+4 PC (prefetch address - 4: "may be advanced by up to five words")  +6 $8000 | vector offset
#  +8 SSW (RR IF DF RM HB BY RW, FC)  +10/+12 fault address  +16 DOB  +20 DIB (0)  +24 IIB (IRC)
#  +26 {fin, chain stage, version 0 (13-10), layout A / B, read destination (bd), trace, loop mode, held X V C}
#  +28 {held N Z rule, held X, resume micro-address}  +30 IR  +32 PCX  +36 slot A (IM | SRT, vector)
#  +40 slot B (RES | MOVEM mask, count)  +44 AUR (24 bits)  +48 IRN  +50 DT  +54 AT
# The faulting word completes (68010: its register writes are kept - continuation); AT is pushed first and then used
# as the pointer; everything the pushes would disturb (AUR, the trace flag, the resume address) was captured at the
# fault (m68ksv_eu). A fault during this sequence halts (group-0 state).
# (the 68020 pushes its own format-B frame, m68ksv_ucode020.py EXC0_020: no format-8 push in its ROM set)
if not IS020:
    patch('EXC0', 0, ms='NONE', sq='NXT', nxt='EXC0_010')
    L('EXC0_010')
    _w = lambda dw, fx=None, au=('AT', 'M2', 'AT'): (U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw=dw, au=au, **(dict(fx=fx) if fx else {})), U())
    U(au=('SSP', 'M4', 'NONE'))
    U(b=('WR', 'AUR'), bf='SUPD', bs='WORD', dw='ATH', au=('SSP', 'M2', 'NONE'))   # +54 (AT intact for both halves)
    U()
    U(b=('WR', 'AUR'), bf='SUPD', bs='WORD', dw='ATL', au=('SSP', 'M4', 'AT'))  # +56
    U(au=('AT', 'M2', 'AT'))
    _w('DTL'); _w('DTH')                                                        # +52 +50
    _w('X10', 'IRN')                                                            # +48
    _w('X10', 'AURL'); _w('X10', 'AURH')                                        # +46 +44
    _w('X10', 'SLBL'); _w('X10', 'SLBH')                                        # +42 +40
    _w('X10', 'SLAL'); _w('X10', 'SLAH')                                        # +38 +36
    _w('PCXL'); _w('PCXH')                                                      # +34 +32
    _w('X10', 'IR')                                                             # +30
    _w('X10', 'I1')                                                             # +28
    U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='X10', fx='I0', au=('AT', 'M2', 'AT'))   # +26
    U(ms='EXCENT')                                                              # SRT = SR; S = 1, T = 0
    _w('X10', 'IIB', ('AT', 'M4', 'AT'))                                        # +24
    _w('X10', 'DIB', ('AT', 'M4', 'AT'))                                        # +20
    _w('X10', 'DOB', ('AT', 'M4', 'AT'))                                        # +16
    _w('FAL'); _w('FAH')                                                        # +12 +10
    U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='X10', fx='SSW', au=('AT', 'M2', 'AT'), x1='VG0')   # +8
    U(alu=('ADD', 'FPC', 'M4', 'PCX', 'LONG'))
    _w('X10', 'FMT8')                                                           # +6
    _w('PCXL'); _w('PCXH')                                                      # +4 +2
    U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='SRT', au=('AT', 'ZERO', 'SP'))  # +0, SP = frame
    U(sq='NXT', nxt='VECTAIL')

# TAS: a re-run repeats the whole read-modify-write and continues at its final prefetch
assert CODE[LABELS['TASM_2'] + 4].get('bus') == 'NPF'
LABELS['TASM_NPF'] = LABELS['TASM_2'] + 4

# format-8 layouts of each bus word (field ly): exception sequences keep {SRT, vector} in slot A and {mask, count} in
# slot B (IM / RES are dead there); multiply, shifts and MOVEM keep {mask, count} in slot B (RES dead)
def _region(a, b):
    return range(LABELS[a], LABELS[b])
_ly3 = list(_region('EXC12', 'HALT')) + list(_region('EXC12_010', 'RTE10'))
_ly1 = list(_region('MUL', 'DIV')) + list(_region('SHR', 'MUL')) + list(range(LABELS['MVLP_000'], N68K))
for _i in _ly3:
    if CODE[_i].get('bus', 'NONE') != 'NONE': CODE[_i]['ly'] = 3
for _i in _ly1:
    if CODE[_i].get('bus', 'NONE') != 'NONE': CODE[_i]['ly'] = 1

# ---- RTD #d16: PC from the stack, SP + 4 + d16; 16(4/0) ----
L('RTD10')
U(b=('RD', 'SP'), bd='HI', bs='WORD', au=('SP', 'P2', 'AT'))
U(au=('SP', 'D16', 'PCX'))
U(b=('RD', 'AT'), bd='LO', bs='WORD')
U(sq='NXT', nxt='RTD10J')
L('RTD10J')
U(b=('NPE', 'DT'), au=('PCX', 'P4', 'SP'))
U()
U(b=('NPF',))
U(sq='FIN')

# ---- MOVEC: control register code in the extension word (IRC); SFC 000, DFC 001, USP 800, VBR 801, any other code is
# an illegal instruction (PC = MOVEC); Rc -> Rn 10(2/0), Rn -> Rc 12(2/0) ----
L('MOVEC_R')
U(ms='LDCX', sq='BF', cd='CRVALID', nxt='EXC_ILL')
U(b=('NPE',), alu=('PASS', 'CTL', 'ZERO', 'NONE', 'LONG'), xe='RCD')
U()
U(b=('NPF',))
U(sq='FIN')
L('MOVEC_W')
U(ms='LDCX', sq='BF', cd='CRVALID', nxt='EXC_ILL')
U(b=('NPE',), alu=('PASS', 'RC', 'ZERO', 'NONE', 'LONG'), xe='CTLW')
U()
U()
U(b=('NPF',))
U(sq='FIN')

# ---- MOVES: extension word (kind XWD), the address (ADDR), then the access with the SFC / DFC function code ----
L('MVS_X')
U(b=('NPE',), ms='LDCX')
U(sq='CONT')
EATAB['XWD'] = [None, None] + ['MVS_X'] * 7 + [None] * 7
L('MOVES10')
U(sq='BT', cd='CXDR', nxt='MOVES_W')
U(sq='BT', cd='SZL', nxt='MOVES_RL')
U(b=('RD', 'AT'), sf='SFC')                                                    # memory -> register: byte / word
U()
U(b=('NPF',), alu=('SEXT', 'DT', 'ZERO', 'NONE'), xe='RCD')                    # An: sign-extended, Dn: low part
U(sq='FIN')
L('MOVES_RL')
U(b=('RD', 'AT'), sf='SFC', bd='HI', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), sf='SFC', bd='LO')
U()
U(b=('NPF',), alu=('PASS', 'DT', 'ZERO', 'NONE', 'LONG'), xe='RCD')
U(sq='FIN')
L('MOVES_W')                                                                    # register -> memory
U(sq='BT', cd='SZL', nxt='MOVES_WL')
U(b=('WR', 'AT'), sf='DFC', dw='RCL')
U()
U(b=('NPF',))
U(sq='FIN')
L('MOVES_WL')
U(b=('WR', 'AT'), sf='DFC', dw='RC1', au=('AT', 'P2', 'NONE'))
U()
U(b=('WR', 'AUR'), sf='DFC', dw='RCL')
U()
U(b=('NPF',))
U(sq='FIN')

# ---- BKPT #n: breakpoint acknowledge cycle (CPU space, all address lines low, no data taken; DTACK, VPA or BERR end
# it), then illegal instruction processing (PC = BKPT) ----
L('BKPT10')
U(b=('IACK', 'BKPT'), bf='CPU', bs='WORD')
U()
U(sq='NXT', nxt='EXC_ILL')

# ---- MOVE from SR (privileged) / MOVE from CCR: register 4(1/0); memory 8(1/1) + no-fetch EA (no read) ----
L('MVFSR_DN10')
U(b=('NPF',), alu=('PASS', 'SR', 'ZERO', 'DY', 'WORD'))
U(sq='FIN')
L('MVFCCR_DN10')
U(b=('NPF',), alu=('PASS', 'CCR', 'ZERO', 'DY', 'WORD'))
U(sq='FIN')
for _lab, _dw in (('MVFSR_M10', 'SRW'), ('MVFCCR_M10', 'CCRW')):
    L(_lab)
    U(b=('WR', 'AT'), dw=_dw, bs='WORD')
    U()
    U(b=('NPF',))
    U(sq='FIN')

# ---- Scc <ea>: 68010 writes without reading; 8(1/1) + no-fetch EA ----
L('SCCW10')                                                                 # 8(1/1) + ea (table 7-12): data from cc
U(b=('WR', 'AT'), dw='SCC', bs='BYTE')
U()
U(b=('NPF',))
U(sq='FIN')

# ---- CLR <ea>: 68010 writes without reading (MC68010 table 9-10: (An) 8(1/1), (An)+ 8, -(An) 10, (d16,An) 12,
# (d8,An,Xn) 16, abs.W 12, abs.L 16; long + 4 and a second write); flags with the first write ----
_clr = dict(alu=('CLR', 'ZERO', 'ZERO', 'NONE'), fl=1)
_t = [None] * 16
def _clr_tail(first, au_first, tail_l):
    U(b=('WR', first), au=au_first, sq='BT', cd='SZL', nxt=tail_l, **_clr)
    U()
    U(b=('NPF',))
    U(sq='FIN')
L('CLRW_AI'); _t[2] = 'CLRW_AI'
_clr_tail('AY', ('AY', 'P2', 'AT'), 'CLRW_LT')
L('CLRW_PI'); _t[3] = 'CLRW_PI'
U(b=('WR', 'AY'), au=('AY', 'INC', 'AY'), sq='BT', cd='SZL', nxt='CLRW_PIL', **_clr)
U()
U(b=('NPF',))
U(sq='FIN')
L('CLRW_PIL')
U(au=('AY', 'M2', 'AT'))
U(b=('WR', 'AT'))
U()
U(b=('NPF',))
U(sq='FIN')
L('CLRW_PD'); _t[4] = 'CLRW_PD'
U(au=('AY', 'DEC', 'AY'))
_clr_tail('AY', ('AY', 'P2', 'AT'), 'CLRW_LT')
L('CLRW_D16'); _t[5] = 'CLRW_D16'
U(b=('NPE',), au=('AY', 'D16', 'AT'))
U()
_clr_tail('AT', ('AT', 'P2', 'NONE'), 'CLRW_LU')
L('CLRW_D8'); _t[6] = 'CLRW_D8'
U(au=('AY', 'D8', 'AT'))
U(b=('NPE',), au=('AT', 'XN', 'AT'))
U()
U()
_clr_tail('AT', ('AT', 'P2', 'NONE'), 'CLRW_LU')
L('CLRW_AW'); _t[7] = 'CLRW_AW'
U(b=('NPE',), au=('ZERO', 'D16', 'AT'))
U()
_clr_tail('AT', ('AT', 'P2', 'NONE'), 'CLRW_LU')
L('CLRW_AL'); _t[8] = 'CLRW_AL'
U(b=('NPE',), au=('ZERO', 'IRCH', 'AT'))
U()
U(b=('NPE',), au=('AT', 'IRCZ', 'AT'))
U()
_clr_tail('AT', ('AT', 'P2', 'NONE'), 'CLRW_LU')
L('CLRW_LT')                     # long: second write at AT (= first + 2)
U()
U(b=('WR', 'AT'))
U()
U(b=('NPF',))
U(sq='FIN')
L('CLRW_LU')                     # long: second write at AUR
U()
U(b=('WR', 'AUR'))
U()
U(b=('NPF',))
U(sq='FIN')
EATAB['CLRW'] = _t

# ---- loop mode (data sheet 7.1.3, User's Manual appendix A) ----
# Entry: a DBcc with displacement -4 branching (cc false, count valid) to a loopable one-word instruction (checked in
# m68ksv_eu on the target opcode at DB_T2), T clear. In loop mode the opcode prefetches of the three loop words (looped
# instruction, DBcc, displacement) run without a bus cycle (m68ksv_eu "ghost" cycles), and the looped instruction's
# FIN dispatches straight to DBL<n> (no interrupt there): <n> idle words chosen per looped instruction so that one
# loop pass takes the data sheet's "loop continued" time (tables 7-6 / 7-8 / 7-10 / 7-14 / 7-16 / 7-20), then the loop
# word: Dn - 1 -> Dn and a dispatch of the looped instruction from its saved decode (interrupts are taken here), or,
# on cc true / count expired, DBL_X: loop mode off and the normal DBcc exits (refetch from the next instruction).
# (the 68020 has no loop mode - its instruction cache takes that role: no loop-mode words in its ROM set)
if not IS020:
    assert CODE[LABELS['DBCC']].get('op') == 'SUB'
    patch('DBCC', 0, x1='LMCAND')                          # displacement word (IRC) = -4 ?
    assert CODE[LABELS['DB_T2']].get('bus') == 'NPF'
    patch('DB_T2', 0, x1='LMDZ')                           # branch taken: loop mode entry check on the target opcode
    L('DBL4')
    U()
    L('DBL3')
    U()
    L('DBL2')
    U()
    L('DBL1')
    U(alu=('SUB', 'ONE', 'DY', 'DY', 'WORD'), sq='FINC', cd='LMX', nxt='DBL_X', x1='LMC')
    L('DBL_X')                                             # cc true -> as DB_SKIPW; count expired -> refetch, Dn = -1
    U(alu=('SUB', 'ONE', 'DY', 'NONE', 'WORD'), au=('FPC', 'ZERO', 'NONE'), x1='LMOFF', sq='BT', cd='CC', nxt='DB_SKIPW')
    U(b=('NPE', 'AUR'))
    U(sq='NXT', nxt='DB_T2')

# ---- 68010 instruction timing (data sheet section 7) where it differs from the 68000 ----
def _relabel(lab, off, new):
    LABELS[new] = LABELS[lab] + off
# Bcc.b not taken 6(1/0) (68000: 8): the final prefetch right after the test
_i = LABELS['BCC_S']
assert CODE[_i + 2].get('bus') == 'NPF' and CODE[_i + 3].get('sq') == 'FIN'
CODE[_i + 1] = {'bus': 'NPF', 'ba': 'FPC'}
CODE[_i + 2] = {'sq': 'FIN'}
CODE[_i + 3] = {}
# Bcc.w not taken 10(2/0) (68000: 12): not taken -> BR_SKIPW at once; taken: the target fetch in the next word
_relabel('BR_TAKEN', 1, 'BR_TAKEN_1')
assert CODE[LABELS['BR_TAKEN']].get('bus') == 'NPE' and CODE[LABELS['BCC_W']].get('nxt') == 'BR_TAKEN'
patch('BCC_W', 0, sq='BF', cd='CC', nxt='BR_SKIPW')
CODE[LABELS['BCC_W'] + 1] = {'bus': 'NPE', 'ba': 'AT', 'sq': 'NXT', 'nxt': 'BR_TAKEN_1'}
# DBcc: cc true 10(2/0) (68000: 12), count expired 16(3/0) (68000: 14)
assert CODE[LABELS['DBCC']].get('nxt') == 'DB_T' and CODE[LABELS['DBCC'] + 1].get('nxt') == 'DB_EXP'
patch('DBCC', 0, nxt='DB_SKIPW')
patch('DBCC', 1, nxt='DB_EXP10')
L('DB_EXP10')
U(sq='NXT', nxt='DB_EXP')
# Scc Dn 4(1/0) whether true or false (68000: true 6)
for _k in ('sq', 'cd', 'nxt'): CODE[LABELS['SCC_D']].pop(_k)
# MOVE USP 6(1/0) (68000: 4)
for _l in ('MVUSP_TO', 'MVUSP_FROM'):
    _i = LABELS[_l]
    CODE.append(dict(CODE[_i])); LABELS[_l + '10'] = len(CODE) - 1
    CODE.append(dict(CODE[_i + 1]))
    CODE[_i] = {'sq': 'NXT', 'nxt': _l + '10'}
    CODE[_i + 1] = {}
# RESET 130(1/0) (68000: 132): RESET output from the first clock, still 124 clocks
_i = LABELS['RESETI']
assert CODE[_i + 1].get('ms') == 'RSTO1' and CODE[_i + 2].get('ms') == 'LDCNTRST'
CODE[_i] = {'ms': 'RSTO1'}
CODE[_i + 1] = {'ms': 'LDCNTRST', 'sq': 'NXT', 'nxt': 'RESETI_L'}
CODE[_i + 2] = {}
# BKPT: breakpoint cycle + illegal instruction 42(5/4) (68000 microcode path: 44)
_i = LABELS['BKPT10']
assert CODE[_i + 2].get('nxt') == 'EXC_ILL'
CODE[_i + 1] = {'sq': 'NXT', 'nxt': 'EXC_ILL'}
CODE[_i + 2] = {}
# CHK no trap 8(1/0) + ea (68000: 10): both bounds in one test word; the trap paths keep their lengths
_i = LABELS['CHK']
assert CODE[_i + 1].get('cd') == 'AUX' and CODE[_i + 2].get('cd') == 'NSET' and CODE[_i + 3].get('bus') == 'NPF'
CODE[_i + 1] = {'sq': 'BT', 'cd': 'CHKX', 'nxt': 'CHK10T'}
CODE[_i + 2] = {'bus': 'NPF', 'ba': 'FPC'}
CODE[_i + 3] = {'sq': 'FIN'}
CODE[_i + 4] = {}
L('CHK10T')
U(sq='BT', cd='AUX', nxt='EXC_CHK')
U(sq='NXT', nxt='EXC_CHK')
# .l <ea>,Dn from Dn / #imm, ADDX / SUBX .l Dy,Dx: 6 (68000: 8) - long flags at once (decode: ALU_DN2 / XREG2L10)
L('XREG2L10')
U(b=('NPF',), alu=('DEC', 'DY', 'DX', 'DX'), fl=1, lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DX', 'LONG'), sq='FIN')
# BCLR on memory: 2 clocks more than BCHG / BSET (table 7-17)
L('RMWB10')
U(sq='NXT', nxt='RMWB')
# MOVE.L Dn / An,-(An) 14(1/2) (table 7-7; 68000: 12); memory / immediate sources as on the 68000 (decode: MVL_PD10)
_i = LABELS['MVL_PD']
assert CODE[_i + 5].get('sq') == 'FIN'
L('MVL_PD10')
for _k in range(5): CODE.append(dict(CODE[_i + _k]))
U()
U(sq='FIN')
# xxxI.l #,Dn 14(3/0), EOR.l Dn,Dn 6(1/0) (68000: 16 / 8): long flags at once (decode: RDY2C10); ADDQ.w #,An 4(1/0)
# (68000: 8; decode: ADDQAW10)
L('RDY2C10')
U(b=('NPF',), alu=('DEC', 'CA', 'DY', 'DY'), fl=1, lh=1)
U()
U(alu=('PASS', 'RES', 'ZERO', 'DY', 'LONG'), sq='FIN')
L('ADDQAW10')
U(b=('NPF',), alu=('DEC', 'QUICK', 'AY', 'AY', 'LONG'))
U(sq='FIN')
# ANDI / ORI / EORI to CCR / SR 16(2/0) (68000: 20)
for _l in ('SRWI', 'CCRWI'):
    _i = LABELS[_l]
    assert CODE[_i + 3].get('nxt') == 'BR_TAKEN'
    CODE[_i + 1] = {'sq': 'NXT', 'nxt': 'BR_TAKEN'}
    CODE[_i + 2] = {}
    CODE[_i + 3] = {}
