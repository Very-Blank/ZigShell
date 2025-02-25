const std = @import("std");
const Args = @import("args.zig").Args;

pub const Operator = enum {
    pipe,
    rOverride,
    rAppend,
};

pub const Command = struct {
    args: Args,
    operator: ?Operator,
};

const ParseError = error{
    QuoteDidNotEnd,
    OutOfMemory,
};

const State = enum {
    normal,
    quote,
    fileName,
    end,
};

pub const CommandQueue = struct {
    commands: ?[]Command,
    allocator: std.mem.Allocator,

    pub fn parse(self: *CommandQueue, buffer: []u8) ParseError!void {
        // FIXME: change this if mess, use switch or something with states.
        // Also I kind of hate how you need an extra check at the end.

        var start: u64 = 0;
        var state: State = .normal;
        var quoteStarted: bool = false;
        // after getting file name it should be an error to put anything else than ;
        var file: bool = true;
        // var file: bool = true;

        for (0..buffer.len) |i| {
            switch (state) {
                .normal => {
                    switch (buffer[i]) {
                        std.ascii.whitespace => {
                            start = i + 1;
                        },
                        '"' => {
                            state = .quote;
                            start = i + 1;
                        },
                        ';' => {
                            if (i - start >= 1) {
                                try self.add(buffer[start..i]);
                            }
                            try self.new();
                            start = i + 1;
                        },
                        '>' => {},
                        '|' => {},
                    }
                },
                .qoute => {},
                .file => {},
                .end => {},
            }

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
                    if (i + 1 < buffer.len and buffer[i] == '>') {
                        try self.set(.rOverride);
                        // try self.new();
                        file = true;
                    } else {
                        try self.set(.rAppend);
                        // try self.new();
                        file = true;
                    }

                    start = i + 1;
                } else if (buffer[i] == '|') {
                    try self.set(.pipe);
                    try self.new();

                    start = i + 1;
                } else if (buffer[i] == ';') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }
                    try self.new();

                    start = i + 1;
                }
            } else if (quoteStarted) {
                if (buffer[i] == '"') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    start = i + 1;
                    quoteStarted = false;
                }
            } else if (file) {
                if (std.ascii.isWhitespace(buffer[i])) {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    start = i + 1;
                } else if (buffer[i] == ';') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }
                    try self.new();

                    start = i + 1;
                }
            }
        }

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
                    if (i + 1 < buffer.len and buffer[i] == '>') {
                        try self.set(.rOverride);
                        // try self.new();
                        file = true;
                    } else {
                        try self.set(.rAppend);
                        // try self.new();
                        file = true;
                    }

                    start = i + 1;
                } else if (buffer[i] == '|') {
                    try self.set(.pipe);
                    try self.new();

                    start = i + 1;
                } else if (buffer[i] == ';') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }
                    try self.new();

                    start = i + 1;
                }
            } else if (quoteStarted) {
                if (buffer[i] == '"') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    start = i + 1;
                    quoteStarted = false;
                }
            } else if (file) {
                if (std.ascii.isWhitespace(buffer[i])) {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }

                    start = i + 1;
                } else if (buffer[i] == ';') {
                    if (i - start >= 1) {
                        try self.add(buffer[start..i]);
                    }
                    try self.new();

                    start = i + 1;
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

        if (self.commands) |cCommands| {
            if (cCommands[cCommands.len - 1].operator != null) {
                return error.NoOperatorTarget;
            }
        }
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
            if (cCommands[cCommands.len - 1].operator == null) {
                if (cCommands[cCommands.len - 1].args.len > 1) {
                    cCommands[cCommands.len - 1].operator = operator;
                } else {
                    return error.NoArgs;
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
            newCommands[self.commands.len - 1] = .{ .args = Args.init(self.allocator), .operator = null };
            self.commands = newCommands;
        }
    }
};
