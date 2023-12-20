const EndianStreamSource = @import("stream/EndianStreamSource.zig");
const Instruction = @import("instruction.zig").Instruction;
const fmtInstruction = @import("instruction.zig").fmtInstruction;

pub const StreamError = EndianStreamSource.ReadError || EndianStreamSource.SeekError;

const syscall_tables_len = 11;
const syscall_table_sizes = [syscall_tables_len]usize{ 105, 368, 98, 0, 59, 35, 72, 37, 9, 0, 60 };

/// Stream should be at the search start position.
pub fn findPotentialSyscalls(stream: *EndianStreamSource, writer: anytype) (StreamError || @TypeOf(writer).Error)!void {
    while (true) {
        const decode_pos = try stream.getPos();
        const code = stream.readInt(u16) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const instruction = Instruction.decode(code, stream) catch |err| switch (err) {
            error.EndOfStream => {
                try stream.seekTo(decode_pos + @sizeOf(u16));
                continue;
            },
            else => |e| return e,
        };

        if (instruction) |i| {
            switch (i) {
                .Syscall => |s| {
                    if (s.table < syscall_tables_len and s.index < syscall_table_sizes[s.table]) {
                        try writer.print("Potential syscall: {X:0>8}: {X:0>4} = {}\n", .{ decode_pos, code, fmtInstruction(i) });
                    }
                },
                else => {},
            }
        } else {
            try stream.seekTo(decode_pos + @sizeOf(u16));
        }
    }
}
