// --------------------------------------------------------------------------
// The frame's object storage. The desk is rebuilt as object trees every drawn
// frame (cheap: a few hundred objects), so the trees, their TEDINFOs, ICONBLKs
// and generated strings live in one fixed pool, reset at the start of a frame.
// The ROM has no allocator in its frame path; a full pool says so (`full`) and
// the frame then repaints whole on the old path (engine.zig).
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const scene = @import("../../engine/scene.zig");
const Object = eng.Object;
const NIL = eng.NIL;

pub const Pool = struct {
    objs: [scene.MAX_OBJS]Object = undefined,
    n: usize = 0,
    teds: [96]eng.Ted = undefined,
    n_ted: usize = 0,
    icons: [160]eng.IconBlk = undefined,
    n_icon: usize = 0,
    text: [6144]u8 = undefined,
    n_text: usize = 0,
    full: bool = false,

    pub fn reset(self: *Pool) void {
        self.n = 0;
        self.n_ted = 0;
        self.n_icon = 0;
        self.n_text = 0;
        self.full = false;
    }

    pub fn ted(self: *Pool, t: eng.Ted) *const eng.Ted {
        if (self.n_ted == self.teds.len) return self.fail(&EMPTY_TED);
        self.teds[self.n_ted] = t;
        self.n_ted += 1;
        return &self.teds[self.n_ted - 1];
    }

    pub fn icon(self: *Pool, ib: eng.IconBlk) *const eng.IconBlk {
        if (self.n_icon == self.icons.len) return self.fail(&EMPTY_ICON);
        self.icons[self.n_icon] = ib;
        self.n_icon += 1;
        return &self.icons[self.n_icon - 1];
    }

    /// Room for `len` bytes of text (filled by the caller), "" when the pool is full.
    pub fn bytes(self: *Pool, len: usize) []u8 {
        if (self.n_text + len > self.text.len) {
            self.full = true;
            return self.text[0..0];
        }
        defer self.n_text += len;
        return self.text[self.n_text..][0..len];
    }

    fn fail(self: *Pool, v: anytype) @TypeOf(v) {
        self.full = true;
        return v;
    }
};

const EMPTY_TED: eng.Ted = .{ .text = "" };
const EMPTY_ICON: eng.IconBlk = .{ .mask = &.{}, .data = &.{}, .w = 0, .h = 0 };

/// One tree being built in the pool: objects are appended and linked as GEM links them
/// (a parent's children run head -> next -> ... -> back to the parent).
pub const Tree = struct {
    pool: *Pool,
    first: usize,
    len: usize = 0,

    pub fn begin(pool: *Pool, root: Object) Tree {
        var t: Tree = .{ .pool = pool, .first = pool.n };
        var r = root;
        r.next = NIL;
        r.head = NIL;
        r.tail = NIL;
        _ = t.push(r);
        return t;
    }

    fn push(self: *Tree, o: Object) i16 {
        if (self.pool.n == self.pool.objs.len) {
            self.pool.full = true;
            return NIL;
        }
        self.pool.objs[self.pool.n] = o;
        self.pool.n += 1;
        self.len += 1;
        return @intCast(self.len - 1);
    }

    /// Append `o` as the last child of `parent` (a local index); its local index, NIL when full.
    pub fn add(self: *Tree, parent: i16, o: Object) i16 {
        if (parent == NIL) return NIL;
        var c = o;
        c.next = parent;
        c.head = NIL;
        c.tail = NIL;
        const i = self.push(c);
        if (i == NIL) return NIL;
        const objs = self.pool.objs[self.first..];
        const p = &objs[@intCast(parent)];
        if (p.head == NIL) p.head = i else objs[@intCast(p.tail)].next = i;
        p.tail = i;
        return i;
    }

    pub fn objects(self: *const Tree) []Object {
        return self.pool.objs[self.first..][0..self.len];
    }
};
