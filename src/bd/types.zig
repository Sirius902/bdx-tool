pub const Int = i32;
pub const Float = f32;

pub const Address = packed struct {
    hash: u32,
};

pub const Value = packed struct {
    data: Data,
    tag: Tag,
};

pub const Data = packed union {
    int: Int,
    float: Float,
    address: Address,
};

pub const Tag = enum(u32) {
    int = fromString("@INT"),
    float = fromString("@FLT"),
    address = fromString("@ADR"),
    userdata = fromString("@???"),

    fn fromString(string: *const [4]u8) u32 {
        return @bitCast(string.*);
    }
};
