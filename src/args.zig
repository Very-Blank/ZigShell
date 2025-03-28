const std = @import("std");

pub const OperatorType = enum {
    none,
    seperator,
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

    pub fn deinit(self: *const Args) void {
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

    pub fn add(self: *Args, arg: []u8) !void {
        const value = try self.allocator.alloc(u8, arg.len);
        @memcpy(value, arg);
        self.args.append(value);
    }

    /// Expects that the operator owns the values memory.
    pub fn setOperator(self: *Args, operator: Operator) !void {
        if (self.operator == .none) {
            self.operator = operator;
        } else {
            return error.OperatorSetTwice;
        }
    }

    pub fn getCArgs(self: *Args) !CArgs {
        return try CArgs.init(self);
    }
};

pub const CArgs = struct {
    file: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,

    allocator: std.mem.Allocator,

    pub fn init(args: *Args) !CArgs {
        const file = try args.allocator.alloc(u8, args.args.items[0].len + 1);
        // NOTE: that at least args.args.items[0] is guaranteed.
        // If this ever panics we have a bad bug in tokenizer!
        @memcpy(file[0 .. file.len - 1], args.args.items[0]);

        const buffer = try args.allocator.alloc(?[:0]u8, args.args.items.len + 1);
        for (args.args.items, 0..) |cValue, i| {
            const value = try args.allocator.alloc(u8, cValue.len + 1);
            @memcpy(value[0..cValue.len], cValue);
            buffer[i] = value[0..cValue.len :0];
        }

        return .{
            .file = file[0..file.len :0],
            .argv = buffer[0..args.list.len :null],
            .allocator = args.allocator,
        };
    }

    pub fn deinit(self: *const CArgs) void {
        for (0..self.argv.len) |i| {
            if (self.argv[i]) |cArg| {
                self.allocator.free(cArg[0..cArg.len]);
            }
        }

        self.allocator.free(self.argv[0..self.argv.len]);
        self.allocator.free(self.file[0..self.file.len]);
    }
};
