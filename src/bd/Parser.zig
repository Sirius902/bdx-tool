const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Endian = std.builtin.Endian;
const StreamSource = std.io.StreamSource;

const endian = @import("endian.zig");
const log = @import("log.zig");
const Program = @import("program.zig").Program;
const ProgramHeader = @import("program.zig").ProgramHeader;
const offsetToStreamPos = @import("stream.zig").offsetToStreamPos;

const Instruction = @import("instruction.zig").Instruction;
const InstructionBits = @import("instruction.zig").InstructionBits;

allocator: Allocator,
stream: StreamSource,
endian: ?Endian = null,

const Self = @This();

const FunctionEntry = packed struct {
    id: u32,
    address: u32,
};

pub const Error = union(enum) {
    DuplicateFunctionId: struct { id: u32 },
};

pub const Result = union(enum) {
    Program: Program,
    Error: Error,
};

pub const StreamError = error{EndOfStream} || StreamSource.ReadError || StreamSource.SeekError;

pub fn parse(self: *Self) (Allocator.Error || StreamError)!Result {
    var program: Program = .{
        .header = undefined,
        .functions = std.AutoArrayHashMap(u32, u32).init(self.allocator),
    };
    errdefer program.deinit();

    const err = try self.parseProgram(&program);
    if (err) |e| {
        program.deinit();
        return .{ .Error = e };
    }

    var iter = program.functions.iterator();
    while (iter.next()) |kv| {
        const function = kv.key_ptr.*;
        const pos = offsetToStreamPos(kv.value_ptr.*);
        try self.stream.seekTo(pos);
        const code = try self.stream.reader().readInt(u16, self.targetEndian());

        std.log.debug("Function {X}: Pos {X:0>8}: {X:0>4} => {?}", .{ function, pos, code, Instruction.decode(code) });
    }

    return .{ .Program = program };
}

pub fn parseProgram(self: *Self, program: *Program) (Allocator.Error || StreamError)!?Error {
    program.header = try self.readStruct(ProgramHeader);
    log.info("Parsing program \"{s}\"", .{program.header.name()});

    while (true) {
        const entry = try self.readStruct(FunctionEntry);
        if (entry.address == 0) break;

        const duplicate = try program.functions.fetchPut(entry.id, entry.address);
        if (duplicate) |kv| {
            return .{ .DuplicateFunctionId = .{ .id = kv.key } };
        }
    }

    return null;
}

fn targetEndian(self: Self) Endian {
    return self.endian orelse endian.native;
}

fn readInt(self: *Self, comptime T: type) StreamError!T {
    return try self.stream.reader().readInt(T, self.targetEndian());
}

fn readStruct(self: *Self, comptime T: type) StreamError!T {
    var t = try self.stream.reader().readStruct(T);
    endian.swapToEndian(T, &t, self.targetEndian());
    return t;
}

test "ProgramHeader size" {
    try std.testing.expectEqual(0x1C, @sizeOf(ProgramHeader));
}
