const std = @import("std");

pub const Args = struct {
    args: ?[*:null]?[*:0]u8,
    len: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Args {
        return .{ .args = null, .len = 0, .allocator = allocator };
    }

    pub fn clear(self: *const Args) void {
        if (self.args) |cArgs| {
            for (cArgs[0 .. self.len - 1]) |arg| {
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
            self.allocator.free(cArgs[0..self.len]);
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

    pub fn parse(self: *Args, buffer: []u8) !void {
        // FIXME: change this if mess, use switch or something with states.
        // Also I kind of hate how you need an extra check at the end.

        var start: u64 = 0;
        var quoteStarted: bool = false;

        for (0..buffer.len) |i| {
            if (!quoteStarted) {
                if (std.ascii.isWhitespace(buffer[i])) {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    start = i + 1;
                } else if (buffer[i] == '"') {
                    quoteStarted = true;
                    start = i + 1;
                }
            } else {
                if (buffer[i] == '"') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    quoteStarted = false;
                }
            }
        }

        if (!quoteStarted) {
            if (buffer.len - start >= 1) {
                try self.add(buffer[start..buffer.len]);
            }
        } else {
            return error.QuoteDidNotEnd;
        }
    }

    pub fn print(self: *const Args) void {
        for (0..self.len) |i| {
            if (self.args[i]) |cArg| {
                std.debug.print("{s}\n", .{cArg});
            }
        }
    }
};
