const std = @import("std");
const Instruction = @import("instruction.zig").Instruction;

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
    known_instructions: KnownInstructionQueue,

    pub const KnownInstructionQueue = std.PriorityQueue(KnownInstruction, void, KnownInstruction.compareFn);

    pub fn deinit(self: *Program) void {
        self.functions.deinit();
        self.known_instructions.deinit();
    }
};

pub const KnownInstruction = struct {
    pos: u64,
    code: u16,
    pc: u16,
    instruction: Instruction,

    pub fn compareFn(_: void, k1: KnownInstruction, k2: KnownInstruction) std.math.Order {
        return std.math.order(k1.pos, k2.pos);
    }
};
