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

        return Args{ .args = newArgs[0..1 :null], .len = 2, .allocator = allocator };
    }

    pub fn deinit(self: *const Args) void {
        for (self.args[0 .. self.len - 1]) |arg| {
            if (arg) |cArg| {
                var i: u64 = 0;
                while (true) : (i += 1) {
                    if (cArg[i] == 0) {
                        break;
                    }
                }
                self.allocator.free(cArg[0 .. i + 1]);
            }
        }
        self.allocator.free(self.args[0..self.len]);
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

        self.args = newArgs[0..self.len :null];
        self.len += 1;
    }

    pub fn print(self: *Args) void {
        for (0..self.len) |i| {
            std.debug.print("{any}", .{self.args[i]});
        }
    }
};
