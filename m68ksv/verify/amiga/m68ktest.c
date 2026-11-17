/* m68ktest.c - m68ksv real-68000 test cases: prints and logs the records filled by m68ktest_a.a
 * Copyright (C) 2026 Rodimus
 *
 * SAS/C 6.58, Kickstart 1.3 or later, plain 68000 only.
 * Usage: m68ktest [label]     e.g.  m68ktest "A2000 KS1.3 Amiberry cycle-exact"
 * Output: the screen and the file m68ktest.log in the current directory (appended).
 */
#include <exec/types.h>
#include <exec/execbase.h>
#include <stdio.h>
#include <stdarg.h>

extern struct ExecBase *SysBase;
extern void RunTests(void);
extern UBYTE *GetResults(void);

#define R_SIZE 96
static FILE *logfp;

static void out(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
    if (logfp) { va_start(ap, fmt); vfprintf(logfp, fmt, ap); va_end(ap); }
}

static ULONG L(UBYTE *p) { return ((ULONG)p[0] << 24) | ((ULONG)p[1] << 16) | ((ULONG)p[2] << 8) | p[3]; }
static UWORD W(UBYTE *p) { return (UWORD)(((UWORD)p[0] << 8) | p[1]); }

/* record fields */
static ULONG which(UBYTE *r)        { return L(r + 0); }
static UWORD fw(UBYTE *r, int i)    { return W(r + 4 + 2 * i); }
static ULONG reg(UBYTE *r, int i)   { return L(r + 20 + 4 * i); }   /* 0-7 = D0-D7, 8-14 = A0-A6 */
static UWORD srafter(UBYTE *r)      { return W(r + 80); }
static ULONG ins(UBYTE *r)          { return L(r + 84); }
static ULONG nxt(UBYTE *r)          { return L(r + 88); }
static ULONG bufa(UBYTE *r)         { return L(r + 92); }

static void dump(UBYTE *r)
{
    int i;
    out("   vector %lu", which(r));
    if (which(r) == 3)
        out("  frame: access %04x (R/W %d I/N %d FC %d) addr %08lx IR %04x SR %04x PC %08lx\n",
            fw(r, 0), (fw(r, 0) >> 4) & 1, (fw(r, 0) >> 3) & 1, fw(r, 0) & 7,
            ((ULONG)fw(r, 1) << 16) | fw(r, 2), fw(r, 3), fw(r, 4), ((ULONG)fw(r, 5) << 16) | fw(r, 6));
    else if (which(r) != 0)
        out("  frame: SR %04x PC %08lx\n", fw(r, 0), ((ULONG)fw(r, 1) << 16) | fw(r, 2));
    else
        out("  (no exception)  SR after %04x\n", srafter(r));
    out("   instr %08lx next %08lx buf %08lx\n  ", ins(r), nxt(r), bufa(r));
    for (i = 0; i < 15; i++) {
        out(" %c%d=%08lx", i < 8 ? 'D' : 'A', i & 7, reg(r, i));
        if (i == 7) out("\n  ");
    }
    out("\n");
}

static const char *pc_is(UBYTE *r, ULONG pc)
{
    if (pc == ins(r)) return "the instruction itself";
    if (pc == nxt(r)) return "the next instruction";
    return "neither";
}

