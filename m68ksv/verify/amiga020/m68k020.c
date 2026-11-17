/* m68k020.c - m68ksv 68020 / 68EC020 behaviour tests: prints and logs the records filled by m68k020_a.a
 * Copyright (C) 2026 Rodimus
 *
 * SAS/C 6.58, Kickstart 2.0 or later, 68020 / 68EC020 only (no 68030 / 68040 / 68060), no FPU wanted (test T5).
 * Usage: m68k020 [label]     e.g.  m68k020 "A1200 68EC020 KS3.1 Amiberry cycle-exact, no FPU"
 * Output: the screen and the file m68k020.log in the current directory (appended).
 */
#include <exec/types.h>
#include <exec/execbase.h>
#include <stdio.h>
#include <stdarg.h>

extern struct ExecBase *SysBase;
extern void RunTests(void);
extern UBYTE *GetResults(void);
extern ULONG *GetInfo(void);

#define R_SIZE 160
#define NDIVU 8
#define NDIVS 8
#define NCHKW 10
#define NCHKL 6

static FILE *logfp;

static void out(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
    if (logfp) { va_start(ap, fmt); vfprintf(logfp, fmt, ap); va_end(ap); }
}

static ULONG L(UBYTE *p) { return ((ULONG)p[0] << 24) | ((ULONG)p[1] << 16) | ((ULONG)p[2] << 8) | p[3]; }
static UWORD W(UBYTE *p) { return (UWORD)(((UWORD)p[0] << 8) | p[1]); }

static UBYTE *rec;                                         /* current record */
static ULONG which(void)      { return L(rec + 0); }
static UWORD fw(int i)        { return W(rec + 4 + 2 * i); }
static ULONG flong(int i)     { return L(rec + 4 + 4 * i); }   /* log mode: stacked PCs */
static ULONG reg(int i)       { return L(rec + 52 + 4 * i); }  /* 0-7 = D0-D7, 8-14 = A0-A6 */
static UWORD srafter(void)    { return W(rec + 112); }
static UBYTE mem(int i)       { return rec[116 + i]; }
static ULONG aux(void)        { return L(rec + 148); }
static ULONG a1(void)         { return L(rec + 152); }
static ULONG a2(void)         { return L(rec + 156); }

static ULONG *info;                                        /* h_any, VBR, CACR, flagout, pbuf, lbuf, fbuf, bbuf */

static void nzvc(UWORD sr) { out("X%d N%d Z%d V%d C%d", (sr >> 4) & 1, (sr >> 3) & 1, (sr >> 2) & 1, (sr >> 1) & 1, sr & 1); }

static void regs(void)
{
    int i;
    out("  ");
    for (i = 0; i < 15; i++) {
        out(" %c%d=%08lx", i < 8 ? 'D' : 'A', i & 7, reg(i));
        if (i == 7) out("\n  ");
    }
    out("\n");
}

static void frame(void)
{
    int i;
    out("   frame (24 words):");
    for (i = 0; i < 24; i++) { if (i % 12 == 0) out("\n     "); out(" %04x", fw(i)); }
    out("\n   SR %04x PC %08lx format %x vector offset %03x\n", fw(0), ((ULONG)fw(1) << 16) | fw(2), fw(3) >> 12, fw(3) & 0xfff);
}

static void head(int n, const char *title)
{
    rec = GetResults() + n * R_SIZE;
    out("\n%s\n", title);
    if (which()) out("   exception: vector %lu\n", which());
    else { out("   no exception; SR after %04x (", srafter()); nzvc(srafter()); out(")\n"); }
}

static void flagtab(const char *name, UBYTE *o, ULONG *tab, int n)
{
    /* tab: the asm tables are not visible from C, so the inputs are repeated here (keep in step with m68k020_a.a) */
    int i;
    out("\n%s   (inputs D0 / D1 / CCR in -> D0 after, vector, flags)\n", name);
    for (i = 0; i < n; i++) {
        out("   %08lx / %08lx / %02lx -> %08lx  vec %2d  ", tab[3 * i], tab[3 * i + 1], tab[3 * i + 2], L(o + 8 * i), o[8 * i + 4]);
        nzvc(o[8 * i + 5]);
        out("\n");
    }
}

static ULONG divu_in[NDIVU * 3] = {
    0x00010000, 1, 0x00,  0x00010000, 1, 0x1F,  0xFFFFFFFF, 1, 0x00,  0xFFFFFFFF, 1, 0x1F,
    0x80000000, 1, 0x00,  0x7FFF0000, 2, 0x00,  0xFFFF0000, 0xFFFF, 0x00,  0x12345678, 0x100, 0x00 };
