const std = @import("std");
const Args = @import("args.zig").Args;
const CommandQueue = @import("commandQueue.zig").CommandQueue;
const Operator = @import("args.zig").Operator;
const Environ = @import("environ.zig").Environ;
const stdinWriter = @import("stdinWriter.zig");

const Builtins = enum {
    exit,
    cd,
    help,
};

const ExecuteError = error{
    Exit,
    ChildExit,
    InvalidPath,
    ForkFailed,
    FailedToOpenFile,
    PipeFailed,
    Dup2Failed,
    OutOfMemory,
    PrintFailed,
};

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

    pub fn executeCommands(self: *const Executer, commandQueue: *const CommandQueue, environ: *const Environ, stdin: *const stdinWriter.StdinWriter) ExecuteError!void {
        var pipe: [2]std.posix.fd_t = .{ 0, 0 };
        var pid: std.posix.pid_t = 0;

        if (commandQueue.commands) |cCommands| {
            var i: u64 = 0;

            while (i < cCommands.items.len) : (i += 1) {
                const args: Args = cCommands.items[i];
                const lastOperator: Operator = if (i > 0) cCommands.items[i - 1].operator else Operator.none;

                // NOTE: Bug allert!
                std.debug.assert(args.args.items.len != 0);

                if (self.hashmap.get(args.args.items[0])) |builtin| {
                    switch (builtin) {
                        .exit => {
                            _ = stdin.write("Bye :(\n") catch return ExecuteError.PrintFailed;
                            return ExecuteError.Exit;
                        },
                        .cd => {
                            if (args.args.items.len != 2) {
                                _ = stdin.write("cd: Supplied too many args or too few args\n") catch return ExecuteError.PrintFailed;
                                return ExecuteError.InvalidPath;
                            }
                            std.posix.chdir(args.args.items[1]) catch {
                                _ = stdin.write("cd: Chdir returned an error, invalid path?\n") catch return ExecuteError.PrintFailed;
                                return ExecuteError.InvalidPath;
                            };

                            continue;
                        },
                        .help => {
                            _ = stdin.write(
                                \\Help {
                                \\  Usage: path arg1 arg2 ...
                                \\  Builtins: exit, cd and help.
                                \\  SIGINT: isn't handled yet, so it will also close the shell.
                                \\}
                            ++ "\n") catch return ExecuteError.PrintFailed;
                            continue;
                        },
                    }
                }

                if (args.operator == .pipe) {
                    pipe = std.posix.pipe() catch return ExecuteError.PipeFailed;
                }

                pid = @intCast(std.posix.fork() catch return ExecuteError.ForkFailed);

                if (pid == 0) {
                    if (lastOperator == .pipe) {
                        std.posix.dup2(pipe[0], std.posix.STDIN_FILENO) catch return ExecuteError.Dup2Failed;
                    }

                    if (args.operator == .pipe or lastOperator == .pipe) {
                        std.posix.close(pipe[0]); //close the output end
                    }

                    switch (args.operator) {
                        .pipe => {
                            std.posix.dup2(pipe[1], std.posix.STDOUT_FILENO) catch return ExecuteError.Dup2Failed;
                            std.posix.close(pipe[1]);
                        },
                        // Look at this sexy code, god damn.
                        // The token parsing was worth it!
                        // No guessing if we have a file!
                        .rOverride => |filename| {
                            const file = std.fs.cwd().createFile(filename, .{}) catch return ExecuteError.FailedToOpenFile;

                            std.posix.dup2(
                                file.handle,
                                std.posix.STDOUT_FILENO,
                            ) catch return ExecuteError.Dup2Failed;
                        },
                        // FIXME: change this so it actually appends
                        .rAppend => |filename| {
                            const file = std.fs.cwd().createFile(filename, .{}) catch return ExecuteError.FailedToOpenFile;

                            std.posix.dup2(
                                file.handle,
                                std.posix.STDOUT_FILENO,
                            ) catch return ExecuteError.Dup2Failed;
                        },
                        else => {},
                    }

                    const cArgs = try args.getCArgs();
                    defer cArgs.deinit();

                    const errors = std.posix.execvpeZ(cArgs.file, cArgs.argv, environ.variables);
                    _ = stdin.print("Execute error: {any}\n", .{errors}) catch return ExecuteError.PrintFailed;

                    return ExecuteError.ChildExit;
                } else if (pid < 0) {
                    return ExecuteError.ForkFailed;
                } else {
                    var wait: std.posix.WaitPidResult = std.posix.waitpid(pid, std.posix.W.UNTRACED);
                    while (!std.posix.W.IFEXITED(wait.status) and !std.posix.W.IFSIGNALED(wait.status)) {
                        wait = std.posix.waitpid(pid, std.posix.W.UNTRACED);
                    }

                    if (args.operator == .pipe) {
                        std.posix.close(pipe[1]);
                    } else if (lastOperator == .pipe) {
                        std.posix.close(pipe[0]);
                    }
                }
            }
        }
    }
};
