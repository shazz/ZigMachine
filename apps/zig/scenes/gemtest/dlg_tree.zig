// --------------------------------------------------------------------------
// GEMTEST's Dialogs area as a REAL object tree (G20): an AES OBJECT array in the
// program's memory, drawn, found, clicked and edited by the ROM (rom.aes.obj). Its
// topology is fixed here; area_dialogs.zig places the objects in the window's
// content each pass (the pen's rows) and acts on what the ROM reports.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const O = rom.aes.obj;

pub const ROOT: u8 = 0;
pub const OK: u8 = 1;
pub const CANCEL: u8 = 2;
pub const PLAIN: u8 = 3;
pub const DISABLED_BTN: u8 = 4;
pub const RADIOS: u8 = 5; // the group's IBOX; its buttons 6, 7, 8
pub const RADIO0: u8 = 6;
pub const CHECK0: u8 = 9; // 9 and 11 (10 and 12 their captions)
pub const FIELD: u8 = 13;
pub const TRACK: u8 = 14; // the slider's track; its knob 15
pub const KNOB: u8 = 15;
pub const N = 16;
pub const STOPS = 11; // the slider's 0..10
pub const STOP_W: i16 = 8;

const ACT = O.SELECTABLE | O.FL3DACT;
const FACE = O.boxSpec(0, 1, 0x1170); // black border, solid white
const GREY = O.boxSpec(0, 1, 0x1121); // black border, a 25 % black pattern: a track

pub const Dlg = struct {
    objs: [N]O.Object = undefined,
    ted: O.Ted = undefined,
    text: [7]u8 = "@\x00\x00\x00\x00\x00\x00".*,

    pub fn init(self: *Dlg) void {
        const s = O.addr;
        self.objs = .{
            .{ .head = 1, .tail = TRACK, .ty = O.G_IBOX, .w = 640, .h = 400 },
            btn(2, "OK", ACT | O.DEFAULT | O.EXIT, 0),
            btn(3, "Cancel", ACT | O.EXIT, 0),
            btn(4, "Plain", ACT, 0),
            btn(5, "Disabled", ACT, O.DISABLED),
            .{ .next = 9, .head = 6, .tail = 8, .ty = O.G_IBOX },
            btn(7, "Low", O.SELECTABLE | O.RBUTTON | O.FL3DIND, O.SELECTED),
            btn(8, "Medium", O.SELECTABLE | O.RBUTTON | O.FL3DIND, 0),
            btn(5, "High", O.SELECTABLE | O.RBUTTON | O.FL3DIND, 0),
            .{ .next = 10, .ty = O.G_BOX, .flags = O.SELECTABLE | O.FL3DIND, .state = O.SELECTED, .spec = FACE },
            .{ .next = 11, .ty = O.G_STRING, .spec = s("Sound") },
            .{ .next = 12, .ty = O.G_BOX, .flags = O.SELECTABLE | O.FL3DIND, .spec = FACE },
            .{ .next = 13, .ty = O.G_STRING, .spec = s("Borders") },
            .{ .next = 14, .ty = O.G_FBOXTEXT, .flags = O.EDITABLE, .spec = s(&self.ted) },
            .{ .next = 0, .head = KNOB, .tail = KNOB, .ty = O.G_BOX, .flags = O.TOUCHEXIT, .spec = GREY },
            .{ .next = TRACK, .ty = O.G_BOX, .flags = O.FL3DIND | O.LASTOB, .spec = FACE },
        };
        self.objs[RADIO0 + 2].next = RADIOS;
        self.ted = .{ .text = s(&self.text), .tmplt = s("__/__/__"), .valid = s("999999"), .color = 0x1170, .thickness = 1, .txtlen = 7, .tmplen = 9 };
    }

    pub fn tree(self: *Dlg, g: rom.Gui) O.Tree {
        return .{ .g = g, .objs = &self.objs };
    }

    /// Object `i` at content (x, y), w x h (the root sits at the content's origin).
    pub fn place(self: *Dlg, i: u16, xy: [2]i32, w: i32, h: i32) void {
        const o = &self.objs[i];
        o.x = @intCast(xy[0]);
        o.y = @intCast(xy[1]);
        o.w = @intCast(w);
        o.h = @intCast(h);
    }
};

fn btn(next: i16, s: [:0]const u8, flags: u16, state: u16) O.Object {
    return .{ .next = next, .ty = O.G_BUTTON, .flags = flags, .state = state, .spec = O.addr(s.ptr) };
}
