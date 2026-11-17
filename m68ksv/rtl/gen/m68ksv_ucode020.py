# Copyright (C) 2026 Rodimus
# m68ksv: 68020 / 68EC020 microcode (patches and appended routines), executed by m68ksv_ucode.py inside its 68020 run
# (IS020), after the 68010 module (m68ksv_ucode010.py, without loop mode). In-place patches keep every word count, so
# all 68000 labels keep their addresses; new routines are appended.
# Sources: M68000 Programmer's Reference Manual (1992) for the 68020 instructions, addressing modes and frames;
# MAME's Musashi m68020 / m68ec020 as the lockstep oracle (REPORT.md "Checkpoint 4"). The MC68020 User's Manual was not
# available on disk this session (bus / timing details from memory, marked so in REPORT.md).

def patch20(lab, off, **kw):
    """change fields of an existing word in place (same address)"""
    CODE[LABELS[lab] + off].update(kw)

def at(lab, off, new):
    """name the word at lab + off (for detours that continue in the middle of a routine)"""
    LABELS[new] = LABELS[lab] + off
    return new

# ---------------------------------------------------------------------------------------------------------------
# full-format extension word (68020 addressing modes 6 / 7-3 with extension bit 8 set): base / index suppress, scale,
# 16 / 32-bit base displacement, memory indirect pre- / post-indexed with null / 16 / 32-bit outer displacement.
# Subroutine (CALL / RET), entered with IRC = the extension word and the base chosen by the entry: FEA_AY (An = ir[2:0]),
# FEA_AX (MOVE destination, An = ir[11:9]), FEA_PC (base = the extension word's address). Returns with AT = the
# effective address, every extension word consumed (IRC = the next word, fpc after it) and the bus idle. The index
# register, its size and scale come from the saved extension word (m2 LDXW -> xw, field xw on the AU word).
# The memory-indirect pointer is read as data (FC 1 / 5), as Musashi's m68ki_read_32 (PC modes included).
for _b, _aa, _ab in (('AY', 'FBY', 'ZERO'), ('AX', 'FBX', 'ZERO'), ('PC', 'FBP', 'M2')):
    L('FEA_' + _b)
    U(b=('NPE',), au=(_aa, _ab, 'AT'), m2='LDXW', sq='NXT', nxt='FEA_1')    # AT = base (0 when BS); ext consumed
L('FEA_1')
U(sq='BT', c2='XBDN', nxt='FEA_IDX')                                       # bd null
U(sq='BT', c2='XBDL', nxt='FEA_BDL')
U(b=('NPE',), au=('AT', 'D16', 'AT'))                                      # bd word
U(sq='NXT', nxt='FEA_IDX')
L('FEA_BDL')
U(b=('NPE',), au=('AT', 'IRCH', 'AT'))                                     # bd long: high word
U()
U(b=('NPE',), au=('AT', 'IRCZ', 'AT'))                                     # low word
U()
L('FEA_IDX')
U(sq='BT', c2='XNOPRE', nxt='FEA_IND')                                     # IS, or post-indexed
U(au=('AT', 'XN', 'AT'), xw=1)                                             # + Xn.size * scale
L('FEA_IND')
U(sq='BT', c2='XNIND', nxt='FEA_RET')                                      # no memory indirection
U(b=('RD', 'AT'), bd='HI', bs='WORD', au=('AT', 'P2', 'NONE'), m2='XP')    # the pointer (long) at AT -> XT (DT may
U()                                                                        # hold the source operand of a MOVE)
U(b=('RD', 'AUR'), bd='LO', bs='WORD', m2='XP')
U()
U(au=('XT', 'ZERO', 'AT'), sq='BT', c2='XNPOST', nxt='FEA_OD')
U(au=('AT', 'XN', 'AT'), xw=1)                                             # post-indexed
L('FEA_OD')
U(sq='BT', c2='XODN', nxt='FEA_RET')                                       # od null
U(sq='BT', c2='XODL', nxt='FEA_ODL')
U(b=('NPE',), au=('AT', 'D16', 'AT'))                                      # od word
U(sq='NXT', nxt='FEA_RET')
L('FEA_ODL')
U(b=('NPE',), au=('AT', 'IRCH', 'AT'))
U()
U(b=('NPE',), au=('AT', 'IRCZ', 'AT'))
U()
L('FEA_RET')
U(sq='RET')

def full_detour(lab, off, base, tail_off, post=None):
    """the brief-format word at lab + off (IRC = the extension word there) branches to the full-format subroutine
    when extension bit 8 is set; afterwards (post: an extra word's fields) the routine continues at lab + tail_off"""
    i = LABELS[lab] + off
    w = CODE[i]
    assert w.get('sq', 'NXT') == 'NXT' and w.get('nxt') is None and w.get('bus', 'NONE') == 'NONE', (lab, off, w)
    w.update(sq='BT', c2='FULLX', nxt=lab + '_F')
    L(lab + '_F')
    U(sq='CALL', nxt='FEA_' + base)
    U(sq='NXT', nxt=at(lab, tail_off, lab + '_FT'), **(post or {}))

for _k in ('RDW', 'RDL'):
    full_detour(_k + '_D8', 0, 'AY', 3)
    full_detour(_k + '_P8', 0, 'PC', 3)
