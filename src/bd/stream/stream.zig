comptime {
    @import("std").testing.refAllDecls(@This());
}

pub const EndianStreamSource = @import("EndianStreamSource.zig");

pub fn offsetToStreamPos(offset: u32) u64 {
    return 0x10 + @sizeOf(u16) * @as(u64, offset);
}

pub fn streamPosToOffset(pos: u64) u16 {
    return @intCast((pos - 0x10) / @sizeOf(u16));
}
