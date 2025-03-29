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

pub const ArgsQueue = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ArgsQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *const ArgsQueue) void {
        if (self.commands) |cCommands| {
            for (cCommands) |cArg| {
                cArg.deinit();
            }

            self.allocator.free(cCommands);
        }

        self.commands = null;
    }

    /// Char array -> Token array -> Args array
    pub fn parse(self: *const ArgsQueue, buffer: []u8) ![]Args {
        const tokens: []Token = try tokenize(buffer, self.allocator);
        defer self.allocator.free(tokens);
        return try parseTokens(tokens, self.allocator);
    }

    // Made this because it was too hard to just parse strings.
    // This will be slower, but much easier to define safe behaviour.
    /// Tokens will have pointers to buffer!
    pub fn tokenize(buffer: []u8, allocator: std.mem.Allocator) ![]Token {
        var tokens = std.ArrayList(Token).init(allocator);
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

                        if (j < buffer.len) continue :state .normal else break :state;
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
                            if (j - i >= 1) {
                                try tokens.append(Token{ .arg = buffer[i..j] });
                            }

                            break :state;
                        }
                    },
                }

                switch (buffer[j]) {
                    '"' => {
                        j += 1;
                        if (j < buffer.len) continue :state .quote else return error.TokenizeError;
                    },
                    ';' => {
                        try tokens.append(Token{ .operator = OperatorType.seperator });
                        j += 1;
                        if (j < buffer.len) continue :state .normal else break :state;
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

                        if (j < buffer.len) continue :state .normal else break :state;
                    },
                    else => {
                        j += 1;
                        if (j < buffer.len) continue :state .quote else return error.TokenizeError;
                    },
                }
            },
        }

        return tokens.toOwnedSlice();
    }

    pub fn parseTokens(tokens: []Token, allocator: std.mem.Allocator) ![]Args {
        var args: std.ArrayList(Args) = std.ArrayList(Args).init(allocator);
        errdefer args.deinit();

        var i: u64 = 0;
        switch (tokens[i]) {
            .arg => |arg| {
                try newArgsWithArg(&args, arg);
                i += 1;
            },
            else => return error.SyntaxError,
        }

        while (i < tokens.len) : (i += 1) {
            const currentToken: Token = tokens[i];
            const nextToken: ?Token = if (i + 1 < tokens.len) tokens[i + 1] else null;
            const thirdToken: ?Token = if (i + 2 < tokens.len) tokens[i + 2] else null;

            switch (currentToken) {
                .arg => |arg| {
                    try addArg(&args, arg);
                },
                .operator => |operator| {
                    switch (operator) {
                        .seperator => {
                            // NOTE: This way we don't end up with empty args!
                            //       Note that we don't set opperator here!
                            if (nextToken) |cNextToken| {
                                switch (cNextToken) {
                                    .arg => |arg| {
                                        try newArgsWithArg(&args, arg);

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
                                        try setArg(&args, Operator.pipe);
                                        try newArgsWithArg(&args, arg);

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
                                            .operator => |nextOperator| switch (nextOperator) {
                                                .rOverride => try setFileOperator(.rOverride, &args, cArg),
                                                .rAppend => try setFileOperator(.rAppend, &args, cArg),
                                                else => unreachable,
                                            },
                                            else => unreachable,
                                        }

                                        // NOTE: Horrible that we have to check the third token but we just have to.
                                        //       This is the most "clean" way to do this.
                                        if (thirdToken) |cThirdToken| {
                                            switch (cThirdToken) {
                                                .operator => |thirdOperator| switch (thirdOperator) {
                                                    .seperator => {},
                                                    else => return error.SyntaxError,
                                                },
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

        return args.toOwnedSlice();
    }

    pub fn setFileOperator(comptime T: OperatorType, args: *std.ArrayList(Args), arg: []u8) !void {
        const value = try args.allocator.alloc(u8, arg.len);
        @memcpy(value, arg);
        errdefer args.allocator.free(value);
        switch (T) {
            .rOverride => {
                try setArg(args, Operator{ .rOverride = value });
            },
            .rAppend => {
                try setArg(args, Operator{ .rAppend = value });
            },
            else => @compileError("OperatorType " ++ @typeName(T) ++ " is not supported"),
        }
    }

    pub fn setArg(args: *std.ArrayList(Args), operator: Operator) !void {
        std.debug.assert(args.items.len > 0);
        try args.items[args.items.len - 1].setOperator(operator);
    }

    pub fn newArgsWithArg(args: *std.ArrayList(Args), arg: []u8) !void {
        try args.append(Args.init(args.allocator));
        try addArg(args, arg);
    }

    pub fn addArg(args: *std.ArrayList(Args), arg: []u8) !void {
        std.debug.assert(args.items.len > 0);
        try args.items[args.items.len - 1].add(arg);
    }
};
