const std = @import("std");
const ArrayHelper = @import("arrayHelper.zig");

pub const Args = struct {
    args: ?[*:null]?[*:0]u8,
    len: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Args {
        return .{ .args = null, .len = 0, .allocator = allocator };
    }

    pub fn clear(self: *Args) void {
        if (self.args) |cArgs| {
            for (cArgs[0 .. self.len - 1]) |arg| {
                if (arg) |cArg| {
                    self.allocator.free(ArrayHelper.cStrToSliceSentinel(cArg));
                }
            }
            self.allocator.free(cArgs[0..self.len]);
            self.len = 0;
            self.args = null;
        }
    }

    pub fn add(self: *Args, arg: []u8) !void {
        if (self.args) |cArgs| {
            const newArgument = try self.allocator.dupeZ(u8, arg);
            errdefer self.allocator.free(newArgument);

            const newArgs = try self.allocator.alloc(?[*:0]u8, self.len + 1);

            for (0..self.len - 1) |j| {
                if (cArgs[j]) |cArg| {
                    newArgs[j] = cArg;
                }
            }

            newArgs[self.len - 1] = newArgument;
            newArgs[self.len] = null;

            self.allocator.free(cArgs[0..self.len]);

            self.args = newArgs[0..self.len :null];
            self.len += 1;
        } else {
            const newArgument = try self.allocator.dupeZ(u8, arg);
            errdefer self.allocator.free(newArgument);

            const newArgs = try self.allocator.alloc(?[*:0]u8, 2);

            newArgs[0] = newArgument;
            newArgs[1] = null;

            self.args = newArgs[0..1 :null];
            self.len = 2;
        }
    }

    pub fn print(self: *const Args) void {
        if (self.args) |cArgs| {
            std.debug.print("Args:\n", .{});
            for (0..self.len) |i| {
                if (cArgs[i]) |cArg| {
                    std.debug.print("{any}. {s}\n", .{ i, cArg });
                }
            }
        }
    }
};
