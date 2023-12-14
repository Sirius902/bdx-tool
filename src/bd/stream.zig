pub fn offsetToStreamPos(offset: u32) u64 {
    return 0x10 + @sizeOf(u16) * @as(u64, offset);
}
