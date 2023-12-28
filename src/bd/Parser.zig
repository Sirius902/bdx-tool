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

const EntrypointData = packed struct {
    id: u32,
    offset: u32,
};

pub const Error = union(enum) {
    DuplicateEntrypointId: struct { id: u32 },
};

pub const Result = union(enum) {
    Program: Program,
    Error: Error,
};

pub const StreamError = error{UnexpectedEndOfStream} || EndianStreamSource.ReadError || EndianStreamSource.SeekError;

pub fn parse(self: *Self) (Allocator.Error || StreamError)!Result {
    var program: Program = .{
        .header = undefined,
        .entrypoints = std.AutoArrayHashMap(u32, u32).init(self.allocator),
        .known_instructions = Program.KnownInstructionQueue.init(self.allocator, {}),
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
        const entry = try self.stream.readStruct(EntrypointData);
        if (entry.offset == 0) break;

        const duplicate = try program.entrypoints.fetchPut(entry.id, entry.offset);
        if (duplicate) |kv| {
            return .{ .DuplicateEntrypointId = .{ .id = kv.key } };
        }
    }

    // TODO: This needs to become a BFS with branching control flow.
    var iter = program.entrypoints.iterator();
    const kv = iter.next() orelse return null;

    try self.stream.seekTo(streamPosFromOffset(kv.value_ptr.*));
    if (try self.followInstructionFlow(program)) |err| {
        return err;
    }

    return null;
}

pub fn followInstructionFlow(self: *Self, program: *Program) (error{EndOfStream} || Allocator.Error || StreamError)!?Error {
    while (true) {
        const pos = try self.stream.getPos();
        const res = try Instruction.decode(&self.stream);
        const pc = offsetFromStreamPos(try self.stream.getPos());

        try program.known_instructions.add(.{ .pos = pos, .code = res.code, .pc = pc, .instruction = res.instruction });

        switch (res.instruction) {
            .Branch => |b| if (b.condition == .always) break else {
                log.debug("Conditional branch, add location to search", .{});
            },
            // TODO: Call might not return, find out how to handle.
            .Call, .LongCall => {
                log.debug("CALL or LONGCALL, add location to search", .{});
            },
            .Halt, .Exit, .Ret => break,
            else => {},
        }
    }

    return null;
}

test "ProgramHeader size" {
    try std.testing.expectEqual(0x1C, @sizeOf(ProgramHeader));
}
