const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Endian = std.builtin.Endian;
const StreamSource = std.io.StreamSource;

const native_endian = @import("builtin").cpu.arch.endian();

const log = std.log.scoped(.bd);

pub const Value = packed struct {
    data: Data,
    tag: Tag,
};

pub const Data = packed union {
    int: Int,
    float: Float,
    address: Address,
};

pub const Tag = enum(u32) {
    int = fromString("@INT"),
    float = fromString("@FLT"),
    address = fromString("@ADR"),
    userdata = fromString("@???"),

    fn fromString(string: *const [4]u8) u32 {
        return @bitCast(string.*);
    }
};

pub const Int = i32;
pub const Float = f32;

pub const Address = packed struct {
    hash: u32,
};

pub const ProgramHeader = extern struct {
    name_bytes: [0x10]u8,
    heap_size: u32,
    frames_size: u32,
    stack_size: u32,

    pub fn name(self: *const ProgramHeader) []const u8 {
        const end = mem.indexOfScalarPos(u8, &self.name_bytes, 0, 0) orelse self.name_bytes.len;
        return self.name_bytes[0..end];
    }
};

pub const FunctionEntry = packed struct {
    id: u32,
    address: u32,
};

pub const Program = struct {
    header: ProgramHeader,
    functions: std.AutoArrayHashMap(u32, u32),

    pub fn deinit(self: *Program) void {
        self.functions.deinit();
    }
};

pub const ParseError = union(enum) {
    DuplicateFunctionId: struct { id: u32 },
};

pub const ParseResult = union(enum) {
    Program: Program,
    Error: ParseError,
};

pub const ReadError = error{EndOfStream} || StreamSource.ReadError;

pub const Parser = struct {
    allocator: Allocator,
    stream: StreamSource,
    endian: ?Endian = null,

    pub fn parse(self: *Parser) (Allocator.Error || ReadError)!ParseResult {
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

    pub fn parseProgram(self: *Parser, program: *Program) (Allocator.Error || ReadError)!?ParseError {
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

    fn readInt(self: *Parser, comptime T: type) ReadError!T {
        return try self.stream.reader().readInt(T, self.endian orelse native_endian);
    }

    fn readStruct(self: *Parser, comptime T: type) ReadError!T {
        var t = try self.stream.reader().readStruct(T);
        self.swapIfNecessary(T, &t);
        return t;
    }

    fn swapIfNecessary(self: *Parser, comptime S: type, s: *S) void {
        if (self.endian != null and self.endian != native_endian) byteSwap(S, s);
    }

    fn byteSwap(comptime S: type, ptr: *S) void {
        switch (@typeInfo(S)) {
            .Struct => |Struct| {
                inline for (Struct.fields) |f| {
                    byteSwap(f.type, &@field(ptr, f.name));
                }
            },
            .Array => |Array| {
                inline for (ptr) |*n| {
                    byteSwap(Array.child, n);
                }
            },
            else => ptr.* = @byteSwap(ptr.*),
        }
    }
};

test "ProgramHeader size" {
    try std.testing.expectEqual(0x1C, @sizeOf(ProgramHeader));
}
