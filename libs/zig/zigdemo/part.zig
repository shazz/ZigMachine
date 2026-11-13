//! zigdemo parts: the cart's parts as a comptime tagged union, with no vtable.
//!
//! A cart declares `const Parts = union(enum) { fade: Fade, bar: Bar, ... }`.
//! Each variant is a part struct, and its fields are the part's state. The tag
//! order is the item's `part` id, so an item names its part by a number. A
//! part struct has:
//!   update(self, ctx, t_ms)   required, every frame while it is on the timeline
//!   render(self, ctx, t_ms)   required, every frame while it is on the timeline
//!   init(self, ctx, arg)      optional, when its draw item starts (arg = the item's)
//!   deinit(self, ctx)         optional, when its draw item ends
//!   once(ctx, arg)            optional, a static hook for a `once` item (a load)
//! A transition is a part whose render calls the render of two other parts.
//!
//! The dispatch is an `inline else` switch over the tag: no vtable, no allocation.

const std = @import("std");

pub fn Dispatch(comptime Ctx: type, comptime Parts: type) type {
    return struct {
        pub const count = @typeInfo(Parts).@"union".fields.len;

        /// A fresh part of kind `id`, from its field defaults. Demo checks the
        /// ids at comptime, so an id past the union is a bug in the cart.
        pub fn make(id: u16) Parts {
            inline for (@typeInfo(Parts).@"union".fields, 0..) |f, i| {
                if (id == i) return @unionInit(Parts, f.name, .{});
            }
            unreachable;
        }

        pub fn init(p: *Parts, ctx: *Ctx, arg: u16) void {
            switch (p.*) {
                inline else => |*s| {
                    if (@hasDecl(@TypeOf(s.*), "init")) s.init(ctx, arg);
                },
            }
        }

        pub fn update(p: *Parts, ctx: *Ctx, t: u32) void {
            switch (p.*) {
                inline else => |*s| s.update(ctx, t),
            }
        }

        pub fn render(p: *Parts, ctx: *Ctx, t: u32) void {
            switch (p.*) {
                inline else => |*s| s.render(ctx, t),
            }
        }

        pub fn deinit(p: *Parts, ctx: *Ctx) void {
            switch (p.*) {
                inline else => |*s| {
                    if (@hasDecl(@TypeOf(s.*), "deinit")) s.deinit(ctx);
                },
            }
        }

        /// Runs the `once` hook of part kind `id`, if it has one. A `once` item
        /// names a part only to reach its hook; it draws nothing.
        pub fn once(ctx: *Ctx, id: u16, arg: u16) void {
            var p = make(id);
            switch (p) {
                inline else => |*s| {
                    const T = @TypeOf(s.*);
                    if (@hasDecl(T, "once")) T.once(ctx, arg);
                },
            }
        }
    };
}
