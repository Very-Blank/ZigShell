const std = @import("std");
const Args = @import("args.zig").Args;
const OperatorType = @import("args.zig").OperatorType;
const Operator = @import("args.zig").Operator;

pub const TokenType = enum {
    arg,
    operator,
};

pub const Token = union(TokenType) {
    arg: []u8,
    operator: OperatorType,
};

const State = enum {
    normal,
    quote,
};

pub const CommandQueue = struct {
    commands: ?std.ArrayList(Args),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{ .commands = null, .allocator = allocator };
    }

    pub fn deinit(self: *CommandQueue) void {
        if (self.commands) |cCommands| {
            for (cCommands.items) |cArg| {
                cArg.deinit();
            }
        }

        self.commands = null;
    }

    // FIXME: add parse
    pub fn parse(buffer: []u8) void {}

    // Made this because it was too hard to just parse strings.
    // This will be slower, but much easier to define safe behaviour.
    /// Tokens will have pointers to buffer!
    pub fn tokenize(self: *CommandQueue, buffer: []u8) ![]Token {
        var tokens = std.ArrayList(Token).init(self.allocator);
        errdefer tokens.deinit();

        var i: u64 = 0;
        var j: u64 = 0;
        // NOTE: Although a labed swtich seem like a weird choice,
        //       it allows the code the be more thorough on what is allowed to happen next.
        state: switch (State.normal) {
            .normal => {
                switch (buffer[j]) {
                    // zig fmt: off
                    std.ascii.whitespace[0],
                    std.ascii.whitespace[1],
                    std.ascii.whitespace[2],
                    std.ascii.whitespace[3],
                    std.ascii.whitespace[4],
                    std.ascii.whitespace[5] => {
                    // zig fmt: on
                        if (j - i >= 1) {
                            try tokens.append(Token{ .arg = buffer[i..j] });
                        }

                        j += 1;
                        i = j;

                        if (j < buffer.len) continue :state .normal else return;
                    },
                    '"', ';', '>', '|' => {
                        if (j - i >= 1) {
                            try tokens.append(Token{ .arg = buffer[i..j] });
                        }

                        i = j + 1;
                    },
                    else => {
                        j += 1;
                        if (j < buffer.len) continue :state .normal else {
                            j -= 1;
                            if (j - i >= 1) {
                                try tokens.append(Token{ .arg = buffer[i..j] });
                            }

                            return;
                        }
                    },
                }

                switch (buffer[j]) {
                    '"' => {
                        j += 1;
                        if (j < buffer.len) continue :state .qoute else return error.TokenizeError;
                    },
                    ';' => {
                        try tokens.append(Token{ .operator = OperatorType.seperator });
                        j += 1;
                        if (j < buffer.len) continue :state .normal else return;
                    },
                    '>' => {
                        if (j + 1 < buffer.len and buffer[j + 1] == '>') {
                            try tokens.append(Token{ .operator = OperatorType.rAppend });

                            j += 2;
                            i = j;

                            if (j < buffer.len) continue :state .normal else return error.TokenizeError;
                        } else {
                            try tokens.append(Token{ .operator = OperatorType.rOverride });
                            j += 1;

                            if (j < buffer.len) continue :state .normal else return error.TokenizeError;
                        }
                    },
                    '|' => {
                        try tokens.append(Token{ .operator = OperatorType.pipe });

                        j += 1;
                        if (j < buffer.len) continue :state .normal else return error.TokenizeError;
                    },
                    else => unreachable,
                }
            },
            .quote => {
                if (buffer[j] == '"') {}
                switch (buffer[j]) {
                    '"' => {
                        if (j - i >= 1) {
                            try tokens.append(Token{ .arg = buffer[i..j] });
                        }

                        j += 1;
                        i = j;

                        if (j < buffer.len) continue :state .normal else return;
                    },
                    else => {
                        j += 1;
                        if (j < buffer.len) continue :state .qoute else return error.TokenizeError;
                    },
                }
            },
        }

        return tokens.toOwnedSlice();
    }

    pub fn parseTokens(self: *CommandQueue, tokens: []Token) !void {
        // If any error happens, commands are invalid!
        errdefer {
            self.deinit();
        }

        var i = 0;
        while (i < tokens.len) : (i += 1) {
            const currentToken: Token = tokens[i];
            const nextToken: ?Token = if (i + 1 < tokens.len) tokens[i + 1] else null;
            const thirdToken: ?Token = if (i + 2 < tokens.len) tokens[i + 2] else null;

            switch (currentToken) {
                .arg => |arg| {
                    try self.addArg(arg);
                },
                .operator => |operator| {
                    switch (operator) {
                        .seperator => {
                            // NOTE: This way we don't end up with empty args!
                            //       Note that we don't set opperator here!
                            if (nextToken) |cNextToken| {
                                switch (cNextToken) {
                                    .arg => |arg| {
                                        try self.newArg();
                                        try self.addArg(arg);

                                        i += 1;
                                        continue;
                                    },
                                    else => return error.SyntaxError,
                                }
                            } else {
                                return error.SyntaxError;
                            }
                        },
                        .pipe => {
                            if (nextToken) |cNextToken| {
                                switch (cNextToken) {
                                    .arg => |arg| {
                                        try self.setArg(Operator{ .pipe = void });
                                        try self.newArg();
                                        try self.addArg(arg);

                                        i += 1;
                                        continue;
                                    },
                                    else => return error.NoWhereToPipe,
                                }
                            } else {
                                return error.NoWhereToPipe;
                            }
                        },
                        .rOverride, .rAppend => {
                            if (nextToken) |cNextToken| {
                                switch (cNextToken) {
                                    .arg => |cArg| {
                                        switch (currentToken) {
                                            .rOverride => try setFileOperator(.rOverride, self, cArg),
                                            .rAppend => try setFileOperator(.rAppend, self, cArg),
                                            else => unreachable,
                                        }

                                        // NOTE: Horrible that we have to check the third token but we just have to.
                                        //       This is the most "clean" way to do this.
                                        if (thirdToken) |cThirdToken| {
                                            switch (cThirdToken) {
                                                .seperator => {},
                                                else => return error.SyntaxError,
                                            }
                                        }

                                        i += 1;
                                        continue;
                                    },
                                    else => return error.NoFile,
                                }
                            } else {
                                return error.NoFile;
                            }
                        },
                        else => unreachable, // NOTE: None would be a bug.
                    }
                },
            }
        }
    }

    pub fn setFileOperator(comptime T: OperatorType, self: *CommandQueue, arg: []u8) !void {
        const value = try self.allocator.alloc(u8, arg.len);
        @memcpy(value, arg);
        errdefer self.allocator.free(value);
        switch (T) {
            .rOverride => {
                try self.setArg(Operator{ .rOverride = value });
            },
            .rAppend => {
                try self.setArg(Operator{ .rAppend = value });
            },
            else => @compileError("OperatorType " ++ @typeName(T) ++ " is not supported"),
        }
    }

    pub fn setArg(self: *CommandQueue, operator: Operator) !void {
        if (self.commands) |cArgs| {
            try cArgs.items[cArgs.items.len].setOperator(operator);
        } else {
            return error.NoArgs;
        }
    }

    pub fn newArg(self: *CommandQueue) !void {
        if (self.commands) |cCommands| {
            try cCommands.items.append(Args.init(self.allocator));
        } else {
            const list = std.ArrayList(Args).init();
            self.commands = list;
        }
    }

    pub fn addArg(self: *CommandQueue, arg: []u8) !void {
        if (self.commands) |cCommands| {
            try cCommands.items[cCommands.items.len - 1].add(arg);
        } else {
            return error.NoCommands;
        }
    }
};
