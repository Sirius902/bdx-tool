const EndianStreamSource = @import("stream/EndianStreamSource.zig");
const Instruction = @import("instruction.zig").Instruction;
const fmtInstruction = @import("instruction.zig").fmtInstruction;
const streamPosToOffset = @import("stream/stream.zig").streamPosToOffset;

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
    while (true) {
        const pos = try stream.getPos();
        const res = Instruction.decode(stream) catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };

        const matches_filter = switch (res.instruction) {
            .Branch => config.branch,
            .Syscall => config.syscall,
            else => false,
        };

        if (matches_filter) {
            try writer.print("{X:0>8}: {X:0>4} = {}\n", .{
                pos,
                res.code,
                fmtInstruction(res.instruction, streamPosToOffset(try stream.getPos())),
            });
        }
    }
}
