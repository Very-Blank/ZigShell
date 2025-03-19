const std = @import("std");
const Args = @import("args.zig").Args;

pub const OperatorType = enum {
    none,
    pipe,
    rOverride,
    rAppend,
};

pub const Operator = union(OperatorType) {
    none,
    pipe,
    rOverride: []u8,
    rAppend: []u8,
};

pub const Command = struct {
    args: Args,
    operator: Operator,
};

const ParseError = error{
    WrongStartState,
    QuoteDidNotEnd,
    OutOfMemory,
    NoOperatorTarget,
    NotNewCommandOperator,
    ExpectedFile,
    NoFile,
    AddFailed,
    NewFailed,
    SetFailed,
};

const State = enum {
    normal,
    quote,
    fileName,
    end,
};

// FIXME: DON'T MAKE NEW COMMAND BEFORE THE FILE NAME LEADS TO BUGs!
pub const CommandQueue = struct {
    commands: ?[]Command,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandQueue {
        return .{ .commands = null, .allocator = allocator };
    }

    pub fn parse(self: *CommandQueue, buffer: []u8, sState: State) ParseError!void {
        var state = sState;
        switch (state) {
            .end => return ParseError.WrongStartState,
            else => {},
        }

        // FIXME: change to labeled swtich?
        var i: u64 = 0;
        var j: u64 = 0;
        while (j < buffer.len) : (j += 1) {
            switch (state) {
                .normal => {
                    switch (buffer[j]) {
                        std.ascii.whitespace[0], std.ascii.whitespace[1], std.ascii.whitespace[2], std.ascii.whitespace[3], std.ascii.whitespace[4], std.ascii.whitespace[5], '"', ';', '>', '|' => {
                            if (j - i >= 1) {
                                self.add(buffer[i..j]) catch return ParseError.AddFailed;
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
                            self.new() catch return ParseError.NewFailed;
                        },
                        '>' => {
                            if (j + 1 < buffer.len and buffer[j + 1] == '>') {
                                j += 1;
                                i = j + 1;

                                self.set(.rOverride) catch return ParseError.SetFailed;
                                state = .fileName;
                            } else {
                                self.set(.rAppend) catch return ParseError.SetFailed;
                                state = .fileName;
                            }
                        },
                        '|' => {
                            self.set(.pipe) catch return ParseError.SetFailed;
                            self.new() catch return ParseError.NewFailed;
                        },
                        else => {},
                    }
                },
                .quote => {
                    switch (buffer[j]) {
                        '"' => {
                            if (j - i >= 1) {
                                self.add(buffer[i..j]) catch return ParseError.AddFailed;
                            }
                            i = j + 1;
                            self.new() catch return ParseError.NewFailed;

                            state = .normal;
                        },
                        else => {},
                    }
                },
                .fileName => {
                    switch (buffer[j]) {
                        std.ascii.whitespace[0], std.ascii.whitespace[1], std.ascii.whitespace[2], std.ascii.whitespace[3], std.ascii.whitespace[4], std.ascii.whitespace[5] => {
                            if (j - i >= 1) {
                                if (self.fileNames) |*cFileNames| {
                                    cFileNames.append(self.allocator.dupe(u8, buffer[i..j]) catch return ParseError.OutOfMemory) catch return ParseError.OutOfMemory;
                                } else {
                                    var fileNames = std.ArrayList([]u8).init(self.allocator);
                                    fileNames.append(self.allocator.dupe(u8, buffer[i..j]) catch return ParseError.OutOfMemory) catch return ParseError.OutOfMemory;
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
                        std.ascii.whitespace[0], std.ascii.whitespace[1], std.ascii.whitespace[2], std.ascii.whitespace[3], std.ascii.whitespace[4], std.ascii.whitespace[5] => {},
                        ';' => {
                            self.new() catch return ParseError.NewFailed;
                            state = .normal;
                        },
                        else => return ParseError.NotNewCommandOperator,
                    }
                },
            }
        }

        switch (state) {
            .quote => {
                return ParseError.QuoteDidNotEnd;
            },
            .fileName => {
                if (j - i >= 1) {
                    if (self.fileNames) |*cFileNames| {
                        cFileNames.append(self.allocator.dupe(u8, buffer[i..j]) catch return ParseError.OutOfMemory) catch return ParseError.OutOfMemory;
                    } else {
                        var fileNames = std.ArrayList([]u8).init(self.allocator);
                        fileNames.append(self.allocator.dupe(u8, buffer[i..j]) catch return ParseError.OutOfMemory) catch return ParseError.OutOfMemory;
                        self.fileNames = fileNames;
                    }

                    state = .end;
                } else {
                    return ParseError.NoFile;
                }
            },
            else => {
                if (j - i >= 1) {
                    self.add(buffer[i..j]) catch return ParseError.AddFailed;
                }

                i = j + 1;
            },
        }

        if (self.commands) |cCommands| {
            if (cCommands.len >= 2 and cCommands[cCommands.len - 1].args.args == null) {
                if (cCommands[cCommands.len - 2].operator) |cOperator| {
                    if (cOperator == Operator.pipe) {
                        return ParseError.NoOperatorTarget;
                    }
                }
            } else {
                if (cCommands[cCommands.len - 1].operator) |cOperator| {
                    if (cOperator == Operator.pipe) {
                        return ParseError.NoOperatorTarget;
                    }
                }
            }
        }
    }

    pub fn clear(self: *CommandQueue) void {
        if (self.commands) |cCommands| {
            for (cCommands) |*cCommand| {
                cCommand.args.clear();
            }

            self.allocator.free(cCommands);
            self.commands = null;
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
            const newCommands = try self.allocator.alloc(Command, cCommands.len + 1);
            @memcpy(newCommands[0..cCommands.len], cCommands);

            newCommands[cCommands.len] = .{ .args = Args.init(self.allocator), .operator = null };

            self.allocator.free(cCommands);
            self.commands = newCommands;
        } else {
            return error.CommandsMissing;
        }
    }

    pub fn set(self: *CommandQueue, operator: Operator) !void {
        if (self.commands) |cCommands| {
            if (cCommands[cCommands.len - 1].operator == null) {
                if (cCommands[cCommands.len - 1].args.len >= 1) {
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
            try cCommands[cCommands.len - 1].args.add(arg);
        } else {
            const newCommands = try self.allocator.alloc(Command, 1);
            errdefer self.allocator.free(newCommands);
            newCommands[0] = .{ .args = Args.init(self.allocator), .operator = null };
            try newCommands[0].args.add(arg);
            self.commands = newCommands;
        }
    }
};
