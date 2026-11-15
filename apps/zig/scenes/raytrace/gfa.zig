// NUCLEUS's GfA Punch Raytrace (ST Magazine, France: the monthly "GfA Punch" contest of
// 20-line GFA BASIC programs), its maths. The listing, as printed (21 lines):
//
//  1 PRINT SPACE$(1);"NUCLEUS's GfA Punch Raytrace"
//  2 REM ^ Attention, ligne indispensable!
//  3 a$=MKI$(0)+MKI$(&H100)+...+MKI$(&H700)+MKI$(&H710)+MKI$(&H720)+MKI$(&H731)
//      +MKI$(&H741)+MKI$(&H751)+MKI$(&H761)+MKI$(&H771)+MKI$(&H772)
//  4 ~XBIOS(6,L:V:a$)
//  5 FOR y%=-99 TO 53
//  6 FOR x%=-159 TO 159
//  7 IF (300*y%^2-9000*x%-2700000)^2-4*(x%*x%+y%*y%+22500)*(22500*(x%*x%+y%*y%)
//      -1350000*x%+300000)>0
//  8 z=(-(300*y%^2-9000*x%-2700000)-SQR(<line 7's discriminant>))/2/(x%*x%+y%*y%+22500)
//  9 PSET x%+159,99-y%,@c(@a((x%*z)/150+x%-30,(y%*z)/150+y%,-60+z,(x%*z)/150+x%,
//      (y%*z)/150+y%,z,0.15))
// 10 ELSE IF y%<0
// 11 z=-14850/y%-150
// 12 PSET x%+159,99-y%,@c(MAX(0,(PTST(MOD(INT(((x%*z)/150+x%)/2+10000),63),
//      15-MOD(INT(z/2),16))<>0)*0.3+(@b((x%*z)/150+x%,z)>=0)*0.5
//      +@a(0,1,0,(x%*z)/150+x%,-99,z,0.09)))
// 13 ELSE IF y%>0 AND y%<=24
// 14 PSET x%+159,99-y%,@c(1-(MIN(22,y%)/22))
// 15 ENDIF / 16 NEXT x% / 17 NEXT y%
// 18 DEFFN a(a%,b%,c%,d,e,f,am)=MIN(1,am+MAX(0,(a%*(80-d)+b%*(80-e)+c%*(-80-f))
//      /(SQR(a%^2+b%^2+c%^2)*SQR((80-d)^2+(80-e)^2+(-80-f)^2))))
// 19 DEFFN b(x&,z&)=100-SQR(x&^2+(z&-148)^2)
// 20 DEFFN c(v)=MAX(0,DIV(@d(v*159),10)+(RAND(10)>MOD(@d(v*159),10)))
// 21 DEFFN d(v)=INT(v)-(ABS(v-INT(v))>=ABS(v-INT(v+1)))
//
// Line by line: prototypes/gfa_punch/ANALYSIS.md. GFA's rules kept here: TRUE is -1, so
// the text and the shadow SUBTRACT (TRUE below; the harness's `--break true` proves it);
// a float passed to an integer parameter (a%, b%, c%, x&, z&) is ROUNDED; INT is the floor;
// DIV()/MOD() in brackets are integer. RAND is a seeded LCG (GFA's own is unknown) so the
// harness can pin the dither.
//
// FLOAT ON PURPOSE (the no-float rule's exception for an original that needed it): GFA
// BASIC computed this in its 8-byte floats; here it is f32 on ZIGGY's FPU, except line 7's
// test, which is exact in integers (its terms reach 2.3e14: GFA's floats held it exactly,
// f32 would not).
pub const TITLE = " NUCLEUS's GfA Punch Raytrace";
pub const PALETTE = [16]u16{ 0x000, 0x100, 0x200, 0x300, 0x400, 0x500, 0x600, 0x700, 0x710, 0x720, 0x731, 0x741, 0x751, 0x761, 0x771, 0x772 };
pub const TRUE: i32 = -1; // GFA's
pub const SEED: u32 = 0x6fa1991;

const T: f32 = @floatFromInt(TRUE);

fn truth(b: bool) f32 {
    return if (b) T else 0;
}

/// An ST colour word $0RGB -> 8 bits a gun, c * 255 / 7 (as the other ST ports).
pub fn stRgb(w: u16) [3]u8 {
    var o: [3]u8 = undefined;
    inline for (0..3) |i| o[i] = @intCast(@as(u32, (w >> @intCast(8 - 4 * i)) & 7) * 255 / 7);
    return o;
}

/// RAND(n): 0..n-1 from a 32-bit LCG; apps/gfa_punch_lib.mjs has its twin.
pub const Rand = struct {
    s: u32,
    pub fn next(self: *Rand, n: u32) u32 {
        self.s = self.s *% 1664525 +% 1013904223;
        return ((self.s >> 16) * n) >> 16;
    }
};

