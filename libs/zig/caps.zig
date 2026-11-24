// zg.caps: the machine's capability word (HW 1.19.0, docs/hardware/ABI_RULES.md). Ask before using an
// optional unit and fall back when it is absent; never infer a unit from the host (browser vs board).
//
//     if (zg.caps.has(.astro)) runOnAstrolabe(d) else runInCart(d);
const hw = @import("hardware");

pub const Cap = hw.caps.Cap;

/// The whole word, one bit per Cap (machine/sdk/caps.zig).
pub fn word() u32 {
    return hw.hwCaps();
}

/// Is the optional unit `c` here? A machine older than 1.19 has no such import: the cart is refused at link time.
pub fn has(c: Cap) bool {
    return hw.caps.has(hw.hwCaps(), c);
}
