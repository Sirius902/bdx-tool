const std = @import("std");

pub const ProgramHeader = extern struct {
    name_bytes: [0x10]u8,
    heap_size: u32,
    frames_size: u32,
    stack_size: u32,

    pub fn name(self: *const ProgramHeader) []const u8 {
        const end = std.mem.indexOfScalarPos(u8, &self.name_bytes, 0, 0) orelse self.name_bytes.len;
        return self.name_bytes[0..end];
    }
};

pub const Program = struct {
    header: ProgramHeader,
    functions: std.AutoArrayHashMap(u32, u32),

    pub fn deinit(self: *Program) void {
        self.functions.deinit();
    }
};
