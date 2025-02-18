const std = @import("std");
const Args = @import("args.zig").Args;

const Operator = enum {
    none,
    pipe,
    rOverride,
    rAppend,
    seperate,
};

const Command = struct {
    args: Args,
    ///Operator after the args
    operator: Operator,
};

const ParseError = error{
    QuoteDidNotEnd,
    OutOfMemory,
};

pub const CommandQueue = struct {
    commands: ?[]Command,
    allocator: std.mem.Allocator,

    pub fn parse(self: *CommandQueue, buffer: []u8) ParseError!void {
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
                } else if (buffer[i] == '>') {
                    try self.set(.rAppend);
                    try self.new();

                    start = i + 1;
                } else if (buffer[i] == '|') {
                    try self.set(.pipe);
                    try self.new();

                    start = i + 1;
                } else if (buffer[i] == ';') {
                    try self.set(.seperate);
                    try self.new();

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
            return ParseError.QuoteDidNotEnd;
        }

        //Check here if the commands ended
        // if()
    }

    pub fn new(self: *CommandQueue) !void {
        if (self.commands) |cCommands| {
            const newCommands = try self.allocator.alloc(Command, self.commands.len);
            @memcpy(newCommands[0..self.commands.len], self.commands);

            newCommands[self.commands.len] = .{ .args = Args.init(self.allocator), .operator = Operator.none };

            self.allocator.free(cCommands);
            self.commands = newCommands;
        } else {
            return error.CommandsMissing;
        }
    }

    pub fn set(self: *CommandQueue, operator: Operator) !void {
        if (self.commands) |cCommands| {
            if (cCommands[cCommands.len - 1].operator == .none) {
                cCommands[cCommands.len - 1].operator = operator;
            } else if (cCommands[cCommands.len - 1].operator == .rAppend) {
                if (operator == .rAppend) {
                    cCommands[cCommands.len - 1].operator = .rOverride;
                } else {
                    return error.TriedSettingOperatorTwice;
                }
            } else {
                return error.TriedSettingOperatorTwice;
            }
        } else {
            return error.CommandsMissing;
        }
    }

    pub fn add(self: *CommandQueue, arg: []u8) !void {
        if (self.commands) |cCommands| {
            try cCommands[cCommands.len - 1].add(arg);
        } else {
            const newCommands = try self.allocator.alloc(Command, 1);
            newCommands[self.commands.len - 1] = .{ .args = Args.init(self.allocator), .operator = Operator.none };
            self.commands = newCommands;
        }
    }
};
