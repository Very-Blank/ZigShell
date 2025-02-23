const std = @import("std");
const Args = @import("args.zig").Args;
const CommandQueue = @import("commandQueue.zig").CommandQueue;
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
};

pub const Executer = struct {
    hashmap: std.StringHashMap(Builtins),
    pub fn init(allocator: std.mem.Allocator) !Executer {
        var executer: Executer = .{ .hashmap = std.StringHashMap(Builtins).init(allocator) };
        errdefer executer.deinit();

        try executer.hashmap.put("exit", Builtins.exit);
        try executer.hashmap.put("cd", Builtins.cd);
        try executer.hashmap.put("help", Builtins.help);

        return executer;
    }

    pub fn deinit(self: *Executer) void {
        self.hashmap.deinit();
    }

    // This will not work you have to launch every command at the same time
    // For piping to work you have to keep track of the last pid before the one you lanched
    // Then you just connect use dup to take the stdout of the command before and connect that into the new commands stdin
    // pub fn executeCommands(self: *const Executer, commandQueue: *const CommandQueue, environ: *const Environ) void {
    //     var pipe: bool = false;
    //     if (commandQueue.commands) |cCommands| {
    //         for (cCommands) |command| {
    //             if (command.args.len <= 1) return error.ArgsTooShort;
    //
    //             const cArgs = if (command.args.args) |value| value else return error.ArgsNull;
    //             const cPath = if (command.cArgs[0]) |value| value else return error.NoCommand;
    //
    //             if (self.hashmap.get(ArrayHelper.cStrToSlice(command))) |builtin| {
    //                 switch (builtin) {
    //                     .exit => {
    //                         return error.Exit;
    //                     },
    //                     .cd => {
    //                         if (command.args.len != 3) return error.InvalidPath;
    //
    //                         const cfilePath = if (cArgs[1]) |value| value else return error.PathWasNull;
    //
    //                         std.posix.chdir(ArrayHelper.cStrToSlice(cfilePath)) catch return error.ChangeDirError;
    //
    //                         continue;
    //                     },
    //                     .help => {
    //                         // FIXME: add some help info
    //                         continue;
    //                     },
    //                     // else => unreachable,
    //                 }
    //             }
    //
    //             const pid: std.posix.pid_t = @intCast(std.posix.fork() catch return error.ForkFailed);
    //             if (pid == 0) {
    //                 if (command.operator == .pipe) {
    //                     pipe = true;
    //                     std.posix.dup2(
    //                         std.posix.STDIN_FILENO,
    //                         std.posix.STDOUT_FILENO,
    //                     ) catch return error.NoCommand;
    //                 }
    //                 if (command.operator == .rAppend or command.operator == .rOverride) {
    //                     const file = std.fs.cwd().createFile("pipe.txt", .{}) catch return error.NoCommand;
    //                     defer file.close();
    //
    //                     std.posix.dup2(
    //                         file.handle,
    //                         std.posix.STDOUT_FILENO,
    //                     ) catch return error.NoCommand;
    //                 }
    //
    //                 if (pipe) {
    //                     std.posix.dup2(
    //                         std.posix.STDOUT_FILENO,
    //                         std.posix.STDIN_FILENO,
    //                     ) catch return error.NoCommand;
    //                 }
    //
    //                 // NOTE: ALSO HERE!!
    //                 const errors = std.posix.execvpeZ(cPath, cArgs, environ.variables);
    //                 std.debug.print("{any}\n", .{errors});
    //                 return error.ChildExit;
    //                 // std.os.linux.exit(-1);
    //             } else if (pid < 0) {
    //                 return error.ForkFailed;
    //             } else {
    //                 // NOTE: READ MORE OF THE MAN PAGES FOR THESE
    //
    //                 var wait: std.posix.WaitPidResult = std.posix.waitpid(pid, std.posix.W.UNTRACED);
    //                 while (!std.posix.W.IFEXITED(wait.status) and !std.posix.W.IFSIGNALED(wait.status)) {
    //                     wait = std.posix.waitpid(pid, std.posix.W.UNTRACED);
    //                 }
    //             }
    //         }
    //     }
    // }

    pub fn executeArgs(self: *const Executer, args: *const Args, environ: *const Environ) ExecuteError!void {
        if (args.len <= 1) return error.ArgsTooShort;

        const cArgs = if (args.args) |value| value else return error.ArgsNull;
        const cCommand = if (cArgs[0]) |value| value else return error.NoCommand;

        if (self.hashmap.get(ArrayHelper.cStrToSlice(cCommand))) |builtin| {
            switch (builtin) {
                .exit => {
                    return error.Exit;
                },
                .cd => {
                    if (args.len != 3) return error.InvalidPath;

                    const cPath = if (cArgs[1]) |value| value else return error.PathWasNull;

                    std.posix.chdir(ArrayHelper.cStrToSlice(cPath)) catch return error.ChangeDirError;

                    return;
                },
                .help => {
                    // FIXME: add some help info
                    return;
                },
                // else => unreachable,
            }
        }

        const pid: std.posix.pid_t = @intCast(std.posix.fork() catch return error.ForkFailed);
        if (pid == 0) {
            const file = std.fs.cwd().createFile("pipe.txt", .{}) catch return error.NoCommand;
            defer file.close();

            std.posix.dup2(
                file.handle,
                std.posix.STDOUT_FILENO,
            ) catch return error.NoCommand;

            // NOTE: ALSO HERE!!
            const errors = std.posix.execvpeZ(cCommand, cArgs, environ.variables);
            std.debug.print("{any}\n", .{errors});
            return error.ChildExit;
            // std.os.linux.exit(-1);
        } else if (pid < 0) {
            return error.ForkFailed;
        } else {
            // NOTE: READ MORE OF THE MAN PAGES FOR THESE

            var wait: std.posix.WaitPidResult = std.posix.waitpid(pid, std.posix.W.UNTRACED);
            while (!std.posix.W.IFEXITED(wait.status) and !std.posix.W.IFSIGNALED(wait.status)) {
                wait = std.posix.waitpid(pid, std.posix.W.UNTRACED);
            }
        }
    }
};
