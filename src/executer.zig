const std = @import("std");
const Args = @import("args.zig").Args;
const CommandQueue = @import("commandQueue.zig").CommandQueue;
const Operator = @import("commandQueue.zig").Operator;
const Command = @import("commandQueue.zig").Command;
const Environ = @import("environ.zig").Environ;
const ArrayHelper = @import("arrayHelper.zig");

const Builtins = enum {
    exit,
    cd,
    help,
};

const ExecuteError = error{
    Exit,
    ChildExit,
    ArgsNull,
    ArgsTooShort,
    NoCommand,
    InvalidPath,
    PathWasNull,
    ForkFailed,
    ChangeDirError,
    FailedToOpenFile,
    PipeFailed,
    Dup2Failed,
    MissingFileName,
    MissingFilesNames,
};

pub fn isPipe(pipe: ?Operator) bool {
    return if (pipe) |cPipe| return cPipe == .pipe else return false;
}

pub const Executer = struct {
    hashmap: std.StringHashMap(Builtins),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Executer {
        var executer: Executer = .{
            .hashmap = std.StringHashMap(Builtins).init(allocator),
            .allocator = allocator,
        };
        errdefer executer.deinit();

        try executer.hashmap.put("exit", Builtins.exit);
        try executer.hashmap.put("cd", Builtins.cd);
        try executer.hashmap.put("help", Builtins.help);

        return executer;
    }

    pub fn deinit(self: *Executer) void {
        self.hashmap.deinit();
    }

    pub fn executeCommands(self: *const Executer, commandQueue: *const CommandQueue, environ: *const Environ) ExecuteError!void {
        var lastOperator: ?Operator = null;
        var p: [2]std.posix.fd_t = .{ 0, 0 };
        var pid: std.posix.pid_t = 0;
        var fd_in: std.posix.fd_t = std.posix.STDIN_FILENO;
        var currentFile: u64 = 0;

        if (commandQueue.commands) |cCommands| {
            for (cCommands) |command| {
                if (command.args.len <= 1) continue;

                const cArgs: [*:null]?[*:0]u8 = if (command.args.args) |value| value else continue;
                const cPath = if (cArgs[0]) |value| value else continue;

                if (self.hashmap.get(ArrayHelper.cStrToSlice(cPath))) |builtin| {
                    switch (builtin) {
                        .exit => {
                            return error.Exit;
                        },
                        .cd => {
                            if (command.args.len != 3) return error.InvalidPath;

                            const cfilePath = if (cArgs[1]) |value| value else return error.PathWasNull;

                            std.posix.chdir(ArrayHelper.cStrToSlice(cfilePath)) catch return error.ChangeDirError;

                            continue;
                        },
                        .help => {
                            // FIXME: add some help info
                            continue;
                        },
                        // else => unreachable,
                    }
                }

                if (isPipe(command.operator) or isPipe(lastOperator)) {
                    p = std.posix.pipe() catch return error.PipeFailed;
                }

                pid = @intCast(std.posix.fork() catch return error.ForkFailed);

                if (pid == 0) {
                    if (isPipe(lastOperator)) {
                        std.posix.dup2(fd_in, std.posix.STDIN_FILENO) catch return error.Dup2Failed;
                    }

                    if (command.operator) |cOperator| {
                        switch (cOperator) {
                            .pipe => {
                                std.posix.dup2(p[1], std.posix.STDOUT_FILENO) catch return error.Dup2Failed;
                            },
                            .rOverride => {
                                if (commandQueue.fileNames) |cFileNames| {
                                    if (currentFile < cFileNames.items.len) {
                                        const file = std.fs.cwd().createFile(cFileNames.items[currentFile], .{}) catch return error.FailedToOpenFile;
                                        currentFile += 1;

                                        std.posix.dup2(
                                            file.handle,
                                            std.posix.STDOUT_FILENO,
                                        ) catch return error.Dup2Failed;
                                    } else {
                                        return error.MissingFileName;
                                    }
                                } else {
                                    return error.MissingFilesNames;
                                }
                            },
                            .rAppend => {
                                if (commandQueue.fileNames) |cFileNames| {
                                    if (currentFile < cFileNames.items.len) {
                                        const file = std.fs.cwd().createFile(cFileNames.items[currentFile], .{}) catch return error.FileDidNotExist;
                                        currentFile += 1;

                                        std.posix.dup2(
                                            file.handle,
                                            std.posix.STDOUT_FILENO,
                                        ) catch return error.Dup2Failed;
                                    } else {
                                        return error.MissingFileName;
                                    }
                                } else {
                                    return error.MissingFilesNames;
                                }
                            },
                        }
                    }

                    if (isPipe(command.operator) or isPipe(lastOperator)) {
                        std.posix.close(p[0]);
                    }

                    const errors = std.posix.execvpeZ(cPath, cArgs, environ.variables);
                    std.debug.print("{any}\n", .{errors});
                    return error.ChildExit;
                } else if (pid < 0) {
                    return error.ForkFailed;
                } else {
                    var wait: std.posix.WaitPidResult = std.posix.waitpid(pid, std.posix.W.UNTRACED);
                    while (!std.posix.W.IFEXITED(wait.status) and !std.posix.W.IFSIGNALED(wait.status)) {
                        wait = std.posix.waitpid(pid, std.posix.W.UNTRACED);
                    }

                    if (isPipe(command.operator) or isPipe(lastOperator)) {
                        std.posix.close(p[1]);
                        fd_in = p[0];
                    }

                    lastOperator = command.operator;
                }
            }
        }
    }
};
