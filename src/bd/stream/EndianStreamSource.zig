const std = @import("std");
const StreamSource = std.io.StreamSource;
const Endian = std.builtin.Endian;
const endian = @import("../endian.zig");

const Self = @This();

stream: StreamSource,
endian: ?Endian,

pub const ReadError = StreamSource.ReadError;
pub const WriteError = StreamSource.WriteError;
pub const SeekError = StreamSource.SeekError;
pub const GetSeekPosError = StreamSource.GetSeekPosError;

pub const Reader = StreamSource.Reader;
pub const Writer = StreamSource.Writer;
pub const SeekableStream = StreamSource.SeekableStream;

pub fn read(self: *Self, dest: []u8) ReadError!usize {
    return self.stream.read(dest);
}

pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
    return self.stream.write(bytes);
}

pub fn seekTo(self: *Self, pos: u64) SeekError!void {
    try self.stream.seekTo(pos);
}

pub fn seekBy(self: *Self, amt: i64) SeekError!void {
    try self.stream.seekBy(amt);
}

pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
    return self.stream.getEndPos();
}

pub fn getPos(self: *Self) GetSeekPosError!u64 {
    return self.stream.getPos();
}

pub fn reader(self: *Self) Reader {
    return self.stream.reader();
}

pub fn writer(self: *Self) Writer {
    return self.stream.writer();
}

pub fn seekableStream(self: *Self) SeekableStream {
    return self.stream.seekableStream();
}

pub fn readInt(self: *Self, comptime T: type) (error{EndOfStream} || ReadError)!T {
    return try self.stream.reader().readInt(T, self.targetEndian());
}

pub fn readStruct(self: *Self, comptime T: type) (error{EndOfStream} || ReadError)!T {
    var t = try self.stream.reader().readStruct(T);
    endian.swapToEndian(T, &t, self.targetEndian());
    return t;
}

inline fn targetEndian(self: Self) Endian {
    return self.endian orelse endian.native;
}
