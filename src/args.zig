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
            .operator = Operator.none,
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
        errdefer self.allocator.free(value);
        @memcpy(value, arg);
        try self.args.append(value);
    }

    /// Expects that the operator owns the values memory.
    pub fn setOperator(self: *Args, operator: Operator) !void {
        if (self.operator == .none) {
            self.operator = operator;
        } else {
            return error.OperatorSetTwice;
        }
    }

    pub fn getCArgs(self: *const Args) !CArgs {
        return try CArgs.init(self);
    }
};

// I want to cry looking at this code :<
pub const CArgs = struct {
    file: [*:0]u8,
    fileLen: u64,
    argv: [*:null]?[*:0]u8,
    argvLen: u64,

    allocator: std.mem.Allocator,

    pub fn init(args: *const Args) !CArgs {
        std.debug.assert(args.args.items.len > 0);

        const file = try args.allocator.alloc(u8, args.args.items[0].len + 1);
        @memcpy(file[0 .. file.len - 1], args.args.items[0]);

        file[file.len - 1] = 0;

        const buffer: []?[*:0]u8 = try args.allocator.alloc(?[*:0]u8, args.args.items.len + 1);
        for (args.args.items, 0..) |cValue, i| {
            const value = try args.allocator.alloc(u8, cValue.len + 1);
            @memcpy(value[0..cValue.len], cValue);
            value[value.len - 1] = 0;
            buffer[i] = value[0..cValue.len :0];
        }

        buffer[buffer.len - 1] = null;

        return .{
            .file = file[0 .. file.len - 1 :0],
            .fileLen = file.len,
            .argv = buffer[0 .. buffer.len - 1 :null],
            .argvLen = buffer.len,
            .allocator = args.allocator,
        };
    }
    pub fn deinit(self: *const CArgs) void {
        for (0..self.argvLen) |i| {
            if (self.argv[i]) |cArg| {
                var j: u64 = 0;
                while (cArg[j] != 0) : (j += 1) {}
                self.allocator.free(cArg[0 .. j + 1]);
            }
        }

        self.allocator.free(self.argv[0..self.argvLen]);
        self.allocator.free(self.file[0..self.fileLen]);
    }
};
