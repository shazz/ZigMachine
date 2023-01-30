// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const shapes = @import("../effects/shapes.zig");
const Coord = shapes.Coord;
const za = @import("../utils/zalgebra.zig");

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

pub const PHYSICAL_WIDTH: u16 = @import("../zigos.zig").PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT: u16 = @import("../zigos.zig").PHYSICAL_HEIGHT;

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {

    rnd: std.rand.DefaultPrng = undefined,
    vector: za.Vec3 = undefined,
    matrix: za.Mat4 = undefined,
    triangle: [3]Vec4 = undefined,
    faces: [1]Vec4 = undefined,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices: [3]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    zoom: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        self.rnd = RndGen.init(0);

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        var j: u8 = 1;
        while (j < 255) : (j += 1) {
            fb.setPaletteEntry(j, Color{ .r = 0, .g = 0, .b = 255, .a = 255 - j });
        }

        self.triangle = [3]Vec4{
                Vec4.new(-1.0,  0.0,  0.0, 1.0),
                Vec4.new( 1.0,  0.0,  0.0, 1.0),
                Vec4.new( 0.0,  2.0,  0.0, 1.0),
        };

        self.faces = [1]Vec4{
            Vec4.new(1, 2, 3, 1),
        };

        self.projection = za.perspective(40.0, 200.0 / 320.0, 20, 1800);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -14.0), 0, 0);
        self.screen = za.screen(320, 200);   

        self.zoom = 1.4;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {

        for(self.triangle) |triangle_vertex, idx| {

            const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            const vertex_after_scale = rot_scale.vec4mulByMat4(triangle_vertex);

            const rot_mat = Mat4.fromEulerAngles(Vec3.new(self.angle_x, self.angle_y, self.angle_z));
            const vertex_after_rot = rot_mat.vec4mulByMat4(vertex_after_scale);

            const vertex_after_cam = self.camera.vec4mulByMat4(vertex_after_rot);
            const vertex_after_proj = self.projection.vec4mulByMat4(vertex_after_cam);
                    
            const norm = Vec4.set(1/vertex_after_proj.w());
            var vertex_after_norm = vertex_after_proj.mul(norm);

            const vertex_after_screen = self.screen.vec4mulByMat4(vertex_after_norm);

            const coord_x: i16 = @floatToInt(i16, vertex_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, vertex_after_screen.y()); 

            self.projected_vertices[idx].x=coord_x;
            self.projected_vertices[idx].y=coord_y;
        }        

        // self.angle_x += 1.8;
        // self.angle_y += 0.55;
        self.angle_z += 2.0;

        _ = zigos;
        _ = time_elapsed;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.clearFrameBuffer(0);

        // shapes.fillPolygon(fb, &self.polygon, 1);
        // const polygon: [3]Coord = [_]Coord{ p1, p2, p3 };

        // fillpolygon testing
        // var i: usize = 0;
        // while (i < 20000) : (i += 1) {
        //     const p1: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const p2: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const p3: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const polygon: [3]Coord = [_]Coord{ p1, p2, p3 };
        //     const col = self.rnd.random().intRangeAtMost(u8, 0, 255);
        //     shapes.fillPolygon(fb, &polygon, self.rnd.random().intRangeAtMost(u8, 0, 255));
        // }

        // draw lines testing
        // var i: usize = 0;
        // while (i < 20000) : (i += 1) {
        //     const p1: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const p2: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const col = self.rnd.random().intRangeAtMost(u8, 0, 255);

        //     shapes.drawLine(fb, p1, p2, col);
        // }

        // flat triangles testing
        // var i: usize = 0;
        // while (i < 20000) : (i += 1) {
        //     const p1: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const p2: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const p3: Coord = .{ .x = self.rnd.random().intRangeAtMost(i16, 0, WIDTH), .y = self.rnd.random().intRangeAtMost(i16, 0, HEIGHT) };
        //     const col = self.rnd.random().intRangeAtMost(u8, 0, 255);

        //     shapes.fillFlatTriangle(fb, p1, p2, p3, col);
        // }       

        // flat triangle rotation testing
        // Console.log("traingle coords: ({}, {}, {})", .{ self.projected_vertices[0], self.projected_vertices[1], self.projected_vertices[2] });
        shapes.fillFlatTriangle(fb, self.projected_vertices[0], self.projected_vertices[1], self.projected_vertices[2], 1);

        _ = time_elapsed;
    }
};
