const std = @import("std");

pub const Args = struct {
    args: [*:null]?[*:0]u8,
    len: u64,
    allocator: std.mem.Allocator,

    pub fn init(arg: []u8, allocator: std.mem.Allocator) !Args {
        const newArgument = try allocator.dupeZ(u8, arg);
        errdefer allocator.free(newArgument);

        const newArgs = try allocator.alloc(?[*:0]u8, 2);

        newArgs[0] = newArgument;
        newArgs[1] = null;

        return Args{ .args = newArgs[0..2 :null], .len = 2, .allocator = allocator };
    }

    pub fn deinit(self: *Args) void {
        for (0..self.len) |i| {
            if (self.args[i]) |arg| {
                self.allocator.free(arg);
            }
        }
        self.allocator.free(self.args);
    }

    pub fn addArg(self: *Args, arg: []u8) !void {
        const newArgument = try self.allocator.dupeZ(u8, arg);
        errdefer self.allocator.free(newArgument);

        const newArgs = try self.allocator.alloc(?[*:0]u8, self.len + 1);

        for (0..self.len - 1) |j| {
            if (self.args[j]) |cArg| {
                newArgs[j] = cArg;
            }
        }

        newArgs[self.len - 1] = newArgument;
        newArgs[self.len] = null;

        self.deinit();

        self.len += 1;
        self.args = newArgs[0..self.len :null];
    }

    pub fn print(self: *Args) void {
        for (0..self.len) |i| {
            std.debug.print("{any}", .{self.args[i]});
        }
    }
};
