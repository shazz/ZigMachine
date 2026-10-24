// Pinned pictures for apps/obj_headless.mjs: sha256 (first 16 hex) of plane
// 0's rows 24..175 (the object alone, no HUD) as 320-byte rows.
//
// PINS_OLD: key "m<model>s<mode>", frames 30, 60, ... 240 after boot, model
// picked with key 1/2, mode with S presses (FLAT, GLENZ, WIRE, SOFT).
// Taken from the cart BEFORE the fixed-point rewrite (f32 maths, every face
// drawn, the whole plane cleared each frame, keys 1-4 / 5 then): the new cart
// draws these exact pixels, so the integer path, the culling, the CPU/CHISEL
// split and the box erase changed nothing in them.
export const PINS_OLD = {
    m0s0: ["37953ca37465dfd1", "75ceda53008d2e20", "a386732aa6a037c8", "03735602134f5c2f", "c5194e98d6c80a2a", "073716eac4ff1da4", "fc9bd6db26902383", "35d0f22b4d1511ad"],
    m0s1: ["74ecc50e7a9efab0", "99ae786b02882551", "9907122679b290c2", "3e8e60a8552dc16c", "362b0780810f037c", "ffe5be5df6eff455", "96d58feb09588e9e", "aef3166340866080"],
    m0s2: ["fc8350e65fccb2fb", "d28d22a2cc0de07a", "ac8ed4fb48d8c56d", "df666417e36aa64d", "f60bd60df2d2aaa2", "2eb02fa81c6a4d13", "6ace21679f7329dd", "55036a9e6546aab8"],
    m0s3: ["0df612ad0985fd4c", "9c5c1056c66ce720", "6ac3f7ad7c47ed86", "a20cf994c4837655", "83185f615cc43752", "77be015ba27119c8", "0f2d38e52aed7cee", "f5d1c790bd31706d"],
    m1s0: ["1db86c5d2999a34f", "07a880e3899eafba", "598a4f9097a6eb29", "e1c3fc0c2f0f3508", "22552751a04905f6", "0e10dc8883e8c623", "e6217692a54e45c1", "3534d0876fa230b0"],
    m1s1: ["e0cac87b8273383e", "31537fbef6072b07", "31d530ae096774fa", "9094c94d6e2f21ea", "1d960fe3f79c5f2f", "2c390008f55c2dfa", "ca721a788afcbd75", "4c88ba2b06f886d3"],
    m1s2: ["5df20e607a83da28", "2c52f3866f6ed9a1", "d63c4298bd7b3136", "1f9d5ac1abef6a0b", "234dd7b8f6927cfc", "d63e4f8ab199024c", "569534b041cf2f1e", "7d16c2c4e6169716"],
    m1s3: ["664a86013a1b85f1", "71e64b4bf678a5b1", "0a396f03ec5349d6", "3e93f50cf99355bf", "111723eb7c4fc00b", "971ea12fd65b5e35", "7492e392b7dd4e93", "4e2989be3e5a6ea7"],
};

// PINS_SPHERE: the sphere after `level` + presses and `mode` S presses, at frame `frames`.
// Taken from this cart (2026-10-24), stills checked by eye: a smooth-lit sphere,
// a flat-lit one at the top level, a hidden-line one with no back edges.
export const PINS_SPHERE = {
    gouraud_level5: { level: 4, mode: 4, frames: 60, hash: "1da6c88d8a9461c6" },
    flat_level13: { level: 12, mode: 0, frames: 30, hash: "31df108a704edccc" },
    hidden_level7: { level: 6, mode: 5, frames: 45, hash: "25a9d40184c7ad63" },
    glenz_level4: { level: 3, mode: 1, frames: 40, hash: "9ba3c94efaae661f" },
};