static ULONG divs_in[NDIVS * 3] = {
    0x00010000, 1, 0x00,  0x00010000, 1, 0x1F,  0xFFFF0000, 1, 0x00,  0x80000000, 0xFFFF, 0x00,
    0x80000000, 1, 0x1F,  0x00008000, 1, 0x00,  0xFFFF7FFF, 1, 0x00,  0x12345678, 0x100, 0x00 };
static ULONG chkw_in[NCHKW * 3] = {
    5, 10, 0x00,  5, 10, 0x1F,  0, 10, 0x1F,  10, 10, 0x00,  0xFFFF, 10, 0x00,
    11, 10, 0x00,  0x8000, 10, 0x1F,  5, 0xFFFF, 0x00,  0xFFFE, 0xFFFF, 0x00,  0, 0, 0x1F };
static ULONG chkl_in[NCHKL * 3] = {
    5, 10, 0x00,  0xFFFFFFFF, 10, 0x00,  11, 10, 0x1F,  0x80000000, 10, 0x00,  0, 0, 0x1F,  0x7FFFFFFF, 0x7FFFFFFF, 0x00 };

static const char *pcname(ULONG pc, ULONG ins, ULONG nxt)
{
    if (pc == info[0]) return "handler entry";
    if (pc == ins) return "the traced instruction";
    if (pc == nxt) return "the next instruction";
    if (pc == nxt + 4) return "after the MOVE to SR";
    return "other";
}

static void tracelog(void)
{
    ULONG i, n = aux();
    out("   log (%lu entries):\n", n);
    for (i = 0; i < n && i < 6; i++)
        out("     vector %2d  stacked PC %08lx = %s\n", mem((int)i), flong((int)i), pcname(flong((int)i), a1(), a2()));
}

static void packshow(void)
{
    int i;
    ULONG pb = info[4];
    out("   A0 %08lx (start pbuf+16, delta %ld)  A7 after %08lx (start pbuf+32, delta %ld)\n",
        reg(8), (long)(reg(8) - (pb + 16)), reg(13), (long)(reg(13) - (pb + 32)));
    out("   pbuf+8..+39:");
    for (i = 0; i < 32; i++) { if (i % 16 == 0) out("\n     +%02d:", i + 8); out(" %02x", mem(i)); }
    out("\n   (before: all EE except +14 = 12, +15 = 34, +29 = 56, +30 = 78, +31 = 9A)\n");
}