full_detour('ADDR_D8', 0, 'AY', 2)
full_detour('ADDR_P8', 0, 'PC', 2)
for _k in ('JMP', 'JSR'):
    _post = dict(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG')) if _k == 'JSR' else None    # return address
    full_detour(_k + '_D8', 0, 'AY', 3, _post)
    full_detour(_k + '_P8', 0, 'PC', 3, _post)
full_detour('LEA_D8', 0, 'AY', 3)
full_detour('LEA_P8', 0, 'PC', 3)
full_detour('PEA_D8', 0, 'AY', 4)
full_detour('PEA_P8', 0, 'PC', 4)
for _k in ('MVRMW', 'MVRML', 'MVMRW', 'MVMRL'):
    full_detour(_k + '_D8', 2, 'AY', 4)
    if _k.startswith('MVMR'):
        full_detour(_k + '_P8', 2, 'PC', 4)
for _k in ('MV_D8', 'MV_D8R', 'MVL_D8_R', 'MVL_D8_M'):
    full_detour(_k, 0, 'AX', 3)
full_detour('CLRW_D8', 0, 'AY', 4)

# ---------------------------------------------------------------------------------------------------------------
# Bcc.L / BSR.L (displacement byte $FF: 32-bit displacement in the next two words, relative to the first one)
L('BCC_L')
U(au=('FPC', 'M2', 'AT'), sq='BF', cd='CC', nxt='BCC_LN')                  # AT = PC (the displacement's address)
U(b=('NPE',), au=('AT', 'IRCH', 'AT'))                                     # + high word; IRC <- low word
U()
U(au=('AT', 'IRCZ', 'AT'), sq='NXT', nxt='BR_TAKEN')                       # + low word: the target
L('BCC_LN')                                                                # not taken: skip both words
U(b=('NPE',))
U()
U(b=('NPE',))
U()
U(b=('NPF',))
U(sq='FIN')
L('BSR_L')
U(au=('FPC', 'M2', 'AT'))
U(b=('NPE',), au=('AT', 'IRCH', 'AT'))
U()
U(au=('AT', 'IRCZ', 'AT'))                                                 # target
U(au=('SP', 'M4', 'SP'), alu=('ADD', 'FPC', 'ZERO', 'PCX', 'LONG'))        # return address (after both words)
U(b=('WR', 'SP'), dw='PCXH', sq='NXT', nxt='BSR_T')
UA20_EXPORT += ['BCC_L', 'BSR_L']

# ---------------------------------------------------------------------------------------------------------------
# exception frames. Format 0 (four words: TRAP #n, illegal, privilege, line A / F, format error, interrupt) as the
# 68010. Format 2 (six words: SR, PC = the next instruction, $2000 | vector offset, the address of the instruction that
# caused it) for CHK / CHK2, TRAPV, TRAPcc, zero divide and trace (PRM / Musashi m68ki_exception_trap and _trace).
# Entered like EXC12 (PCX and the vector set, AT = SSP - 2; SSP = ISP or MSP by the M bit, m68ksv_eu).
L('EXC12_F2')
U(ms='EXCENT')
U(b=('WR', 'AT'), d2='PPCL', bs='WORD', au=('AT', 'M2', 'AT'))             # instruction address, low at SSP - 2
U()
U(b=('WR', 'AT'), d2='PPCH', bs='WORD', au=('AT', 'M2', 'AT'))             # high at SSP - 4
U()
U(b=('WR', 'AT'), d2='F2', bs='WORD', au=('AT', 'M2', 'AT'))               # format 2 / vector offset at SSP - 6
U()
U(b=('WR', 'AT'), dw='PCXL', bs='WORD', au=('AT', 'M4', 'AT'))             # PC low at SSP - 8
U()
U(b=('WR', 'AT'), dw='SRT', bs='WORD', au=('AT', 'P2', 'AT'))              # SR at SSP - 12
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='PCXH', bs='WORD')                                    # PC high at SSP - 10
U(sq='NXT', nxt='VECTAIL')
for _lab in ('EXC_TRACE', 'EXC_CHK', 'EXC_TRAPV', 'EXC_DIV0'):
    assert CODE[LABELS[_lab]].get('nxt') in ('EXC12', 'EXC12C'), _lab
    patch20(_lab, 0, nxt='EXC12_F2')
assert CODE[LABELS['TRAPV']].get('nxt') == 'EXC12' and CODE[LABELS['DIV_Z']].get('nxt') == 'EXC12C'
patch20('TRAPV', 0, nxt='EXC12_F2')
patch20('DIV_Z', 0, nxt='EXC12_F2')

# ---------------------------------------------------------------------------------------------------------------
# instructions new to the 68020 (core set)
# extension word first (kind XWD -> cx) for every mode: MUL.L / DIV.L / CHK2 / CAS / bit fields (MOVES's own modes are
# limited by its validity class)
EATAB['XWD'] = ['MVS_X'] * 12 + [None] * 4

# CHK.L <ea>,Dn: as CHK.W (68010 flags: Z of Dn, V = C = 0, N only when trapping), 32-bit compare; format-2 frame
L('CHKL20')
U(alu=('CHK', 'EAV', 'DX', 'NONE', 'LONG'), fl=1)
U(sq='BT', cd='CHKX', nxt='CHK10T')
U(b=('NPF',))
U(sq='FIN')

# EXTB.L Dn
L('EXTB20')
U(b=('NPF',), alu=('EXTB', 'ZERO', 'DY', 'DY', 'LONG'), fl=1)
U(sq='FIN')

# LINK A7 (2026-11-16): the 68020 pushes A7 as it was before the decrement - WinUAE's 68020 tables (gencpu.cpp i_LINK,
# "smode must be first in case it is A7"; Amiberry run T10), as the 68000 microcode (fx68k); the 68010 module's patch
# (xa AYLK: the decremented A7, Musashi) is undone for the 68020
assert CODE[LABELS['LINK'] + 1].get('xa') == 'AYLK'
patch20('LINK', 1, xa='AY')
# LINK.L An,#d32: push An (A7: the old A7, as LINK.W above), An = SP - 4, SP = An + d32
L('LINKL20')
U(au=('SP', 'M4', 'AT'))                                                   # AT = SP - 4
U(b=('NPE',), au=('AT', 'IRCH', 'PCX'))                                    # PCX = AT + d32 high; IRC <- low word
U(alu=('PASS', 'AY', 'ZERO', 'IM', 'LONG'))                                 # (SP is written below: AY = the old A7)
U(b=('WR', 'AT'), dw='IMH', au=('AT', 'ZERO', 'AY'), lk=2)                 # push; An = SP - 4
U(au=('AT', 'P2', 'NONE'))
U(b=('WR', 'AUR'), dw='IML')
U(au=('PCX', 'IRCZ', 'SP'))                                                # SP = SP - 4 + d32
U(b=('NPE',))                                                              # IRC <- the next opcode
U()
U(b=('NPF',))
U(sq='FIN')