int main(int argc, char **argv)
{
    UBYTE *res, *r;
    UWORD sr, attn = SysBase->AttnFlags;
    ULONG pc;

    logfp = fopen("m68ktest.log", "a");
    out("m68ksv 68000 test  label: %s\n", argc > 1 ? argv[1] : "(none given)");
    out("Kickstart exec V%d.%d  AttnFlags %04x\n",
        SysBase->LibNode.lib_Version, SysBase->SoftVer, attn);
    if (!logfp) out("NOTE: could not open m68ktest.log for writing (write-protected?) - screen only\n");
    if (attn & (AFF_68010 | AFF_68020)) {
        out("This is not a plain 68000 (68010 or later reported). The tests need a 68000. Stopping.\n");
        if (logfp) fclose(logfp);
        return 10;
    }

    RunTests();
    res = GetResults();

    r = res + 0 * R_SIZE;
    out("\nT1  MOVE.W (A0)+,D0 with A0 = buf+1 (odd)\n"); dump(r);
    if (which(r) != 3) out("   RESULT: unexpected (no address error)\n");
    else if (reg(r, 8) == bufa(r) + 1) out("   RESULT: A0 NOT incremented  -> fx68k / m68ksv\n");
    else if (reg(r, 8) == bufa(r) + 3) out("   RESULT: A0 incremented      -> suite / MAME\n");
    else out("   RESULT: A0 = %08lx, matches no prediction\n", reg(r, 8));

    r = res + 1 * R_SIZE;
    out("\nT2  MOVE.W D0,-(A1) to buf+1 (odd), ILLEGAL next\n"); dump(r);
    if (which(r) != 3) out("   RESULT: unexpected (no address error)\n");
    else out("   RESULT: I/N = %d  -> %s\n", (fw(r, 0) >> 3) & 1,
             ((fw(r, 0) >> 3) & 1) ? "fx68k / m68ksv" : "MAME / suite");

    r = res + 2 * R_SIZE;
    out("\nT2b control: the same with NOP next (all models: I/N = 0)\n"); dump(r);
    if (which(r) != 3) out("   RESULT: unexpected (no address error)\n");
    else out("   RESULT: I/N = %d  %s\n", (fw(r, 0) >> 3) & 1, ((fw(r, 0) >> 3) & 1) ? "(UNEXPECTED)" : "(as expected)");

    r = res + 3 * R_SIZE;
    out("\nT3  ADDA.L overflow (V = 0), then TRAPV\n"); dump(r);
    if (which(r) == 7) out("   RESULT: TRAPV trapped       -> MAME\n");
    else if (which(r) == 0 && reg(r, 7) == 0x55) out("   RESULT: no trap             -> fx68k / m68ksv\n");
    else out("   RESULT: unexpected\n");

    r = res + 4 * R_SIZE;
    out("\nT3b control: TRAPV with V = 1 (all models: trap)\n"); dump(r);
    out("   RESULT: %s\n", which(r) == 7 ? "trapped (as expected)" : "NO TRAP (UNEXPECTED - handler problem?)");

    r = res + 5 * R_SIZE;
    out("\nT4a DIVU 4(A7),D0 by zero, D0 = $80011234, CCR = 0 before\n"); dump(r);
    if (which(r) != 5) out("   RESULT: unexpected (no zero-divide trap)\n");
    else {
        sr = fw(r, 0); pc = ((ULONG)fw(r, 1) << 16) | fw(r, 2);
        out("   RESULT: stacked PC = %s; N = %d Z = %d V = %d C = %d\n", pc_is(r, pc),
            (sr >> 3) & 1, (sr >> 2) & 1, (sr >> 1) & 1, sr & 1);
        out("   predictions: suite = the instruction, N 0 Z 0; MAME / fx68k / m68ksv = the next instruction, N 1 Z 0\n");
    }

    r = res + 6 * R_SIZE;
    out("\nT4b DIVU 4(A7),D0 by zero, D0 = $00005678, CCR = 0 before\n"); dump(r);
    if (which(r) != 5) out("   RESULT: unexpected (no zero-divide trap)\n");
    else {
        sr = fw(r, 0); pc = ((ULONG)fw(r, 1) << 16) | fw(r, 2);
        out("   RESULT: stacked PC = %s; N = %d Z = %d V = %d C = %d\n", pc_is(r, pc),
            (sr >> 3) & 1, (sr >> 2) & 1, (sr >> 1) & 1, sr & 1);
        out("   predictions: suite = the instruction, N 0 Z 0; MAME / fx68k / m68ksv = the next instruction, N 0 Z 1\n");
    }

    r = res + 7 * R_SIZE;
    out("\nT5  ASR.L #40 (in D1) on D0 = -1, CCR = 0 before\n"); dump(r);
    if (which(r) != 0) out("   RESULT: unexpected exception\n");
    else {
        sr = srafter(r);
        out("   RESULT: X = %d C = %d  -> %s\n", (sr >> 4) & 1, sr & 1,
            ((sr & 0x11) == 0x11) ? "MAME / fx68k / m68ksv" : ((sr & 0x11) == 0 ? "suite" : "no prediction"));
    }

    out("\ndone.\n\n");
    if (logfp) fclose(logfp);
    return 0;
}
