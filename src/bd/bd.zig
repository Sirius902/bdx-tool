comptime {
    @import("std").testing.refAllDecls(@This());
}

pub const Parser = @import("Parser.zig");

pub usingnamespace @import("instruction.zig");
pub usingnamespace @import("program.zig");
pub usingnamespace @import("stream.zig");
pub usingnamespace @import("types.zig");
