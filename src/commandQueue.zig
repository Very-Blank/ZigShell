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
    WrongStartState,
    QuoteDidNotEnd,
    OutOfMemory,
    NoOperatorTarget,
    NotNewCommandOperator,
    ExpectedFile,
    NoFile,
};

const State = enum {
    normal,
    quote,
    fileName,
    end,
};

pub const CommandQueue = struct {
    commands: ?[]Command,
    fileNames: ?std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    pub fn parse(self: *CommandQueue, buffer: []u8, state: State) ParseError!void {
        switch (state) {
            .end => return ParseError.WrongStartState,
            else => {},
        }

        var i: u64 = 0;
        var j: u64 = 0;
        while (j < buffer.len) : (j += 1) {
            switch (state) {
                .normal => {
                    switch (buffer[j]) {
                        std.ascii.whitespace, '"', ';', '>', '|' => {
                            if (j - i >= 1) {
                                try self.add(buffer[i..j]);
                            }

                            i = j + 1;
                        },
                        else => {},
                    }

                    switch (buffer[j]) {
                        '"' => {
                            state = .quote;
                        },
                        ';' => {
                            try self.new();
                        },
                        '>' => {
                            if (j + 1 < buffer.len and buffer[j + 1] == '>') {
                                j += 1;
                                i = j + 1;

                                try self.set(.rAppend);
                                state = .fileName;
                            } else {
                                try self.set(.rOverride);
                                state = .fileName;
                            }
                        },
                        '|' => {
                            try self.set(.pipe);
                            try self.new();
                        },
                        else => {},
                    }
                },
                .qoute => {
                    switch (buffer[j]) {
                        '"' => {
                            if (j - i >= 1) {
                                try self.add(buffer[i..j]);
                            }
                            i = j + 1;
                            try self.new();

                            state = .normal;
                        },
                        else => {},
                    }
                },
                .file => {
                    switch (buffer[j]) {
                        std.ascii.whitespace => {
                            if (j - i >= 1) {
                                if (self.fileNames) |cFileNames| {
                                    try cFileNames.append(try self.allocator.dupe([]u8, buffer[i..j]));
                                } else {
                                    const fileNames = std.ArrayList(u8).init(self.allocator);
                                    try fileNames.append(try self.allocator.dupe([]u8, buffer[i..j]));
                                    self.fileNames = fileNames;
                                }

                                state = .end;
                            }
                            i = j + 1;
                        },
                        '"', ';', '>', '|' => {
                            return ParseError.ExpectedFile;
                        },
                        else => {},
                    }
                },
                .end => {
                    switch (buffer[j]) {
                        std.ascii.whitespace => {},
                        ';' => {
                            self.new();
                            state = .normal;
                        },
                        else => return ParseError.NotNewCommandOperator,
                    }
                },
            }
        }

        switch (state) {
            .qoute => {
                return ParseError.QuoteDidNotEnd;
            },
            .file => {
                return ParseError.NoFile;
            },
            else => {},
        }

        if (self.commands) |cCommands| {
            if (cCommands[cCommands.len - 1].operator != null) {
                return ParseError.NoOperatorTarget;
            }
        }
    }

    pub fn clear(self: *CommandQueue) void {
        if (self.commands) |cCommands| {
            self.allocator.free(cCommands);
        }

        if (self.fileNames) |cFileNames| {
            for (cFileNames.items) |item| {
                self.allocator.free(item);
            }
            cFileNames.deinit();
            self.fileNames = null;
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
