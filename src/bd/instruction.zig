const std = @import("std");
const enums = std.enums;
const meta = std.meta;
const types = @import("types.zig");
const EndianStreamSource = @import("stream/stream.zig").EndianStreamSource;

pub const Instruction = union(enum) {
    Push: Push,
    Load: Load,
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
    Syscall: Syscall,

    // TODO: Possibly split this into multiple decoder functions or use a comptime lookup table.
    pub fn decode(code: u16, stream: *EndianStreamSource) (error{EndOfStream} || EndianStreamSource.ReadError)!?Instruction {
        const bits: InstructionBits = @bitCast(code);
        return switch (bits.group) {
            0 => switch (bits.flags) {
                0 => .{ .Load = .{ .Int = try stream.readInt(types.Int) } },
                1 => .{ .Load = .{ .Float = @bitCast(try stream.readInt(types.Int)) } },
                else => blk: {
                    const offset = try stream.readInt(u16);

                    const mode: Push.Mode = if ((bits.flags & 1) == 0) .ref else .deref;
                    const target: PushTarget = switch (bits.immediate) {
                        0 => .{ .Register = .{ .reg = .fp, .offset = offset } },
                        1 => .{ .Register = .{ .reg = .hp, .offset = offset } },
                        2 => .{ .Register = .{ .reg = .fp0, .offset = offset } },
                        3 => .{ .Null = {} },
                        4 => .{ .Register = .{ .reg = .gp, .offset = offset } },
                        else => return null,
                    };

                    break :blk .{ .Push = .{ .mode = mode, .target = target } };
                },
            },
            // TODO: Parse additional information from the rest of these.
            1 => .Pop,
            // TODO: Copy immediate
            2 => null,
            3 => .Deref,
            4 => .Copy,
            10 => blk: {
                const table = meta.intToEnum(Syscall.Table, bits.immediate) catch return null;
                const index = try stream.readInt(u16);
                if (index >= table.len()) return null;

                break :blk .{ .Syscall = .{
                    .table = table,
                    .index = index,
                } };
            },
            else => null,
        };
    }
};

pub const InstructionBits = packed struct {
    group: u4,
    flags: u2,
    immediate: u10,
};

pub const Register = enum {
    hp,
    fp,
    sp,
    gp,
};

pub const PushRegister = enum {
    fp,
    hp,
    fp0,
    gp,
};

pub const PushRegisterTarget = struct {
    reg: PushRegister,
    offset: u16,
};

pub const PushTarget = union(enum) {
    Register: PushRegisterTarget,
    Null,
};

pub const Push = struct {
    mode: Mode,
    target: PushTarget,

    pub const Mode = enum {
        deref,
        ref,
    };
};

pub const Load = union(enum) {
    Int: types.Int,
    Float: types.Float,
};

pub const Syscall = struct {
    table: Table,
    index: u16,

    pub const Table = enum(u10) {
        system = 0,
        field = 1,
        battle = 2,
        event = 4,
        table5 = 5,
        table6 = 6,
        table7 = 7,
        table8 = 8,
        table10 = 10,

        pub const count = @intFromEnum(.table10) + 1;

        pub fn len(self: Table) usize {
            return switch (self) {
                .system => 105,
                .field => 368,
                .battle => 98,
                .event => 59,
                .table5 => 35,
                .table6 => 72,
                .table7 => 37,
                .table8 => 9,
                .table10 => 60,
            };
        }
    };
};

fn formatInstruction(
    instruction: Instruction,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    switch (instruction) {
        .Push => |p| try writer.print("PUSH mode={}, target={}", .{ p.mode, p.target }),
        .Load => |l| {
            try writer.writeAll("LOAD ");
            switch (l) {
                .Int => |i| try writer.print("{X:}h", .{i}),
                .Float => |f| try writer.print("{}f", .{f}),
            }
        },
        .Pop => try writer.writeAll("POP ???"),
        .Syscall => |s| try writer.print("SYSCALL table={s} index={}", .{ enums.tagName(Syscall.Table, s.table).?, s.index }),
        else => try writer.writeAll("???"),
    }
}

pub fn fmtInstruction(instruction: Instruction) std.fmt.Formatter(formatInstruction) {
    return .{ .data = instruction };
}
