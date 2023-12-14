const std = @import("std");
const bd = @import("bd/bd.zig");

comptime {
    std.testing.refAllDecls(@This());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    if (!args.skip()) return error.InvalidArgument;
    const bdx_path = try allocator.dupe(u8, args.next() orelse return error.InvalidArgument);
    defer allocator.free(bdx_path);

    var bdx_file = try std.fs.cwd().openFile(bdx_path, .{});
    defer bdx_file.close();

    var parser: bd.Parser = .{ .allocator = allocator, .stream = std.io.StreamSource{ .file = bdx_file } };
    var result = try parser.parse();
    switch (result) {
        .Program => |*p| {
            defer p.deinit();
            try output_disassembly(p);
        },
        .Error => |e| output_error(e),
    }
}

fn output_disassembly(program: *const bd.Program) std.fs.File.WriteError!void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("{s}\n", .{program.header.name()});

    try stdout.print("heap size:\t{X:0>8}\n", .{program.header.heap_size});
    try stdout.print("frames size:\t{X:0>8}\n", .{program.header.frames_size});
    try stdout.print("stack size:\t{X:0>8}\n\n", .{program.header.stack_size});

    try stdout.writeAll("functions");
    var iter = program.functions.iterator();
    while (iter.next()) |kv| {
        try stdout.print("\n{X:0>8}: {X:0>8}", .{ kv.key_ptr.*, bd.offsetToStreamPos(kv.value_ptr.*) });
    }
    try stdout.writeAll("\n\n");

    try stdout.writeAll("testing testing 123\n");
}

fn output_error(err: bd.Parser.Error) void {
    std.log.err("{}", .{err});
}
