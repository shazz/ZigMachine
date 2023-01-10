// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Coord = @import("shapes.zig").Coord;
const shapes = @import("shapes.zig");

const Console = @import("../utils/debug.zig").Console;
// const zm = @import("..utils/zmath.zig");
const za = @import("../utils/zalgebra.zig");

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;

const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Dots3D = struct {
    fb: *LogicalFB = undefined,
    vector: za.Vec3 = undefined,
    matrix: za.Mat4 = undefined,
    cube: [8]Vec4 = undefined,
    faces: [12]Vec3 = undefined,
    projection: Mat4 = undefined,
    camera: Mat4 = undefined,
    screen: Mat4 = undefined,
    projected_vertices: [8]Coord = undefined,
    angle_y: f32 = 0.0,
    angle_x: f32 = 0.0,
    angle_z: f32 = 0.0,
    zoom: f32 = 0.0,
    zoom_dir: f32 = 0.0,

    pub fn init(self: *Dots3D, fb: *LogicalFB) void {
        self.fb = fb;

        fb.setPaletteEntry(10, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(11, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });  
        fb.setPaletteEntry(12, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });        
        fb.setPaletteEntry(13, Color{ .r = 0, .g = 255, .b = 0, .a = 255 });   
        fb.setPaletteEntry(14, Color{ .r = 0, .g = 0, .b = 255, .a = 255 });   

        // Clear
        fb.clearFrameBuffer(0);    

        self.cube = [8]Vec4{
                Vec4.new(1.0,  -1.0, -1.0, 1.0),
                Vec4.new(1.0,  -1.0,  1.0, 1.0),
                Vec4.new(-1.0, -1.0,  1.0, 1.0),
                Vec4.new(-1.0, -1.0, -1.0, 1.0),
                Vec4.new(1.0,   1.0, -1.0, 1.0),
                Vec4.new(1.0,   1.0,  1.0, 1.0),
                Vec4.new(-1.0,  1.0,  1.0, 1.0),
                Vec4.new(-1.0,  1.0, -1.0, 1.0),
        };

        self.faces = [12]Vec3{
            Vec3.new(1, 2, 3),
            Vec3.new(7, 6, 5),
            Vec3.new(4, 5, 1),
            Vec3.new(5, 6, 2),
            Vec3.new(2, 6, 7),
            Vec3.new(0, 3, 7),
            Vec3.new(0, 1, 3),
            Vec3.new(4, 7, 5),
            Vec3.new(0, 4, 1),
            Vec3.new(1, 5, 2),
            Vec3.new(3, 2, 7),
            Vec3.new(4, 0, 7),
        };

        self.projection = za.perspective(60.0, 200.0 / 320.0, 0.1, 100.0);
        self.camera = za.camera(Vec3.new(0.0, 0.0, -10.0), 0, 0);
        self.screen = za.screen(320, 200);        

    }

    pub fn update(self: *Dots3D) void {

        for(self.cube) |cube_point, idx| {

            const rot_scale = Mat4.fromScale(Vec3.new(self.zoom, self.zoom, self.zoom));
            const point_after_scale = rot_scale.vec4mulByMat4(cube_point);

            const rot_mat = Mat4.fromEulerAngles(Vec3.new(self.angle_x, self.angle_y, self.angle_z));
            const point_after_rot = rot_mat.vec4mulByMat4(point_after_scale);

            const point_after_cam = self.camera.vec4mulByMat4(point_after_rot);
            const point_after_proj = self.projection.vec4mulByMat4(point_after_cam);
                    
            const norm = Vec4.set(1/point_after_proj.w());
            var point_after_norm = point_after_proj.mul(norm);

            const point_after_screen = self.screen.vec4mulByMat4(point_after_norm);

            const coord_x: i16 = @floatToInt(i16, point_after_screen.x()); 
            const coord_y: i16 = @floatToInt(i16, point_after_screen.y()); 

            self.projected_vertices[idx].x=coord_x;
            self.projected_vertices[idx].y=coord_y;
        }        

        self.angle_x += 1.8;
        self.angle_y += 0.55;
        
        if(self.zoom > 2.0) {
            self.zoom_dir = -0.001;
        } 
        if(self.zoom <= 0.0) {
            self.zoom_dir = 0.001;
        }
         
        self.zoom += self.zoom_dir;
    }

    pub fn render(self: *Dots3D) void {

        for(self.faces) |face| {
                const v1: Coord = self.projected_vertices[@floatToInt(usize, face.x())];
                const v2: Coord = self.projected_vertices[@floatToInt(usize, face.y())];
                const v3: Coord = self.projected_vertices[@floatToInt(usize, face.z())];

                shapes.drawLine(self.fb, v1, v2, 12);   
                shapes.drawLine(self.fb, v2, v3, 12);  
                shapes.drawLine(self.fb, v3, v1, 12);  

                self.fb.setPixelValue(@intCast(u16, v1.x), @intCast(u16, v1.y), 11);
                self.fb.setPixelValue(@intCast(u16, v2.x), @intCast(u16, v2.y), 11);
                self.fb.setPixelValue(@intCast(u16, v3.x), @intCast(u16, v3.y), 11);
        }
    }
};