int main(int argc, char **argv)
{
    UBYTE *o;
    UWORD attn = SysBase->AttnFlags;
    ULONG d1, d2;
    int i, ok;

    logfp = fopen("m68k020.log", "a");
    out("m68ksv 68020 test  label: %s\n", argc > 1 ? argv[1] : "(none given)");
    out("Kickstart exec V%d.%d  AttnFlags %04x\n", SysBase->LibNode.lib_Version, SysBase->SoftVer, attn);
    if (!logfp) out("NOTE: could not open m68k020.log for writing (write-protected?) - screen only\n");
    if (!(attn & 0x0002) || (attn & 0x000C)) {   /* AFF_68020 required; AFF_68030 / AFF_68040 refused */
        out("This is not a 68020 / 68EC020 (AttnFlags). The tests need exactly a 68020. Stopping.\n");
        if (logfp) fclose(logfp);
        return 10;
    }
    if (attn & 0x0030) out("NOTE: an FPU is reported (AFF_68881 / 68882): test T5 needs no FPU and will not mean much.\n");

    RunTests();
    info = GetInfo();
    out("VBR %08lx  CACR at entry %08lx  handler %08lx\n", info[1], info[2], info[0]);

    /* T1: flag tables */
    rec = GetResults() + 24 * R_SIZE;
    out("\nT1  undefined / overflow flags (raw; compared against m68ksv and Musashi afterwards)\n");
    if (which()) { out("   ABORTED by vector %lu\n", which()); frame(); }
    o = (UBYTE *)info[3];
    flagtab("DIVU.W D1,D0", o, divu_in, NDIVU);          o += 8 * NDIVU;
    flagtab("DIVS.W D1,D0", o, divs_in, NDIVS);          o += 8 * NDIVS;
    flagtab("CHK.W D1,D0 (vec 6 = trapped)", o, chkw_in, NCHKW); o += 8 * NCHKW;
    flagtab("CHK.L D1,D0 (vec 6 = trapped)", o, chkl_in, NCHKL);

    /* T2: DIV.L overflow C */
    for (i = 0; i < 3; i++) {
        static const char *t[3] = { "T2a DIVU.L D1,D2:D0 overflow (D2:D0 = 2:0, D1 = 1), CCR = 00 before",
                                    "T2b DIVU.L D1,D2:D0 overflow, CCR = 1F before",
                                    "T2c DIVS.L D1,D2:D0 overflow, CCR = 1F before" };
        head(i, t[i]);
        regs();
        if (!which()) {
            UWORD sr = (UWORD)reg(3);
            out("   flags right after: "); nzvc(sr); out("   D2:D0 = %08lx:%08lx (unchanged = 00000002:00000000)\n", reg(2), reg(0));
            if (i == 0) out("   RESULT: V = %d C = %d (control: C was 0 before)\n", (sr >> 1) & 1, sr & 1);
            else out("   RESULT: V = %d, C = %d  -> %s\n", (sr >> 1) & 1, sr & 1,
                     (sr & 1) ? "C kept (Musashi)" : "C cleared (Programmer's Reference Manual / m68ksv)");
        }
    }

    /* T3: trace after a trap-type exception */
    head(3, "T3a TRAP #0 with T1 set: is a trace exception taken before the TRAP handler runs?");
    if (!which()) tracelog(); else frame();
    rec = GetResults() + 3 * R_SIZE;
    if (!which()) out("   RESULT: %s\n", (aux() >= 1 && mem(0) == 9 && flong(0) == info[0]) ? "trace first, PC = handler (manual / m68ksv)" :
                                       (aux() >= 1 && mem(0) == 32) ? "TRAP first, no trace before the handler (Musashi)" : "other (see log)");
    head(4, "T3b DIVU.W by zero with T1 set: the same question");
    if (!which()) tracelog(); else frame();
    rec = GetResults() + 4 * R_SIZE;
    if (!which()) out("   RESULT: %s\n", (aux() >= 1 && mem(0) == 9 && flong(0) == info[0]) ? "trace first, PC = handler (manual / m68ksv)" :
                                       (aux() >= 1 && mem(0) == 5) ? "zero divide first, no trace before the handler (Musashi)" : "other (see log)");

    /* T4: PACK / UNPK with -(A7) */
    head(5, "T4a PACK -(A0),-(A7),#0");       if (which()) frame(); else packshow();
    head(6, "T4b PACK -(A7),-(A0),#0");       if (which()) frame(); else packshow();
    head(7, "T4c UNPK -(A0),-(A7),#$3030");   if (which()) frame(); else packshow();
    head(8, "T4d UNPK -(A7),-(A0),#$3030");   if (which()) frame(); else packshow();
    out("   RESULT (T4a-d): raw; the A7 steps and bytes are compared against m68ksv and Musashi afterwards\n");

    /* T5: FSAVE with no FPU */
    head(9, "T5a FSAVE -(A7) in user mode, no FPU: privilege violation (8) or F-line (11)?");
    if (which()) frame();
    out("   RESULT: %s\n", which() == 8 ? "privilege violation (manual / m68ksv)" : which() == 11 ? "F-line (Musashi)" :
                        (which() == 4 && reg(7) == 0x55) ? "FSAVE did not trap (FPU present?)" : "other");
    head(10, "T5b (control) FSAVE -(A7) in supervisor mode, no FPU: F-line (11) expected");
    if (which()) frame();
    out("   RESULT: %s\n", which() == 11 ? "F-line (as expected)" : (!which() && reg(7) == 0x55) ? "no exception (FPU present?)" : "other");

    /* T6: RTE of hand-built frames */
    {
        static const int n[3] = { 11, 13, 12 };
        static const char *t[3] = { "T6a RTE of a format-7 frame: format error (14)?",
                                    "T6c (control) RTE of a format-0 frame",
                                    "T6b RTE of a format-9 frame (run last)" };
        for (i = 0; i < 3; i++) {
            head(n[i], t[i]);
            if (which()) { frame(); out("   (RTE at %08lx)\n", a1()); }
            else if (reg(7) == 0x55) out("   frame accepted: %ld bytes popped (A5 %08lx -> A4 %08lx)\n", (long)(reg(12) - reg(13)), reg(13), reg(12));
            if (i == 0) out("   RESULT: %s\n", which() == 14 ? "format error (manual / m68ksv)" :
                                (!which() && reg(7) == 0x55) ? "accepted (Musashi pops a 68040 frame: 60 bytes)" : "other");
            if (i == 1) out("   RESULT: %s\n", (!which() && reg(7) == 0x55 && reg(12) - reg(13) == 8) ? "accepted, 8 bytes (as expected)" : "UNEXPECTED");
            if (i == 2) out("   RESULT: %s\n", (!which() && reg(7) == 0x55 && reg(12) - reg(13) == 20) ? "accepted, 20 bytes popped (m68ksv)" :
                                which() == 14 ? "format error (Musashi)" : "other (see above)");
        }
    }

    /* T7: odd JMP target */
    head(14, "T7  JMP to an odd address: address error frame");
    if (which() == 3) {
        frame();
        out("   SSW %04x  fault address %08lx  (target was %08lx + 1)\n", fw(5), ((ULONG)fw(8) << 16) | fw(9), a2());
        out("   RESULT: format %x (m68ksv: format B; Musashi: a mostly empty frame); words compared afterwards\n", fw(3) >> 12);
    } else out("   RESULT: unexpected (no address error)\n");

    /* T8: cache */
    head(15, "T8a (control) cache: two cached subroutines patched to return 2, no clearing");
    d1 = reg(1); d2 = reg(2);
    out("   results %ld / %ld  ->  %s\n", d1, d2, (d1 == 1 && d2 == 1) ? "stale: the instruction cache is modelled" :
                                          (d1 == 2 && d2 == 2) ? "fresh: the cache is NOT modelled (T8b means nothing)" : "other");
    head(16, "T8b CACR CE with CAAR = the first subroutine: one entry or the whole cache cleared?");
    d1 = reg(1); d2 = reg(2);
    out("   RESULT: %ld / %ld  ->  %s\n", d1, d2, (d1 == 2 && d2 == 1) ? "one entry (manual / m68ksv)" :
                                          (d1 == 2 && d2 == 2) ? "whole cache (Musashi) - or no cache, see T8a" : "other");

    /* T9: bit fields */
    head(17, "T9a BFEXTU D1{0:0},D0 (width 0 = 32), D1 = 12345678");
    out("   RESULT: D0 = %08lx (expected 12345678, N0 Z0)  %s\n", reg(0), reg(0) == 0x12345678 && !(srafter() & 0x0c) ? "ok" : "DIFFERENT");
    head(18, "T9b BFEXTS (A0){D2:12},D0, A0 = bbuf+2, D2 = -4, bbuf = 11 28 33 44 ...");
    out("   RESULT: D0 = %08lx (expected FFFFF833, N1)  %s\n", reg(0), reg(0) == 0xFFFFF833 && (srafter() & 8) ? "ok" : "DIFFERENT");
    head(19, "T9c BFINS D1,(A0){7:32}, A0 = cbuf+1, D1 = A5C3E187, cbuf all 00");
    out("   cbuf: "); for (i = 8; i < 16; i++) out(" %02x", mem(i));
    ok = mem(8) == 0 && mem(9) == 1 && mem(10) == 0x4b && mem(11) == 0x87 && mem(12) == 0xc3 && mem(13) == 0x0e && mem(14) == 0;
    out("\n   RESULT: expected 00 01 4b 87 c3 0e 00 00, N1  %s\n", ok && (srafter() & 8) ? "ok" : "DIFFERENT");
    head(20, "T9d BFFFO D1{4:8},D0, D1 = 0");
    out("   RESULT: D0 = %ld (expected 12, Z1)  %s\n", reg(0), reg(0) == 12 && (srafter() & 4) ? "ok" : "DIFFERENT");
    head(21, "T9e BFFFO D1{4:8},D0, D1 = 00800000");
    out("   RESULT: D0 = %ld (expected 8, N0 Z0)  %s\n", reg(0), reg(0) == 8 && !(srafter() & 0x0c) ? "ok" : "DIFFERENT");

    /* T10: LINK A7 */
    head(22, "T10 LINK A7,#-8 with A7 = lbuf+32");
    {
        ULONG lb = info[5], pushed = L(rec + 116 + 28);
        out("   long pushed at lbuf+28: %08lx  A7 after: lbuf+%ld\n", pushed, (long)(reg(13) - lb));
        out("   RESULT: pushed %s, A7 after lbuf+%ld (m68ksv / Musashi: lbuf+28, A7 lbuf+20)\n",
            pushed == lb + 28 ? "lbuf+28 (A7 after the push's decrement)" : pushed == lb + 32 ? "lbuf+32 (A7 before)" : "other",
            (long)(reg(13) - lb));
    }

    out("\ndone.\n\n");
    if (logfp) fclose(logfp);
    return 0;
}
