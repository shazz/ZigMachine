"""Vertex-clustering decimation for the sb_spike LOD keys (2x, 3x, 4x fewer triangles).

The spike measures how many textured triangles KESTREL draws, so the lower levels only
have to be plausible meshes of the right size: a uniform grid over the mesh, every
vertex snapped to its cell, triangles that collapse dropped. The texture seams survive
because a new vertex is a (cell, chart) pair: a chart is a set of triangles joined by
shared vertex indices (the exporter splits vertices at UV seams), and the new vertex
takes the mean uv and normal of its chart's old vertices in the cell. A quadric
edge-collapse (better silhouettes) is deferred to the port proper.
"""
import math


def charts(nv, tris):
    """Chart id per vertex: union-find over triangles that share a vertex index."""
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in tris:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    return [find(i) for i in range(nv)]


def cluster(mesh, cell):
    """One clustering pass at grid size `cell`: (vertices, triangles)."""
    p, uv, n, tris = mesh['p'], mesh['uv'], mesh['n'], mesh['tris']
    chart = mesh['chart']
    cell_of = [tuple(math.floor(c / cell) for c in v) for v in p]
    groups = {}
    for i in range(len(p)):
        groups.setdefault((cell_of[i], chart[i]), []).append(i)
    pos_of_cell = {}
    for i, c in enumerate(cell_of):
        pos_of_cell.setdefault(c, []).append(p[i])
    remap, verts = {}, []
    for key, members in groups.items():
        ps = pos_of_cell[key[0]]
        pos = tuple(sum(v[k] for v in ps) / len(ps) for k in range(3))
        u = tuple(sum(uv[i][k] for i in members) / len(members) for k in range(2))
        nn = [sum(n[i][k] for i in members) for k in range(3)]
        ln = math.sqrt(sum(c * c for c in nn)) or 1.0
        for i in members:
            remap[i] = len(verts)
        verts.append((pos, u, tuple(c / ln for c in nn)))
    out, seen = [], set()
    for a, b, c in tris:
        ca, cb, cc = cell_of[a], cell_of[b], cell_of[c]
        if ca == cb or cb == cc or ca == cc:
            continue
        t = (remap[a], remap[b], remap[c])
        k = tuple(sorted(t))
        if k in seen:
            continue
        seen.add(k)
        out.append(t)
    return verts, out


def compact(verts, tris):
    """Drop the vertices no triangle uses."""
    used = sorted({i for t in tris for i in t})
    index = {old: new for new, old in enumerate(used)}
    return [verts[i] for i in used], [tuple(index[i] for i in t) for t in tris]


def decimate(mesh, target):
    """The clustering whose triangle count is closest to `target` (bisection on the cell)."""
    if target >= len(mesh['tris']):
        verts = list(zip(mesh['p'], mesh['uv'], mesh['n']))
        return compact(verts, mesh['tris'])
    mesh = dict(mesh, chart=charts(len(mesh['p']), mesh['tris']))
    lo, hi = 1e-4, 4.0
    best = None
    for _ in range(28):
        mid = math.sqrt(lo * hi)
        verts, tris = cluster(mesh, mid)
        if best is None or abs(len(tris) - target) < abs(len(best[1]) - target):
            best = (verts, tris)
        if len(tris) > target:
            lo = mid
        else:
            hi = mid
    return compact(*best)
