# KESTREL: ayumi works in float, but its unsuffixed constants (0.5, the FIR taps) are double, so every
# expression with one is computed in double: soft-float on the cart CPU (f32 has an FPU there, f64 does not),
# ~20,000 cycles a sample (apps/frame_cost.mjs). Every floating literal becomes a float literal.
s/\([0-9]\.[0-9]\+\(e-\?[0-9]\+\)\?\)\([^0-9fe]\|$\)/\1f\3/g
