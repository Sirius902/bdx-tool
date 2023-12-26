const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const log = @import("log.zig");
const Program = @import("program.zig").Program;
const ProgramHeader = @import("program.zig").ProgramHeader;
const EndianStreamSource = @import("stream/stream.zig").EndianStreamSource;
const streamPosFromOffset = @import("stream/stream.zig").streamPosFromOffset;
const offsetFromStreamPos = @import("stream/stream.zig").offsetFromStreamPos;

const Instruction = @import("instruction.zig").Instruction;
const fmtInstruction = @import("instruction.zig").fmtInstruction;

allocator: Allocator,
stream: EndianStreamSource,

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

pub const StreamError = error{UnexpectedEndOfStream} || EndianStreamSource.ReadError || EndianStreamSource.SeekError;

pub fn parse(self: *Self) (Allocator.Error || StreamError)!Result {
    var program: Program = .{
        .header = undefined,
        .functions = std.AutoArrayHashMap(u32, u32).init(self.allocator),
    };
    errdefer program.deinit();

    const err = self.parseProgram(&program) catch |err| return switch (err) {
        error.EndOfStream => error.UnexpectedEndOfStream,
        else => |e| e,
    };

    if (err) |e| {
        program.deinit();
        return .{ .Error = e };
    }

    return .{ .Program = program };
}

pub fn parseProgram(self: *Self, program: *Program) (error{EndOfStream} || Allocator.Error || StreamError)!?Error {
    program.header = try self.stream.readStruct(ProgramHeader);
    log.info("Parsing program \"{s}\"", .{program.header.name()});

    while (true) {
        const entry = try self.stream.readStruct(FunctionEntry);
        if (entry.address == 0) break;

        const duplicate = try program.functions.fetchPut(entry.id, entry.address);
        if (duplicate) |kv| {
            return .{ .DuplicateFunctionId = .{ .id = kv.key } };
        }
    }

    var iter = program.functions.iterator();
    while (iter.next()) |kv| {
        const function = kv.key_ptr.*;
        const pos = streamPosFromOffset(kv.value_ptr.*);
        try self.stream.seekTo(pos);

        const res = try Instruction.decode(&self.stream);
        std.log.debug("Function {X}: Pos {X:0>8}: {X:0>4} => {?}", .{
            function,
            pos,
            res.code,
            fmtInstruction(res.instruction, offsetFromStreamPos(try self.stream.getPos())),
        });
    }

    return null;
}

test "ProgramHeader size" {
    try std.testing.expectEqual(0x1C, @sizeOf(ProgramHeader));
}
