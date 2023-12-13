const std = @import("std");
const Endian = std.builtin.Endian;

pub const native = @import("builtin").cpu.arch.endian();

pub inline fn swapToEndian(comptime S: type, s: *S, endian: Endian) void {
    if (endian != native) byteSwap(S, s);
}

pub fn byteSwap(comptime S: type, ptr: *S) void {
    switch (@typeInfo(S)) {
        .Struct => |Struct| {
            inline for (Struct.fields) |f| {
                byteSwap(f.type, &@field(ptr, f.name));
            }
        },
        .Array => |Array| {
            inline for (ptr) |*n| {
                byteSwap(Array.child, n);
            }
        },
        else => ptr.* = @byteSwap(ptr.*),
    }
}
