const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Endian = std.builtin.Endian;
const StreamSource = std.io.StreamSource;

const endian = @import("endian.zig");
const log = @import("log.zig");
const Program = @import("program.zig").Program;
const ProgramHeader = @import("program.zig").ProgramHeader;

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

pub const ReadError = error{EndOfStream} || StreamSource.ReadError;

pub fn parse(self: *Self) (Allocator.Error || ReadError)!Result {
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

    return .{ .Program = program };
}

pub fn parseProgram(self: *Self, program: *Program) (Allocator.Error || ReadError)!?Error {
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

fn readInt(self: *Self, comptime T: type) ReadError!T {
    return try self.stream.reader().readInt(T, self.targetEndian());
}

fn readStruct(self: *Self, comptime T: type) ReadError!T {
    var t = try self.stream.reader().readStruct(T);
    endian.swapToEndian(T, &t, self.targetEndian());
    return t;
}

test "ProgramHeader size" {
    try std.testing.expectEqual(0x1C, @sizeOf(ProgramHeader));
}
