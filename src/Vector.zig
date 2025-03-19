const std = @import("std");

//I know that std has an arraylist already just did this for practice
pub fn Vector(comptime T: type) type {
    return struct {
        /// List is with all of the add values
        list: []T,
        /// Buffer is the whole list with all of the capacity and with undefined values!
        buffer: []T,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            const buffer = try allocator.alloc(T, 4);
            return .{
                .list = buffer[0..0],
                .buffer = buffer,
                .allocator = allocator,
            };
        }

        pub fn deinit() void {}

        pub fn add(self: *Self, value: T) !void {
            if (self.list.len < self.buffer.len) {
                self.list = self.buffer[0 .. self.list.len + 1];
                self.list[self.list.len - 1] = value;
            } else {
                const buffer = try self.allocator.alloc(T, self.buffer.len * 2);
                @memcpy(buffer[0..self.buffer.len], self.buffer);
                self.allocator.free(self.buffer);

                self.buffer = buffer;
                // NOTE: values of list are invalid but the length should be okay?
                self.list = self.buffer[0 .. self.list.len + 1];
                self.list[self.list.len - 1] = value;
            }
        }

        pub fn toNullTerminatedSlice(self: *Self) ![:null]?[:0]u8 {
            switch (@typeInfo(T)) {
                .array => |array| {
                    if (array.child == []u8) {
                        const buffer = try self.allocator.alloc(?[:0]u8, self.list.len + 1);
                        for (self.list, 0..) |cValue, i| {
                            const value = try self.allocator.alloc(u8, cValue.len + 1);
                            @memcpy(value[0..cValue.len], cValue);
                            buffer[i] = value[0..cValue.len :0];
                        }

                        return buffer[0..self.list.len :null];
                    } else {
                        @compileError("Not implemented for type " ++ @typeName(T));
                    }
                },
                else => @compileError("Not implemented for type " ++ @typeName(T)),
            }
        }
    };
}
