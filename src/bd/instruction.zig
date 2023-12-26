const std = @import("std");
const enums = std.enums;
const meta = std.meta;
const types = @import("types.zig");
const EndianStreamSource = @import("stream/stream.zig").EndianStreamSource;
const streamPosFromOffset = @import("stream/stream.zig").streamPosFromOffset;

pub const Instruction = union(enum) {
    Load: Load,
    Push: Push,
    Pop: [1]u16,
    Memcpy: [2]u16,
    Deref: [1]u16,
    Copy,
    UnaryOp,
    BinOp,
    Branch: Branch,
    Call: Call,
    Halt,
    Exit,
    Ret,
    Drop,
    Dup,
    Syscall: Syscall,
    LongCall: LongCall,
    Invalid,

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
                        else => break :blk .Invalid,
                    };

                    break :blk .{ .Push = .{ .mode = mode, .target = target } };
                },
            },
            1 => .{ .Pop = [_]u16{try stream.readInt(u16)} },
            2 => .{ .Memcpy = [_]u16{ try stream.readInt(u16), try stream.readInt(u16) } },
            3 => .{ .Deref = [_]u16{try stream.readInt(u16)} },
            4 => .Copy,
            5 => .UnaryOp,
            6 => .BinOp,
            7 => blk: {
                const offset = try stream.readInt(i16);
                const condition: Branch.Condition = switch (bits.immediate) {
                    0 => .always,
                    1 => .if_zero,
                    2 => .if_not_zero,
                    else => break :blk .Invalid,
                };
                break :blk .{ .Branch = .{ .condition = condition, .offset = offset } };
            },
            8 => if (bits.flags == 0) .{ .Call = .{
                .frame_size = bits.immediate,
                .offset = try stream.readInt(i16),
            } } else .Invalid,
            9 => switch (bits.immediate) {
                0 => .Halt,
                1 => .Exit,
                2 => .Ret,
                3 => .Drop,
                5 => .Dup,
                // Sin
                6 => .UnaryOp,
                // Cos
                7 => .UnaryOp,
                // DegToRad
                8 => .UnaryOp,
                // RadToDeg
                9 => .UnaryOp,
                else => .Invalid,
            },
            10 => blk: {
                const table = meta.intToEnum(Syscall.Table, bits.immediate) catch break :blk .Invalid;
                const index = try stream.readInt(u16);
                if (index >= table.len()) break :blk .Invalid;

                break :blk .{ .Syscall = .{
                    .table = table,
                    .index = index,
                } };
            },
            11 => if (bits.flags == 0) .{ .LongCall = .{
                .frame_size = bits.immediate,
                .offset = @as(i32, try stream.readInt(u16)) + @as(i32, try stream.readInt(u16)) << 16,
            } } else .Invalid,
            else => .Invalid,
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
        always,
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

pub const Call = struct {
    frame_size: u10,
    offset: i16,

    pub inline fn computeTargetOffset(self: *const Call, pc: u16) u16 {
        return @intCast(@as(i32, pc) + @as(i32, self.offset));
    }

    pub fn computeTargetPos(self: *const Call, pc: u16) u64 {
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

pub const LongCall = struct {
    frame_size: u10,
    offset: i32,

    pub inline fn computeTargetOffset(self: *const LongCall, pc: u16) u16 {
        return @intCast(@as(i32, pc) + self.offset);
    }

    pub fn computeTargetPos(self: *const LongCall, pc: u16) u64 {
        return streamPosFromOffset(self.computeTargetOffset(pc));
    }
};

const FormatContext = struct {
    instruction: Instruction,
    code: u16,
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
        .Load => |l| {
            try writer.writeAll("LOAD");
            switch (l) {
                .Int => |i| try writer.print(".I 0x{X:0>8}", .{@as(u32, @bitCast(i))}),
                .Float => |f| try writer.print(".F {d}f", .{f}),
            }
        },
        .Push => |p| {
            try writer.writeAll("PUSH ");

            if (p.mode == .ref) {
                try writer.writeByte('&');
            }

            switch (p.target) {
                .Null => try writer.writeAll("null"),
                .Register => |r| try writer.print("{s}[{}]", .{ enums.tagName(PushRegister, r.reg).?, r.offset }),
            }
        },
        .Pop => |p| try writer.print("POP 0x{X:0>4}", .{p[0]}),
        .Memcpy => |m| try writer.print("MEMCPY {}, 0x{X:0>4}", .{ m[0], m[1] }),
        .Deref => |d| try writer.print("DEREF 0x{X:0>4}", .{d[0]}),
        .Copy => try writer.writeAll("COPY ???"),
        .UnaryOp => try writer.writeAll("UNARYOP ???"),
        .BinOp => try writer.writeAll("BINOP ???"),
        .Branch => |b| {
            const name = switch (b.condition) {
                .always => "BRA",
                .if_zero => "BEZ",
                .if_not_zero => "BNZ",
            };

            try writer.print("{s} 0x{X:0>8}", .{ name, b.computeTargetPos(ctx.pc) });
        },
        .Call => |c| try writer.print("CALL {}, 0x{X:0>8}", .{ c.frame_size, c.computeTargetPos(ctx.pc) }),
        .Halt => try writer.writeAll("HALT"),
        .Exit => try writer.writeAll("EXIT"),
        .Ret => try writer.writeAll("RET"),
        .Drop => try writer.writeAll("DROP"),
        .Dup => try writer.writeAll("DUP"),
        .Syscall => |s| try writer.print("SYSCALL table={s}, index={}", .{ enums.tagName(Syscall.Table, s.table).?, s.index }),
        .LongCall => |l| try writer.print("LONGCALL {}, 0x{X:0>8}", .{ l.frame_size, l.computeTargetPos(ctx.pc) }),
        .Invalid => try writer.print(".DW 0x{X:0>4}", .{ctx.code}),
    }
}

pub fn fmtInstruction(instruction: Instruction, code: u16, pc: u16) std.fmt.Formatter(formatInstruction) {
    return .{ .data = .{ .instruction = instruction, .code = code, .pc = pc } };
}
