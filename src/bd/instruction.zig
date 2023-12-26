const std = @import("std");
const enums = std.enums;
const meta = std.meta;
const types = @import("types.zig");
const EndianStreamSource = @import("stream/stream.zig").EndianStreamSource;
const streamPosFromOffset = @import("stream/stream.zig").streamPosFromOffset;

pub const Instruction = union(enum) {
    Push: Push,
    Load: Load,
    Pop,
    Copy,
    Deref,
    UnaryOp,
    BinOp,
    Branch: Branch,
    Jump,
    Halt,
    Exit,
    Ret,
    Dup,
    Syscall: Syscall,
    Unknown,

    // TODO: Possibly split this into multiple decoder functions or use a comptime lookup table.
    pub fn decode(stream: *EndianStreamSource) (error{EndOfStream} || EndianStreamSource.ReadError)!DecodeResult {
        const code = try stream.readInt(u16);
        const bits: InstructionBits = @bitCast(code);

        const instruction: Instruction = switch (bits.group) {
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
                        3 => .Null,
                        4 => .{ .Register = .{ .reg = .gp, .offset = offset } },
                        else => break :blk .Unknown,
                    };

                    break :blk .{ .Push = .{ .mode = mode, .target = target } };
                },
            },
            // TODO: Parse additional information from the rest of these.
            1 => .Pop,
            // TODO: Copy immediate
            2 => .Unknown,
            3 => .Deref,
            4 => .Copy,
            7 => blk: {
                const offset = try stream.readInt(i16);
                const condition: Branch.Condition = switch (bits.immediate) {
                    0 => .none,
                    1 => .if_zero,
                    2 => .if_not_zero,
                    else => break :blk .Unknown,
                };
                break :blk .{ .Branch = .{ .condition = condition, .offset = offset } };
            },
            10 => blk: {
                const table = meta.intToEnum(Syscall.Table, bits.immediate) catch break :blk .Unknown;
                const index = try stream.readInt(u16);
                if (index >= table.len()) break :blk .Unknown;

                break :blk .{ .Syscall = .{
                    .table = table,
                    .index = index,
                } };
            },
            else => .Unknown,
        };

        return .{ .instruction = instruction, .code = code };
    }
};

pub const DecodeResult = struct {
    instruction: Instruction,
    code: u16,
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

pub const Branch = struct {
    condition: Condition,
    offset: i16,

    pub const Condition = enum {
        none,
        if_zero,
        if_not_zero,
    };

    pub inline fn computeTargetOffset(self: *const Branch, pc: u16) u16 {
        return @intCast(@as(i32, pc) + @as(i32, self.offset));
    }

    pub fn computeTargetPos(self: *const Branch, pc: u16) u64 {
        return streamPosFromOffset(self.computeTargetOffset(pc));
    }
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

const FormatContext = struct {
    instruction: Instruction,
    pc: u16,
};

fn formatInstruction(
    ctx: FormatContext,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    switch (ctx.instruction) {
        .Push => |p| try writer.print("PUSH mode={}, target={}", .{ p.mode, p.target }),
        .Load => |l| {
            try writer.writeAll("LOAD ");
            switch (l) {
                .Int => |i| try writer.print("{X}h", .{i}),
                .Float => |f| try writer.print("{}f", .{f}),
            }
        },
        .Pop => try writer.writeAll("POP ???"),
        .Branch => |b| {
            const name = switch (b.condition) {
                .none => "BRA",
                .if_zero => "BEZ",
                .if_not_zero => "BNZ",
            };

            try writer.print("{s} {X}h", .{ name, b.computeTargetPos(ctx.pc) });
        },
        .Syscall => |s| try writer.print("SYSCALL table={s} index={}", .{ enums.tagName(Syscall.Table, s.table).?, s.index }),
        else => try writer.writeAll("???"),
    }
}

pub fn fmtInstruction(instruction: Instruction, pc: u16) std.fmt.Formatter(formatInstruction) {
    return .{ .data = .{ .instruction = instruction, .pc = pc } };
}
