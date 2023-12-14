const types = @import("types.zig");

pub const Instruction = union(enum) {
    Push: Push,
    Pop,
    Copy,
    Deref,
    UnaryOp,
    BinOp,
    Branch,
    Jump,
    Halt,
    Exit,
    Ret,
    Dup,
    Syscall,

    pub fn decode(code: u16) ?Instruction {
        const bits: InstructionBits = @bitCast(code);
        return switch (bits.group) {
            0 => switch (bits.flags) {
                0 => .{ .Push = .{ .Int = 0 } },
                1 => .{ .Push = .{ .Float = 0.0 } },
                else => .Push,
            },
            1 => .Pop,
            // TODO: Copy immediate
            2 => null,
            3 => .Lookup,
            4 => .Copy,
            else => null,
        };
    }
};

pub const InstructionBits = packed struct {
    group: u4,
    flags: u2,
    immediate: u10,
};

pub const Push = union(enum) {
    Int: struct { i: types.Int },
    Float: struct { f: types.Float },
};
