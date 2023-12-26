const EndianStreamSource = @import("stream/EndianStreamSource.zig");
const Instruction = @import("instruction.zig").Instruction;
const fmtInstruction = @import("instruction.zig").fmtInstruction;
const offsetFromStreamPos = @import("stream/stream.zig").offsetFromStreamPos;

pub const StreamError = EndianStreamSource.ReadError || EndianStreamSource.SeekError;

pub const Config = struct {
    branch: bool = false,
    syscall: bool = false,
};

/// `stream` should be at the search start position.
pub fn findPotentialInstructions(
    stream: *EndianStreamSource,
    writer: anytype,
    config: Config,
) (StreamError || @TypeOf(writer).Error)!void {
    const end_pos = try stream.getEndPos();

    while (true) {
        const pos = try stream.getPos();
        const res = Instruction.decode(stream) catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };

        const pc_pos = try stream.getPos();
        const pc = offsetFromStreamPos(pc_pos);

        const matches_filter = switch (res.instruction) {
            .Load => true,
            .Branch => |b| config.branch and b.computeTargetPos(pc) < end_pos,
            .Syscall => config.syscall,
            else => false,
        };

        if (!matches_filter) continue;

        try writer.print("{X:0>8}: {X:0>4} = {}\n", .{
            pos,
            res.code,
            fmtInstruction(res.instruction, res.code, pc),
        });
    }
}
