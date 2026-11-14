"""Readers for Suicide Barbie's PSP blobs (mutalisk .msk/.msh/.man/.mtx), the mix3 subset.

Formats: prototypes/suicide_barbie_re/ANALYSIS.md section 2; reference readers in
prototypes/suicide_barbie_re/tools/sb_parse.py and sb_anim.py. The data is untrusted:
run the tools with python3 -I (no numpy needed).
"""
import struct
import zlib


def load(path):
    """A blob, inflated when it carries the MTc1 zlib wrapper."""
    with open(path, 'rb') as f:
        d = f.read()
    return zlib.decompress(d[4:]) if d[:4] == b'MTc1' else d


class R:
    def __init__(s, b):
        s.b = b
        s.p = 0

    def u32(s):
        v = struct.unpack_from('<I', s.b, s.p)[0]
        s.p += 4
        return v

    def u8(s):
        v = s.b[s.p]
        s.p += 1
        return v

    def f(s, n):
        v = struct.unpack_from('<%df' % n, s.b, s.p)
        s.p += 4 * n
        return v

    def raw(s, n):
        v = s.b[s.p:s.p + n]
        s.p += n
        return v

    def str(s):
        return s.raw(s.u32()).decode('latin1')


def _node(r):
    r.u32()
    name = r.str()
    r.f(16)  # world matrix: every mix3 node is animated, the clip overrides it
    r.u32()
    return name


def _material(r):
    shader = r.u32()
    assert r.u32() == 0x103, 'shader_fixed version'
    r.f(16)  # ambient, diffuse, specular, emissive
    dtex, etex = r.u32(), r.u32()
    r.f(3)  # u/v offset, transparency
    fbo = r.u32()
    r.raw(12)  # zbo, xw, yw
    r.f(4)
    return dict(shader=shader, diffuse=dtex, env=etex, fbo=fbo)


def scene(path):
    """mix3.msk: mesh and texture names, the camera node, the actors and their materials."""
    r = R(load(path))
    assert r.u32() == 0x121, 'scene version'
    meshes = [r.str() for _ in range(r.u32())]
    texs = [r.str() for _ in range(r.u32())]
    r.u32()
    assert r.u32() == 0, 'mix3 has no lights'
    cams = []
    for _ in range(r.u32()):
        cams.append(_node(r))
        r.f(6)
    r.u32()
    actors = []
    for _ in range(r.u32()):
        name = _node(r)
        mesh = r.u32()
        mats = [_material(r) for _ in range(r.u32())]
        slice_ = r.u32()
        actors.append(dict(name=name, mesh=mesh, mats=mats, slice=slice_))
    return dict(meshes=meshes, textures=texs, cameras=cams, actors=actors)


def mesh(path):
    """A .msh: vertices (uv, normal, position; decl 0x1e3), u16 triangle list, subsets."""
    r = R(load(path))
    assert r.u32() == 0x103, 'mesh version'
    vc, vds, vst = r.u32(), r.u32(), r.u32()
    assert vst == 32 and vds == vc * 32
    vd = r.raw(vds)
    ic, isz = r.u32(), r.u32()
    assert isz == 2
    idx = struct.unpack('<%dH' % ic, r.raw(ic * 2))
    subs = [(r.u32(), r.u32()) for _ in range(r.u32())]
    decl, prim = r.u32(), r.u32()
    assert decl == 0x1e3 and prim == 3, 'uv+normal+position triangle lists only'
    verts = [struct.unpack_from('<8f', vd, i * 32) for i in range(vc)]
    out = []
    for start, count in subs:
        tris = [tuple(idx[start + 3 * t:start + 3 * t + 3]) for t in range(count // 3)]
        out.append(tris)
    return dict(uv=[v[0:2] for v in verts], n=[v[2:5] for v in verts], p=[v[5:8] for v in verts], subsets=out)


def anim(path):
    """mix3.man: {node: [(t3, q4 xyzw), ...]} at 30 Hz (every clip is baked at 30 Hz)."""
    r = R(load(path))
    r.u32()
    r.str()
    nh, nc = r.u32(), r.u32()
    for _ in range(nh):
        r.str()
        for _ in range(r.u32()):
            r.str()
            r.raw(4 * r.u32())
    assert nc == 1
    r.str()
    r.u32()
    r.f(1)
    nodes = {}
    for _ in range(r.u32()):
        name = r.str()
        for _ in range(r.u32()):
            et, cs, kind, kc = r.u8(), r.u8(), r.str(), r.u32()
            r.raw(4 * kc)  # key times: 0, 1/30, ... (checked by the caller via the count)
            assert et == 1 and cs == 10 and kind == 'vecQuatVec'
            v = r.f(kc * 10)
            keys = [(v[i * 10:i * 10 + 3], v[i * 10 + 3:i * 10 + 7], v[i * 10 + 7:i * 10 + 10]) for i in range(kc)]
            nodes[name] = keys
    return nodes


def texture(path):
    """A T8 .mtx: (w, h, rows of RGBA tuples), un-swizzled (16-byte x 8-row blocks)."""
    b = load(path)
    sig, pf, w, h, st, alloc, cf, ce, po, bits, _ = struct.unpack_from('<IHHHHIHHIII', b, 0)
    assert b[:4] == b'MTX2' and pf == 5 and cf == 3 and ce == 32 and st == w
    tex = b[32:32 + w * h]
    pal = [struct.unpack_from('<4B', b, 32 + po + 4 * i) for i in range(256)]
    lin = bytearray(w * h)
    if bits & 1:
        bw = w // 16
        for i in range(w * h):
            blk, o = divmod(i, 128)
            by, bx = divmod(blk, bw)
            ry, rx = divmod(o, 16)
            lin[(by * 8 + ry) * w + bx * 16 + rx] = tex[i]
    else:
        lin[:] = tex
    return w, h, [[pal[lin[y * w + x]] for x in range(w)] for y in range(h)]