# TRAPcc (#.W / #.L operand words skipped): taken -> format-2 frame, vector 7, PC = the next instruction
L('TRAPCC20')
U(sq='BT', c2='TOPW', nxt='TRAPCC20_W')
U(sq='BT', c2='TOPL', nxt='TRAPCC20_L')
L('TRAPCC20_T')
U(b=('NPF',), alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VTRAPV', au=('SSP', 'M2', 'AT'), sq='BT', cd='CC', nxt='EXC12_F2')
U(sq='FIN')
L('TRAPCC20_L')
U(b=('NPE',))
U()
L('TRAPCC20_W')
U(b=('NPE',))
U(sq='NXT', nxt='TRAPCC20_T')

# MUL.L <ea>,Dl / <ea>,Dh:Dl (cx = extension word: Dl 14-12, signed 11, 64-bit 10, Dh 2-0): the operands go into the
# DSP multiplier once (m2 MULL), Dh is written first, then Dl with the flags (Musashi's order: Dl wins when Dh = Dl)
L('MULL20')
U(alu=('NOP', 'EAV', 'RC', 'NONE', 'LONG'), m2='MULL', sq='BF', c2='MUL64', nxt='MULL20_32')
U(alu=('MULLH', 'EAV', 'RC', 'NONE', 'LONG'), xe='RCH')
U(b=('NPF',), alu=('MULLL', 'EAV', 'RC', 'NONE', 'LONG'), xe='RCL', fl=1)
U(sq='FIN')
L('MULL20_32')
U()
U(b=('NPF',), alu=('MULLL', 'EAV', 'RC', 'NONE', 'LONG'), xe='RCL', fl=1)
U(sq='FIN')

# DIV.L <ea>,Dq / Dr:Dq (cx: Dq 14-12, signed 11, 64-bit dividend 10, Dr 2-0): divisor and Dq latched (DVLINIT), Dr /
# the extension of Dq (DVLHI), zero divide (format-2 frame, flags unchanged as Musashi), early overflow (|dividend
# high| >= |divisor|), 32 restoring steps, late overflow (signed range), remainder to Dr, quotient to Dq (wins when
# Dr = Dq) with N / Z, V = C = 0. Overflow: V = 1, C = 0, N / Z and the registers unchanged.
L('DIVL20')
U(alu=('NOP', 'EAV', 'RC', 'NONE', 'LONG'), m2='DVLINIT')
U(alu=('NOP', 'ZERO', 'RCH', 'NONE', 'LONG'), m2='DVLHI')
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), sq='BT', c2='DVZL', nxt='DIVL20_Z')      # PCX for the zero-divide frame
U(sq='BT', c2='DVOVL', nxt='DIVL20_OV')
L('DIVL20_L')
U(m2='DVLSTEP', sq='BT', cd='CNTGT1', nxt='DIVL20_L')
U(sq='BT', c2='DVOVL2', nxt='DIVL20_OV')
U(alu=('DVLR', 'ZERO', 'ZERO', 'NONE', 'LONG'), xe='RCH')
U(b=('NPF',), alu=('DVLQ', 'ZERO', 'ZERO', 'NONE', 'LONG'), xe='RCL', fl=1)
U(sq='FIN')
L('DIVL20_Z')
U(ms='VDIV0', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12_F2')
L('DIVL20_OV')
U(b=('NPF',), alu=('DVLO', 'ZERO', 'ZERO', 'NONE', 'LONG'), fl=1)
U(sq='FIN')

# PACK / UNPK (adjustment = the extension word, kept in IM; no flags). Memory forms: -(Ay) byte reads (PACK: the first
# byte is the low one), -(Ax) byte writes (UNPK: low byte first). The one-byte side (PACK -(Ax), UNPK -(Ay)) moves A7
# by 2; the two-byte side (PACK -(Ay), UNPK -(Ax)) moves any An by 2 in total, A7 too (2026-11-16: WinUAE gencpu.cpp
# i_PACK / i_UNPK - one word at An - 2; Amiberry run T4b / T4c; was 2 per byte for A7, as Musashi). m68ksv keeps its two
# byte accesses (at An - 1, then An - 2), addressed through AT so the A7 byte rule does not apply
L('PACK20R')
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM', 'WORD'))
U()
U(b=('NPF',), alu=('PACK', 'DY', 'IM', 'DX', 'BYTE'))
U(sq='FIN')
L('UNPK20R')
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM', 'WORD'))
U()
U(b=('NPF',), alu=('UNPK', 'DY', 'IM', 'DX', 'WORD'))
U(sq='FIN')
L('PACK20M')
U(au=('AY', 'M2', 'AT'))                                                   # AT = Ay - 2
U(au=('AT', 'INC', 'AT', 'BYTE'))                                          # AT = Ay - 1 (one word more than before)
U(b=('RD', 'AT'), bs='BYTE', bd='SHB')                                     # byte at Ay - 1
U(au=('AT', 'DEC', 'AY', 'BYTE'))                                          # Ay = Ay - 2
U(b=('RD', 'AY'), bs='BYTE', bd='SHB')                                     # byte at Ay - 2
U()
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM', 'WORD'))
U(au=('AX', 'DEC', 'AX', 'BYTE'))
U(alu=('PACK', 'DT', 'IM', 'NONE', 'BYTE'))
U(b=('WR', 'AX'), bs='BYTE', dw='RESL')
U()
U(b=('NPF',))
U(sq='FIN')
L('UNPK20M')
U(au=('AY', 'DEC', 'AY', 'BYTE'))
U(b=('RD', 'AY'), bs='BYTE')
U()
U(b=('NPE',), alu=('PASS', 'IRC', 'ZERO', 'IM', 'WORD'))
U(au=('AX', 'M2', 'AT'))                                                   # AT = Ax - 2
U(alu=('UNPK', 'DT', 'IM', 'NONE', 'WORD'), au=('AT', 'INC', 'AT', 'BYTE'))   # AT = Ax - 1
U(b=('WR', 'AT'), bs='BYTE', dw='RESL')                                    # low byte at Ax - 1
U(au=('AT', 'DEC', 'AX', 'BYTE'), alu=('UNPKH', 'DT', 'IM', 'NONE', 'WORD'))  # Ax = Ax - 2
U(b=('WR', 'AX'), bs='BYTE', dw='RESL')                                    # high byte at Ax - 2
U()
U(b=('NPF',))
U(sq='FIN')

# ---------------------------------------------------------------------------------------------------------------
# bit fields (cx = extension word: Dn 14-12, Do 11, offset 10-6 / register 8-6, Dw 5, width 4-0 / register 2-0).
# BFINIT: offset (signed, from Dn or immediate) and width (1-32) into the bit-field unit, the byte address EA + offset / 8
# (memory); BFP: stage 1 of the unit (funnel shift of the data, masks) into registers; BF: the result (field / FFO /
# modified data) with the flags (N = field msb, Z = field 0, V = C = 0; BFINS: of the inserted value); BF5: the modified
# fifth byte (memory, offset % 8 + width > 32). Register form: Dy taken circularly. Memory form: the long at the byte
# address (and the fifth byte) read, written back whole (Musashi writes the same long; unchanged bytes keep their value).
L('BF20R')
U(alu=('NOP', 'RCO', 'RCH', 'NONE', 'LONG'), m2='BFINIT')
U(alu=('BFP', 'RCL', 'DY', 'NONE', 'LONG'), sq='BT', c2='BFMOD', nxt='BF20R_M')
U(sq='BT', c2='BFEXT', nxt='BF20R_X')
U(b=('NPF',), alu=('BF', 'RCL', 'DY', 'NONE', 'LONG'), fl=1)                # BFTST
U(sq='FIN')
L('BF20R_X')
U(b=('NPF',), alu=('BF', 'RCL', 'DY', 'NONE', 'LONG'), xe='RCL', fl=1)      # BFEXTU / BFEXTS / BFFFO -> Dn
U(sq='FIN')
L('BF20R_M')
U(b=('NPF',), alu=('BF', 'RCL', 'DY', 'DY', 'LONG'), fl=1)                  # BFCHG / BFCLR / BFSET / BFINS -> Dy
U(sq='FIN')
L('BF20M')
U(alu=('NOP', 'RCO', 'RCH', 'NONE', 'LONG'), m2='BFINIT')
U(au=('BFA', 'ZERO', 'AT'))                                                # AT = EA + offset / 8
U(b=('RD', 'AT'), bd='HI', bs='WORD', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO', bs='WORD', au=('AT', 'P4', 'NONE'))
U(sq='BF', c2='BF5', nxt='BF20M_1')
U(b=('RD', 'AUR'), bs='BYTE', m2='XP')                                     # fifth byte -> XT[7:0]
U()
L('BF20M_1')
U(alu=('BFP', 'RCL', 'DT', 'NONE', 'LONG'), sq='BT', c2='BFMOD', nxt='BF20M_M')
U(sq='BT', c2='BFEXT', nxt='BF20M_X')
U(b=('NPF',), alu=('BF', 'RCL', 'DT', 'NONE', 'LONG'), fl=1)                # BFTST
U(sq='FIN')
L('BF20M_X')
U(b=('NPF',), alu=('BF', 'RCL', 'DT', 'NONE', 'LONG'), xe='RCL', fl=1)
U(sq='FIN')
L('BF20M_M')
U(alu=('BF', 'RCL', 'DT', 'NONE', 'LONG'), fl=1)
U(b=('WR', 'AT'), dw='RESH', au=('AT', 'P2', 'NONE'))
U()
U(b=('WR', 'AUR'), dw='RESL')
U(sq='BF', c2='BF5', nxt='BF20M_E')
U(alu=('BF5', 'RCL', 'DT', 'NONE', 'LONG'), au=('AT', 'P4', 'NONE'))
U(b=('WR', 'AUR'), bs='BYTE', dw='RESL')
U()
L('BF20M_E')
U(b=('NPF',))
U(sq='FIN')

# CHK2 / CMP2 (cx: register 15-12, CHK2 11): lower bound -> XT, upper bound -> DT, then Musashi's compare (signed when the
# lower bound's sign bit is set, else unsigned; .B / .W against a data register's low part, against all of An): C = out
# of bounds, Z = equal to a bound, N / V unchanged; CHK2 out of bounds -> CHK exception (format 2)
L('CHK220')
U(sq='BT', cd='SZL', nxt='CHK220_L')
U(sq='BT', c2='SZB', nxt='CHK220_B')
U(b=('RD', 'AT'), bs='WORD', m2='XP', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bs='WORD')
U(sq='NXT', nxt='CHK220_C')
L('CHK220_B')
U(b=('RD', 'AT'), bs='BYTE', m2='XP', au=('AT', 'INC', 'NONE', 'BYTE'))
U()
U(b=('RD', 'AUR'), bs='BYTE')
U(sq='NXT', nxt='CHK220_C')
L('CHK220_L')
U(b=('RD', 'AT'), bd='HI', bs='WORD', m2='XP', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO', bs='WORD', m2='XP', au=('AT', 'P4', 'AT'))
U()
U(b=('RD', 'AT'), bd='HI', bs='WORD', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO', bs='WORD')
U(sq='NXT', nxt='CHK220_C')
L('CHK220_C')
U(alu=('CHK2', 'RC', 'ZERO', 'NONE'))                                  # compare (registered: c2_cq / c2_zq)
U(alu=('CHK2', 'RC', 'ZERO', 'NONE'), fl=1)                            # Z / C from the registered compare
U(sq='BT', c2='CHK2X', nxt='CHK220_T')
U(b=('NPF',))
U(sq='FIN')
L('CHK220_T')
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VCHK', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12_F2')

# CAS Dc,Du,<ea> (cx: Du 8-6, Dc 2-0): dest - Dc flags; equal: Du written to <ea>; not equal: Dc <- dest
L('CAS20')
U(sq='BT', cd='SZL', nxt='CAS20_L')
U(b=('RD', 'AT'))
U(sq='NXT', nxt='CAS20_C')
L('CAS20_L')
U(b=('RD', 'AT'), bd='HI', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO')
U()
L('CAS20_C')
U(alu=('CMP', 'RCC', 'DT', 'NONE'), fl=1)
U(sq='BF', c2='ZSET', nxt='CAS20_NE')
U(b=('WR', 'AT'), d2='RUH', au=('AT', 'P2', 'NONE'), sq='BT', cd='SZL', nxt='CAS20_WL')
U()
U(b=('NPF',))
U(sq='FIN')
L('CAS20_WL')
U()
U(b=('WR', 'AUR'), d2='RUL')
U()
U(b=('NPF',))
U(sq='FIN')
L('CAS20_NE')
U(b=('NPF',), alu=('PASS', 'DT', 'ZERO', 'NONE'), xe='RCH')
U(sq='FIN')

# CAS2 Dc1:Dc2,Du1:Du2,(Rn1):(Rn2): extension words -> cx (1) / cx2 (2), swapped with m2 SWCX; ea1 kept in PCX, dest1 in IM
L('CAS220')
U(b=('NPE',), ms='LDCX')
U()
U(b=('NPE',), m2='LDCX2')
U(alu=('PASS', 'RC', 'ZERO', 'AT', 'LONG'))                                # AT = Rn1
U(au=('AT', 'ZERO', 'PCX'), sq='BT', cd='SZL', nxt='CAS220_L1')
U(b=('RD', 'AT'))
U(sq='NXT', nxt='CAS220_1')
L('CAS220_L1')
U(b=('RD', 'AT'), bd='HI', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO')
U()
L('CAS220_1')
U(alu=('PASS', 'DT', 'ZERO', 'IM', 'LONG'), m2='SWCX')                     # IM = dest1; cx = extension 2
U(alu=('PASS', 'RC', 'ZERO', 'AT', 'LONG'))                                # AT = Rn2
U(m2='SWCX', sq='BT', cd='SZL', nxt='CAS220_L2')                           # (cx = extension 1)
U(b=('RD', 'AT'))
U(sq='NXT', nxt='CAS220_2')
L('CAS220_L2')
U(b=('RD', 'AT'), bd='HI', au=('AT', 'P2', 'NONE'))
U()
U(b=('RD', 'AUR'), bd='LO')
U()
L('CAS220_2')
U(alu=('CMP', 'RCC', 'IM', 'NONE'), fl=1)                                  # dest1 - Dc1
U(sq='BF', c2='ZSET', nxt='CAS220_NE', m2='SWCX')                          # (cx = extension 2)
U(alu=('CMP', 'RCC', 'DT', 'NONE'), fl=1)                                  # dest2 - Dc2
U(sq='BF', c2='ZSET', nxt='CAS220_NE2', m2='SWCX')                         # (cx = extension 1)
U(au=('PCX', 'ZERO', 'NONE'))                                              # AUR = ea1
U(b=('WR', 'AUR'), d2='RUH', au=('PCX', 'P2', 'NONE'), sq='BT', cd='SZL', nxt='CAS220_W1L')
U(m2='SWCX')                                                               # (cx = extension 2)
L('CAS220_W2')
U(b=('WR', 'AT'), d2='RUH', au=('AT', 'P2', 'NONE'), sq='BT', cd='SZL', nxt='CAS220_W2L')
U()
U(b=('NPF',))
U(sq='FIN')
L('CAS220_W1L')                                                            # (cx = extension 1)
U()
U(b=('WR', 'AUR'), d2='RUL')
U(m2='SWCX', sq='NXT', nxt='CAS220_W2')                                    # (cx = extension 2)
L('CAS220_W2L')
U()
U(b=('WR', 'AUR'), d2='RUL')
U()
U(b=('NPF',))
U(sq='FIN')
L('CAS220_NE2')                                                            # (cx = extension 1)
U(m2='SWCX')
L('CAS220_NE')                                                             # (cx = extension 2): Dc1 <- dest1, Dc2 <- dest2
U(m2='SWCX')
U(alu=('PASS', 'IM', 'ZERO', 'NONE'), xe='RCH', m2='SWCX')                 # Dc1 (cx = extension 1)
U(b=('NPF',), alu=('PASS', 'DT', 'ZERO', 'NONE'), xe='RCH')                # Dc2 (cx = extension 2)
U(sq='FIN')

# ---------------------------------------------------------------------------------------------------------------
# RTE (68020): SR, PC, format word. Format 0 (8 bytes), 2 (12), 9 (20), A (32), B (92): SR and PC restored, the frame
# removed (formats 9 / A / B are returned from at the stacked PC - no coprocessor state, no re-run: Musashi's handling of
# A / B; Musashi takes a format error on 9); format 1 (throwaway): SP + 8, SR from the frame (which selects the next
# stack by S / M), then the next frame is processed; any other format: format error (vector 14), the stack unchanged.
L('RTE20')
U(b=('RD', 'SP'), bd='LO', bs='WORD', au=('SP', 'P2', 'AT'), fx='LSR')    # SR (also kept for the format-B tail: x1 SRF)
U()
U(b=('RD', 'AT'), bd='HI', bs='WORD', au=('AT', 'P2', 'AT'), alu=('PASS', 'DT', 'ZERO', 'IM', 'WORD'))     # IM = SR
U()
U(b=('RD', 'AT'), bd='LO', bs='WORD', au=('AT', 'P2', 'AT'))                                              # DT = PC
U()
U(b=('RD', 'AT'), bd='LO', bs='WORD', alu=('PASS', 'DT', 'ZERO', 'PCX', 'LONG'))                # format word
U()
U(m2='LDCNTF', sq='BT', cd='FMT0', nxt='RTE20_SK')                         # cnt = longs after the first 8 bytes
U(sq='BT', c2='FMT1', nxt='RTE20_F1')
U(sq='BT', c2='FMT2', nxt='RTE20_SK')
U(sq='BT', c2='FMT9', nxt='RTE20_SK')
U(sq='BT', c2='FMTA', nxt='RTE20_SK')
U(sq='BT', c2='FMTB', nxt='RTE20_SK')
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VFMT', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12')
L('RTE20_SK')                                                              # AT = frame + 6
U(au=('AT', 'P2', 'AT'), sq='BF', cd='CNTNZ', nxt='RTE20_SE')
L('RTE20_SL')
U(au=('AT', 'P4', 'AT'), ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='RTE20_SL')
L('RTE20_SE')
U(alu=('PASS', 'PCX', 'ZERO', 'DT', 'LONG'), au=('AT', 'ZERO', 'SP'))      # SP = end of the frame
U(alu=('PASS', 'IM', 'ZERO', 'SR', 'WORD'), sq='NXT', nxt='JMPDT')
L('RTE20_F1')
U(au=('AT', 'P2', 'SP'))                                                   # the throwaway frame removed
U(alu=('PASS', 'IM', 'ZERO', 'SR', 'WORD'))                                # its SR: S / M choose the next stack
U(sq='NXT', nxt='RTE20')

# interrupt with M set: after the format-0 frame on the master stack, M is cleared and a format-1 throwaway frame (the
# same PC and vector, SR with S set) goes on the interrupt stack (PRM; Musashi m68ki_exception_interrupt)
_i = LABELS['EXC_INT_010']
while CODE[_i].get('nxt') != 'VECTAIL': _i += 1
CODE[_i]['nxt'] = 'EXC_INT20_T'
L('EXC_INT20_T')
U(sq='BF', c2='MSET', nxt='VECTAIL')
U(m2='CLRM')                                                               # A7 = ISP
U(au=('SSP', 'M2', 'AT'))
U(b=('WR', 'AT'), d2='F1', bs='WORD', au=('AT', 'M2', 'AT'))               # format 1 / vector offset at ISP - 2
U()
U(b=('WR', 'AT'), dw='PCXL', bs='WORD', au=('AT', 'M4', 'AT'))             # PC low at ISP - 4
U()
U(b=('WR', 'AT'), d2='SRTS', bs='WORD', au=('AT', 'P2', 'AT'))             # SR | S at ISP - 8
U(au=('AT', 'M2', 'SP'))
U(b=('WR', 'AT'), dw='PCXH', bs='WORD')                                    # PC high at ISP - 6
U(sq='NXT', nxt='VECTAIL')

# ---------------------------------------------------------------------------------------------------------------
# bus / address error (68020): format B, 46 words, pushed downwards from SSP - 2 on the ISP or MSP. The fault capture,
# the internal state and the continuation are the 68010's (m68ksv_ucode010.py EXC0_010 / RTE10_F8, m68ksv_eu), in the
# format-B slots (m68ksv's own internal layout; the architected fields where the PRM puts them):
#  +00 SR  +02 PC (prefetch address - 4, as the 68010)  +06 $B000 | vector offset  +08 internal: m68ksv SSW (68010 layout)
#  +0A SSW (68020: FB / RB = instruction fetch, DF, RM, RW, SIZ, FC)  +0C stage C: IRC  +0E stage B: 0
#  +10 fault address  +14 0  +18 data output buffer  +1C..+2A 0  +2C data input buffer  +30..+34 0
#  (2026-11-16, address-error frame: SSW = RB | RC (MC68020 UM 6.2.1, #unverified - WinUAE writes no RB / RC) | RW | SIZE
#  word | FC; WinUAE's data input buffer = the fault address and a JMP's stacked PC = its address + 2 - m68ksv_eu
#  DWX_SSW20 / FX_DIB / M2_AEPC)
#  +36 version / internal: {fin, stage, version 0 (13-10), layouts, read destination, trace, held X V C}
#  +38..+3C 0  +3E resume address etc.  +40 IR  +42 PCX  +46 slot A  +4A slot B  +4E AUR  +52 IRN  +54 DT  +58 AT
# RTE: the version (+36) and the last word (+5A) read first (a fault there is a bus error of the RTE), then the frame
# loaded, the faulted cycle re-run unless the handler cleared DF / RB / RC (software completion: DIB / IIB) and the
# instruction continued. Any fault during the push is a double fault (halt).
patch20('EXC0', 0, ms='NONE', sq='NXT', nxt='EXC0_020')
L('EXC0_020')
_w = lambda dw, fx=None, au=('AT', 'M2', 'AT'), **kw: (U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw=dw, au=au,
                                                         **(dict(fx=fx) if fx else {}), **kw), U())
_z = lambda au=('AT', 'M2', 'AT'): _w('X10', au=au)                       # a zero word
U(au=('SSP', 'M4', 'NONE'))
U(b=('WR', 'AUR'), bf='SUPD', bs='WORD', dw='ATH', au=('SSP', 'M2', 'NONE'))   # +58
U()
U(b=('WR', 'AUR'), bf='SUPD', bs='WORD', dw='ATL', au=('SSP', 'M4', 'AT'))  # +5A
U(au=('AT', 'M2', 'AT'))
_w('DTL'); _w('DTH')                                                        # +56 +54
_w('X10', 'IRN')                                                            # +52
_w('X10', 'AURL'); _w('X10', 'AURH')                                        # +50 +4E
_w('X10', 'SLBL'); _w('X10', 'SLBH')                                        # +4C +4A
_w('X10', 'SLAL'); _w('X10', 'SLAH')                                        # +48 +46
_w('PCXL'); _w('PCXH')                                                      # +44 +42
_w('X10', 'IR')                                                             # +40
_w('X10', 'I1')                                                             # +3E
_z(); _z(); _z()                                                            # +3C +3A +38
U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='X10', fx='I0', au=('AT', 'M2', 'AT'))   # +36
U(ms='EXCENT')                                                              # SRT = SR; S = 1, T1 = T0 = 0
_z(); _z(); _z()                                                            # +34 +32 +30
_w('X10', 'DIB'); _w('X10', 'DIBH')                                        # +2E +2C (address error: the fault address)
for _k in range(7): _z()                                                    # +2A .. +1E
_z()                                                                        # +1C
_w('X10', 'DOB'); _z()                                                      # +1A +18
_z(); _z()                                                                  # +16 +14
_w('FAL'); _w('FAH')                                                        # +12 +10
_z()                                                                        # +0E stage B
_w('X10', 'IIB')                                                            # +0C stage C (IRC)
_w('X10', 'SSW20')                                                          # +0A
U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='X10', fx='SSW', au=('AT', 'M2', 'AT'), x1='VG0')   # +08
U(alu=('ADD', 'FPC', 'M4', 'PCX', 'LONG'))
U(b=('WR', 'AT'), bf='SUPD', bs='WORD', d2='FB', au=('AT', 'M2', 'AT'), m2='AEPC')    # +06 (JMP address error: PCX)
U()
_w('PCXL'); _w('PCXH')                                                      # +04 +02
U(b=('WR', 'AT'), bf='SUPD', bs='WORD', dw='SRT', au=('AT', 'ZERO', 'SP'))  # +00, SP = frame
U(sq='NXT', nxt='VECTAIL')

L('RTE20_FB')                                                               # AT = frame + 6
for _k in range(12): U(au=('AT', 'P4', 'AT'))                               # AT = frame + 54
U(b=('RD', 'AT'), bf='SUPD', bs='WORD', fx='LI0', au=('AT', 'P4', 'AT'))    # +36 version
U(au=('AT', 'P4', 'AT'))
U(sq='BF', cd='VERSOK', nxt='RTE20_VERR', au=('AT', 'P4', 'AT'))
for _k in range(6): U(au=('AT', 'P4', 'AT'))
U(au=('AT', 'P2', 'AT'))                                                    # AT = frame + 90
U(b=('RD', 'AT'), bf='SUPD', bs='WORD')                                     # +5A accessibility
U()
U(fx='G0ON', au=('SP', 'P4', 'SP'))
U(au=('SP', 'P4', 'SP'))                                                    # SP = frame + 8
_rd20 = lambda fx=None, **kw: U(b=('RD', 'SP'), bf='SUPD', bs='WORD', **(dict(fx=fx) if fx else {}), **kw)
_rd20('LSSW', au=('SP', 'P2', 'SP'))                                        # +08 m68ksv SSW
U(au=('PCX', 'P4', 'FPC'))                                                  # prefetch address = PC + 4
_rd20('LSSW20', au=('SP', 'P2', 'SP')); U()                                 # +0A SSW: re-run or completed
_rd20('LIIB', au=('SP', 'P4', 'SP')); U()                                   # +0C stage C -> IRC
_rd20('LFAH', au=('SP', 'P2', 'SP')); U()                                   # +10 fault address
_rd20('LFAL', au=('SP', 'P4', 'SP')); U()                                   # +12
for _k in range(1): U(au=('SP', 'P2', 'SP'))                                # SP = +18
U(au=('SP', 'P2', 'SP'))                                                    # +1A
_rd20('LDOB', au=('SP', 'P4', 'SP')); U()                                   # +1A data output buffer
for _k in range(4): U(au=('SP', 'P4', 'SP'))                                # SP = +2E
_rd20('LDIB', au=('SP', 'P4', 'SP')); U()                                   # +2E data input buffer
U(au=('SP', 'P4', 'SP'))                                                    # SP = +36
_rd20('LI0', au=('SP', 'P4', 'SP')); U()                                    # +36 version / flags
U(au=('SP', 'P4', 'SP'))                                                    # SP = +3E
_rd20('LI1', au=('SP', 'P2', 'SP')); U()                                    # +3E resume micro-address
_rd20('LIR', au=('SP', 'P2', 'SP')); U()                                    # +40 IR (decoded from now on)
_rd20(bd='HI', au=('SP', 'P2', 'SP')); U()                                  # +42 PCX
_rd20(bd='LO', au=('SP', 'P2', 'SP')); U()                                  # +44
_rd20(bd='HI', au=('SP', 'P2', 'SP'), alu=('PASS', 'DT', 'ZERO', 'PCX', 'LONG')); U()      # +46 slot A
_rd20(bd='LO', au=('SP', 'P2', 'SP')); U()                                  # +48
_rd20('MSLA', bd='HI', au=('SP', 'P2', 'SP')); U(fx='RSTR')                 # +4A slot B; sequencer state from IR
_rd20(bd='LO', au=('SP', 'P2', 'SP')); U()                                  # +4C
_rd20('LAURH', au=('SP', 'P2', 'SP')); U(fx='MSLB')                         # +4E AUR
_rd20('LAURL', au=('SP', 'P2', 'SP')); U()                                  # +50
_rd20('LIRN', au=('SP', 'P2', 'SP')); U()                                   # +52 IRN
_rd20(bd='HI', au=('SP', 'P2', 'SP')); U()                                  # +54 DT
_rd20(bd='LO', au=('SP', 'P2', 'SP')); U()                                  # +56
_rd20('LATH', au=('SP', 'P2', 'SP')); U()                                   # +58 AT
_rd20('LATL', au=('SP', 'P2', 'SP')); U()                                   # +5A; SP = frame + 92
_i = LABELS['RTE10_F8']
while not (CODE[_i].get('cd') == 'RRSET' and CODE[_i].get('fx') == 'G0OFF'): _i += 1
LABELS['RTE10_CONT'] = _i                                                   # the 68010 re-run / resume tail
U(sq='NXT', nxt='RTE10_CONT')
L('RTE20_VERR')                                                             # wrong version: format error, SP unchanged
U(alu=('ADD', 'FPC', 'M2', 'PCX', 'LONG'), ms='VFMT', au=('SSP', 'M2', 'AT'), sq='NXT', nxt='EXC12')
_i = LABELS['RTE20']
while not (CODE[_i].get('c2') == 'FMTB'): _i += 1
CODE[_i]['nxt'] = 'RTE20_FB'
for _i in range(LABELS['EXC0_020'], LABELS['RTE20_FB']):                    # pushes: group-0 slot layouts (68010 ly 3)
    if CODE[_i].get('bus', 'NONE') != 'NONE': CODE[_i]['ly'] = 3

# T0 trace on the taken paths of Bcc / DBcc (the unconditional change-of-flow instructions: decode class bit)
assert CODE[LABELS['BCC_S']].get('nxt') == 'BR_TAKEN'
patch20('BCC_S', 0, nxt='BCC20_T')
L('BCC20_T')
U(m2='FLOW', sq='NXT', nxt='BR_TAKEN')
assert CODE[LABELS['BCC_W'] + 1].get('nxt') == 'BR_TAKEN_1'
patch20('BCC_W', 1, m2='FLOW')
patch20('BCC_L', 1, m2='FLOW')
assert CODE[LABELS['DBCC'] + 2].get('nxt') == 'DB_T2'
patch20('DBCC', 2, m2='FLOW')

# ---------------------------------------------------------------------------------------------------------------
# coprocessor interface (checkpoint 4b; MC68020 User's Manual section 10 from memory, #unverified where noted in REPORT.md).
# CPU-space cycles (FC 7, A19-16 = 2, Cp-ID on A15-13, the interface register on A4-0; m68ksv_eu BA_CPS): cpGEN writes the
# command word (the first extension word) to the command register ($0A), cpScc / cpDBcc / cpTRAPcc and cpBcc the condition
# (extension word / opcode bits 5-0) to the condition register ($0E), cpRESTORE a format word to the restore register
# ($06); cpSAVE reads the save register ($04) first. A bus error on that first access (no coprocessor) is the F-line
# exception (m68ksv_eu: a bus error on a CPU-space coprocessor cycle enters EXC_LF; format 0, PC = the instruction).
# cpGEN then reads the response register ($00): null (function 01000, CA clear) ends the instruction; null with CA set
# or busy (function 00100) reads it again; any other primitive, and an answering coprocessor on the other types, is
# not implemented: coprocessor protocol violation (vector 13, format 0, PC = the instruction).
L('LINEF20')
U(sq='BT', c2='CPRD', nxt='LINEF20_S')
U(b=('WR', 'CPS'), bf='CPU', bs='WORD', d2='CPW')
U()
U(sq='BF', c2='CPGEN', nxt='EXC_CPV')
L('LINEF20_R')
U(b=('RD', 'CPS'), bf='CPU', bs='WORD')                                    # response -> DT
U()
U(sq='BT', c2='CPAGAIN', nxt='LINEF20_R')
U(sq='BF', c2='CPNULL', nxt='EXC_CPV')
U(b=('NPE',))                                                              # null: the command word is consumed
U()
U(b=('NPF',))
U(sq='FIN')
L('LINEF20_S')
U(b=('RD', 'CPS'), bf='CPU', bs='WORD')                                    # save register
U()
U(sq='NXT', nxt='EXC_CPV')
exc_entry('EXC_CPV', 'VCPV', 'M4')
UA20_EXPORT.append('EXC_LF')

# ---------------------------------------------------------------------------------------------------------------
# RESET (checkpoint 4b): the 68020 asserts RESET for 512 clocks (User's Manual, from memory: #unverified; Musashi's
# m68020 counts 518 for the instruction). With one micro-cycle per clock the 68010 loop (RSTO1, LDCNTRST = 60, CNTDEC
# while > 1, RSTO0) is stretched to eight words per count plus padding: RSTO1 .. RSTO0 = 512 micro-cycles
assert CODE[LABELS['RESETI'] + 1].get('ms') == 'LDCNTRST' and CODE[LABELS['RESETI'] + 1].get('nxt') == 'RESETI_L'
patch20('RESETI', 1, nxt='RESETI20_L')
L('RESETI20_L')
for _i in range(7):
    U()
U(ms='CNTDEC', sq='BT', cd='CNTGT1', nxt='RESETI20_L')
for _i in range(30):
    U()
U(sq='NXT', nxt=at('RESETI_L', 1, 'RESETI20_E'))

# ---------------------------------------------------------------------------------------------------------------
# CAS / CAS2 locked sequence (checkpoint 4b): RMC from the first operand read (m2 RMCON on the reads at AT) to the end of
# the last write, or of the last read when the compare fails (m2 RMCOFF on the final prefetch, which starts after the
# sequence's last cycle); no bus grant in between (m68ksv_biu32). The 68020's behaviour for a failed compare (RMC
# released after the reads, no write) is from memory (#unverified).
def _rmc_region(lo, hi):
    for _i in range(lo, hi):
        _w = CODE[_i]
        if _w.get('bus') == 'RD' and _w.get('ba') == 'AT':
            assert _w.get('m2', 'NONE') == 'NONE'
            _w['m2'] = 'RMCON'
        if _w.get('bus') == 'NPF':
            assert _w.get('m2', 'NONE') == 'NONE'
            _w['m2'] = 'RMCOFF'
_e = LABELS['CAS220_NE'] + 1
while CODE[_e].get('sq') != 'FIN':
    _e += 1
_rmc_region(LABELS['CAS20'], LABELS['CAS220'])
_rmc_region(LABELS['CAS220'], _e + 1)
