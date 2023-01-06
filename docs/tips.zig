const std = @import("std");
const print = @import("std").debug.print;

// get variable type:
pub fn showDataTYpe() void {
    const MyEnum = struct {
        char: u8 = undefined,
        char_pointer: *u32 = undefined,
    };

    var an_int: u32 = 10;
    var my_enum: MyEnum = MyEnum{
        .char = 'A',
        .char_pointer = &an_int,
    };

    print("Data type of my_enum: {s}\n", .{@typeName(@TypeOf(my_enum))});
    print("Data type of &my_enum: {s}\n", .{@typeName(@TypeOf(&my_enum))});
    print("Data type of my_enum.char: {s}\n", .{@typeName(@TypeOf(my_enum.char))});
    print("Data type of my_enum.char_pointer: {s}\n", .{@typeName(@TypeOf(my_enum.char_pointer))});
}

// GPA allocator
pub fn gpaAllocator() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    if (allocator.alloc(u8, 2)) |buffer| {
        defer allocator.destroy(&buffer);

        buffer[0] = 'A';
        print("buffer[0]: {d} {c}\n", .{ buffer[0], buffer[0] });

        // undefined
        print("buffer[1]: {d} {c}\n", .{ buffer[1], buffer[1] });

        // catch out of bounds
        // if(buffer[2]) |a_var| {
        //     print("Really? {}", .{a_var});
        // } else |err| {
        //     print("expected error :{})", .{err});
        // }

    } else |err| {
        print("Alloc failed due to: {}", .{err});
    }
}

// iterate bu reference
pub fn forByRef() void {
    var items = [_]i32{ 3, 4, 2 };

    // Iterate over the slice by reference by
    // specifying that the capture value is a pointer.
    for (items) |*value| {
        value.* += 1;
    }
}

pub fn catchError() vois {
    // if (Demo.init(&zigos)) |aDemo| {
    //     demo = aDemo;
    // } else |err| {
    //     Console.log("Demo.init failed: {s}", .{@errorName(err)});
    //     @panic("Guru meditation");
    // }
}

// ----------------------------------------------------------------------
// Try tips!
// ----------------------------------------------------------------------

pub fn main() void {
    showDataTYpe();
    gpaAllocator();
    forByRef();
}