/// A float passed to an integer parameter: rounded (half away from zero).
fn cint(v: f32) f32 {
    return @round(v);
}

/// FN a: Lambert from a light at (80, 80, -80) on normal (a, b, c) at (d, e, f), plus ambient.
pub fn fnA(a0: f32, b0: f32, c0: f32, d: f32, e: f32, f: f32, am: f32) f32 {
    const a = cint(a0);
    const b = cint(b0);
    const c = cint(c0);
    const lx = 80 - d;
    const ly = 80 - e;
    const lz = -80 - f;
    const dot = a * lx + b * ly + c * lz;
    const den = @sqrt(a * a + b * b + c * c) * @sqrt(lx * lx + ly * ly + lz * lz);
    return @min(1, am + @max(0, dot / den));
}

/// FN b: 100 minus the distance from (0, 148) on the floor: >= 0 inside the shadow disc.
pub fn fnB(x: f32, z: f32) f32 {
    const xi = cint(x);
    const dz = cint(z) - 148;
    return 100 - @sqrt(xi * xi + dz * dz);
}

/// FN d: round to nearest, halves up (INT(v) - TRUE when the fraction is >= 0.5).
pub fn fnD(v: f32) i32 {
    const fl = @floor(v);
    const up = @abs(v - fl) >= @abs(v - @floor(v + 1));
    return @as(i32, @intFromFloat(fl)) - (if (up) TRUE else 0);
}

/// FN c: brightness 0..1 -> colour 0..15, dithered: d DIV 10, plus TRUE (-1) when RAND(10)
/// beats d MOD 10. So the mean colour is max(0, (d - 9) / 10) and 159 is exactly 15.
pub fn fnC(v: f32, r: *Rand) u8 {
    const d = fnD(v * 159);
    const c = @divTrunc(d, 10) + (if (r.next(10) > @rem(d, 10)) TRUE else 0);
    return @intCast(@max(0, @min(c, 255)) & 15); // PSET draws the low 4 bits (4 planes)
}

/// Line 7, exact: the discriminant of the listing's quadric in z (its B lacks the 300*x%^2
/// a true sphere needs: the shape is the listing's, kept). Null: no hit.
pub fn sphereZ(x: i32, y: i32) ?f32 {
    const a: i64 = x * x + y * y + 22500;
    const b: i64 = 300 * y * y - 9000 * x - 2700000;
    const c: i64 = 22500 * @as(i64, x * x + y * y) - 1350000 * @as(i64, x) + 300000;
    const disc = b * b - 4 * a * c;
    if (disc <= 0) return null;
    const bf: f32 = @floatFromInt(b);
    return (-bf - @sqrt(@as(f32, @floatFromInt(disc)))) / 2 / @as(f32, @floatFromInt(a));
}

/// Line 7 for a sub-pixel ray (gfa_tc.zig), in f32: its error is ~1e-5 of a pixel there.
pub fn sphereZf(x: f32, y: f32) ?f32 {
    const a = x * x + y * y + 22500;
    const b = 300 * y * y - 9000 * x - 2700000;
    const c = 22500 * (x * x + y * y) - 1350000 * x + 300000;
    const disc = b * b - 4 * a * c;
    if (!(disc > 0)) return null;
    return (-b - @sqrt(disc)) / 2 / a;
}

/// Line 9's brightness: the sphere, centre (30, 0, 60), lit by FN a, ambient 0.15.
pub fn sphereV(x: f32, y: f32, z: f32) f32 {
    const px = (x * z) / 150 + x;
    const py = (y * z) / 150 + y;
    return fnA(px - 30, py, -60 + z, px, py, z, 0.15);
}

/// Lines 11-12's brightness: the floor at y = -99; `scr.ptst(x, y)` reads the screen.
pub fn floorV(x: f32, y: f32, scr: anytype) f32 {
    const z = -14850 / y - 150;
    const px = (x * z) / 150 + x;
    const tx: u32 = @intCast(@mod(@as(i32, @intFromFloat(@floor(px / 2 + 10000))), 63));
    const ty: u32 = @intCast(15 - @mod(@as(i32, @intFromFloat(@floor(z / 2))), 16));
    const text = truth(scr.ptst(tx, ty)) * 0.3;
    const shadow = truth(fnB(px, z) >= 0) * 0.5;
    return @max(0, text + shadow + fnA(0, 1, 0, px, -99, z, 0.09));
}

/// Line 14's brightness: the sky over the horizon, 0 < y <= 24.
pub fn skyV(y: f32) f32 {
    return 1 - @min(22, y) / 22;
}
