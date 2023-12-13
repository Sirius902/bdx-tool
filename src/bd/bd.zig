comptime {
    @import("std").testing.refAllDecls(@This());
}

pub const Parser = @import("Parser.zig");

pub usingnamespace @import("types.zig");
pub usingnamespace @import("program.zig");
