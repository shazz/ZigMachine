#!/usr/bin/env python3
"""Generate the patched benchmark sources the cart compiles, from the pristine ones.

    python3 -I apps/c/bench/kestrel/gen.py <outdir>

The committed sources under apps/c/bench/{dhry,third_party} stay byte-for-byte what was downloaded (their
licences ask for that); every edit the slice scheduler needs is made here, on a copy, and each one asserts it
matched exactly once, so a drifting source fails the build instead of silently measuring something else.
Same approach as the Hatari build's build_all.sh.
"""
import re
import sys
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent
DHRY = BENCH / "dhry"
TP = BENCH / "third_party"


def sub1(text: str, old: str, new: str) -> str:
    n = text.count(old)
    assert n == 1, f"gen.py: expected exactly one {old[:50]!r}, found {n}"
    return text.replace(old, new)


def dhrystone(out: Path) -> None:
    t = (DHRY / "dhry_1.c").read_text()
    # main() becomes a call with the run count (one slice = one call); the scanf asking for it goes.
    t = sub1(t, "main ()\n/*****/", "int dhry_main (nruns)\nint nruns;\n/*****/")
    t = sub1(t, '  {\n    int n;\n    scanf ("%d", &n);\n    Number_Of_Runs = n;\n  }', "  Number_Of_Runs = nruns;")
    (out / "dhry_1.c").write_text(t)
    (out / "dhry_2.c").write_text((DHRY / "dhry_2.c").read_text())


FLOAT_LIT = re.compile(r"(?<![\w.])(\d+\.\d*|\.\d+)([eE][-+]?\d+)?(?![\w.])")
SP_MATH = {"DSIN": "bsinf", "DCOS": "bcosf", "DATAN": "batanf", "DLOG": "blogf", "DEXP": "bexpf", "DSQRT": "sqrtf"}


def single(text: str) -> str:
    """double -> float, f32 libm, and every float literal an `f` literal (so no op is silently f64)."""
    text = re.sub(r"\bdouble\b", "float", text)
    for k, v in SP_MATH.items():
        text = re.sub(rf"(#define\s+{k}\s+)\w+", rf"\g<1>{v}", text)
    lines = []
    for ln in text.split("\n"):
        lines.append(ln if '"' in ln else FLOAT_LIT.sub(lambda m: m.group(0) + "f", ln))
    return "\n".join(lines)


def whetstone(out: Path) -> None:
    t = (TP / "whetstone.c").read_text()
    t = sub1(t, "double T,T1,T2,E1[5];\nint J,K,L;", "static double T,T1,T2,E1[5];\nstatic int J,K,L;\nlong WH_T0, WH_T1;\ndouble WH_CHK;")
    t = sub1(t, "main(int argc, char *argv[])", "WH_MAIN(int argc, char *argv[])")
    t = sub1(t, "\tstartsec = time(0);", "\tstartsec = WH_T0 = time(0);")
    t = sub1(t, "\tfinisec = time(0);", "\tWH_CHK = X1+X2+X3+X4+E1[1]+E1[2]+E1[3]+E1[4]+X+Y+Z;\n\tfinisec = WH_T1 = time(0);")
    for fn in ("PA(double E[])", "P0(void)", "P3(double X, double Y, double *Z)"):
        t = sub1(t, f"void\n{fn}", f"static void\n{fn}")
        t = sub1(t, f"void {fn};", f"static void {fn};")
    for v, text in (("d", t), ("f", single(t))):
        text = text.replace("WH_", f"WH_{v.upper()}_")
        (out / f"whet_{v}.c").write_text(text)


LIN_ENTRY = """
static REAL LN_RESID;
long LN_T_GEFA, LN_T_GESL;
extern unsigned bench_now(void);
extern int bench_break;
void LN_INIT(void *mem) { mempool = mem; }
REAL LN_RESIDUAL(void) { return LN_RESID; }

/* One phase of LINPACK's linpack(): matgen, a timed dgefa and dgesl, rolled or unrolled BLAS, on the 200 x 200
 * array (n = 100) the Hatari build ran. x must come out as all ones; LN_RESID is how far it is. */
void LN_PHASE(int roll)
    {
    int arsize = 200, n = arsize / 2, lda = arsize, info;
    REAL *a = (REAL *)mempool, *b = a + (long)arsize * arsize, norma;
    int *ipvt = (int *)&b[arsize];
    unsigned t;

    matgen(a, lda, n, b, &norma);
    t = bench_now();
    dgefa(a, lda, n, ipvt, &info, roll);
    LN_T_GEFA += (long)(bench_now() - t);
    t = bench_now();
    dgesl(a, lda, n, ipvt, b, 0, roll);
    LN_T_GESL += (long)(bench_now() - t);
    if (bench_break == 2) b[0] += (REAL)0.5;
    LN_RESID = 0;
    for (int i = 0; i < n; i++)
        {
        REAL d = b[i] - ONE;
        LN_RESID = fabs(d) > LN_RESID ? fabs(d) : LN_RESID;
        }
    }
"""


def linpack(out: Path) -> None:
    t = (TP / "linpack.c").read_text()
    m = t.index("void main(void)")
    d = t.index("static REAL linpack(long nreps,int arsize)\n")
    e = t.index("/*\n** For matgen,")
    t = t[:m] + LIN_ENTRY + "\n\n" + t[e:]
    t = sub1(t, "static REAL second(void)\n\n    {\n    return ((REAL)((REAL)clock()/(REAL)CLOCKS_PER_SEC));\n    }",
             "static REAL second(void) { return 0; }")
    assert d > m
    for v, text in (("d", t), ("f", t)):
        if v == "f":
            text = sub1(text, "#define DP\n", "#define SP\n#define fabs fabsf\n")
            text = sub1(text, "#define ZERO        0.0\n", "#define ZERO        0.0f\n")
            text = sub1(text, "#define ONE         1.0\n", "#define ONE         1.0f\n")
        text = text.replace("LN_", f"LN_{v.upper()}_")
        text = re.sub(r"\b(matgen|dgefa|dgesl|daxpy_r|ddot_r|dscal_r|daxpy_ur|ddot_ur|dscal_ur|idamax)\b", r"\1_" + v, text)
        text = text.replace("static void *mempool;", "static void *mempool;\n#ifndef REAL_DEFINED\n#endif")
        (out / f"lin_{v}.c").write_text(text)


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    dhrystone(out)
    whetstone(out)
    linpack(out)


if __name__ == "__main__":
    main()
