const std = @import("std");
const Vector = @import("vector.zig");

pub const Args = struct {
    list: [][]u8,
    buffer: [][]u8,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Args {
        const buffer = try allocator.alloc([]u8, 4);
        return .{
            .list = buffer[0..0],
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Args) void {
        for (self.list.len) |cValue| {
            self.allocator.free(cValue);
        }
    }

    pub fn add(self: *Args, value: []u8) !void {
        const copy: []u8 = try self.allocator.alloc(u8, self.value.len);
        @memcpy(copy, value);
        if (self.list.len < self.buffer.len) {
            self.list = self.buffer[0 .. self.list.len + 1];
            self.list[self.list.len - 1] = copy;
        } else {
            const buffer = try self.allocator.alloc([]u8, self.buffer.len * 2);
            @memcpy(buffer[0..self.buffer.len], self.buffer);
            self.allocator.free(self.buffer);

            self.buffer = buffer;
            // NOTE: values of list are invalid but the length should be okay?
            self.list = self.buffer[0 .. self.list.len + 1];
            self.list[self.list.len - 1] = copy;
        }
    }

    pub fn toCArgs(self: *Args) ![:null]?[:0]u8 {
        const buffer = try self.allocator.alloc(?[:0]u8, self.list.len + 1);
        for (self.list, 0..) |cValue, i| {
            const value = try self.allocator.alloc(u8, cValue.len + 1);
            @memcpy(value[0..cValue.len], cValue);
            buffer[i] = value[0..cValue.len :0];
        }

        return buffer[0..self.list.len :null];
    }

    pub fn freeArgs(cArgs: [:null]?[:0]u8, allocator: std.mem.Allocator) void {
        for (0..cArgs.len) |i| {
            if (cArgs[i]) |cArg| {
                allocator.free(cArg[0..cArg.len]);
            }
        }

        allocator.free(cArgs[0..cArgs.len]);
    }
};
