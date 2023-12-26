const std = @import("std");
const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;
const bd = @import("bd/bd.zig");

comptime {
    std.testing.refAllDecls(@This());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try Args.parse(allocator);
    defer args.deinit();

    var bdx_file = try std.fs.cwd().openFile(args.bdx_path, .{});
    defer bdx_file.close();

    var parser: bd.Parser = .{
        .allocator = allocator,
        .stream = bd.EndianStreamSource{
            .stream = std.io.StreamSource{ .file = bdx_file },
            .endian = args.endian,
        },
    };

    var result = try parser.parse();
    switch (result) {
        .Program => |*p| {
            defer p.deinit();
            try output_disassembly(p);

            const function_table_size = (2 * @sizeOf(u32)) * (p.functions.count() + 1);
            try parser.stream.seekTo(@sizeOf(bd.ProgramHeader) + function_table_size);
            const writer = std.io.getStdOut().writer();
            try writer.writeAll("potential instruction finder\n");
            try bd.experimental.findPotentialInstructions(
                &parser.stream,
                writer,
                .{ .branch = true, .syscall = true },
            );
        },
        .Error => |e| output_error(e),
    }
}

const Args = struct {
    allocator: Allocator,
    bdx_path: []const u8,
    endian: ?Endian,

    pub const Error = error{InvalidArgument};

    pub fn parse(allocator: Allocator) (Error || Allocator.Error)!Args {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        if (!args.skip()) return error.InvalidArgument;
        const bdx_path = try allocator.dupe(u8, args.next() orelse return error.InvalidArgument);
        errdefer allocator.free(bdx_path);

        var endian: ?Endian = null;
        if (args.next()) |endian_str| {
            if (std.mem.eql(u8, endian_str, "b")) {
                endian = .big;
            } else if (std.mem.eql(u8, endian_str, "l")) {
                endian = .little;
            } else {
                return error.InvalidArgument;
            }
        }

        return .{ .allocator = allocator, .bdx_path = bdx_path, .endian = endian };
    }

    pub fn deinit(self: *const Args) void {
        self.allocator.free(self.bdx_path);
    }
};

fn output_disassembly(program: *const bd.Program) std.fs.File.WriteError!void {
    const writer = std.io.getStdOut().writer();

    try writer.print("{s}\n", .{program.header.name()});

    try writer.print("heap size:\t{X:0>8}\n", .{program.header.heap_size});
    try writer.print("frames size:\t{X:0>8}\n", .{program.header.frames_size});
    try writer.print("stack size:\t{X:0>8}\n\n", .{program.header.stack_size});

    try writer.writeAll("functions");
    var iter = program.functions.iterator();
    while (iter.next()) |kv| {
        try writer.print("\n{X:0>8}: {X:0>8}", .{ kv.key_ptr.*, bd.streamPosFromOffset(kv.value_ptr.*) });
    }
    try writer.writeAll("\n\n");

    // TODO: Output disassembled instructions.
}

fn output_error(err: bd.Parser.Error) void {
    std.log.err("{}", .{err});
}
