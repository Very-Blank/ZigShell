const std = @import("std");
const Vector = @import("vector.zig");

pub const OperatorType = enum {
    none,
    pipe,
    rOverride,
    rAppend,
};

pub const Operator = union(OperatorType) {
    none,
    seperator,
    pipe,
    rOverride: []u8,
    rAppend: []u8,
};

pub const Args = struct {
    args: std.ArrayList([]u8),
    operator: Operator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Args {
        return .{
            .args = std.ArrayList([]u8).init(allocator),
            .operator = .{ .none = void },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Args) void {
        for (self.args.items) |cValue| {
            self.allocator.free(cValue);
        }

        self.args.deinit();

        switch (self.operator) {
            .rOverride, .rAppend => |cValue| {
                self.allocator.free(cValue);
            },
            else => {},
        }
    }

    /// Expects that the operator owns the values memory.
    pub fn setOperator(self: *Args, operator: Operator) !void {
        if (self.operator == .none) {
            self.operator = operator;
        } else {
            return error.SetOperatorTwice;
        }
    }

    pub fn toCArgs(self: *Args) ![:null]?[:0]u8 {
        const buffer = try self.allocator.alloc(?[:0]u8, self.args.items.len + 1);
        for (self.args.items, 0..) |cValue, i| {
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
