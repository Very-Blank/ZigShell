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
    commands: ?[]Args,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{ .commands = null, .allocator = allocator };
    }

    // Made this because it was too hard to just parse strings.
    // This will be slower, but much easier to define safe behaviour.
    /// Tokens will have pointers to buffer!
    pub fn tokenize(self: *CommandQueue, buffer: []u8) ![]Token {
        var tokens = std.ArrayList(Token).init(self.allocator);
        errdefer tokens.deinit();

        var i: u64 = 0;
        var j: u64 = 0;

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
        for (0..tokens.len) |i| {
            const currentToken: Token = tokens[i];
            const nextToken: ?Token = if (i + 1 < tokens.len) tokens[i] else null;
        }
    }
};
