const std = @import("std");
const Args = @import("args.zig").Args;
const InputReader = @import("inputReader.zig").InputReader;
const Environ = @import("environ.zig").Environ;

// TODO:
// add buildins! "cd" -> chdir(), to change process dir for the parent (shell),
// "help",
// "exit"

// TODO:
// maybe change to execvpeZ to execveZ and get the absolute path yourself?

pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.print("{any}\n", .{gpa.deinit()});
    const allocator = gpa.allocator();

    const stdout = std.io.getStdIn().writer();
    // var bw = std.io.bufferedWriter(stdout);

    _ = try stdout.write(" > ");
    // try bw.flush(); // don't forget to flush!

    var inputReader = InputReader.init(allocator);
    defer inputReader.clear();

    var args: Args = Args.init(allocator);
    defer args.clear();

    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    var delimeter: u8 = '\n';
    while (true) {
        try inputReader.read(delimeter);

        args.parse(
            if (inputReader.buffer) |cBuffer| cBuffer else return error.NoArguments,
        ) catch |err| {
            switch (err) {
                error.QuoteDidNotEnd => {
                    delimeter = '"';
                    continue;
                },
                else => return err,
            }
        };

        break;
    }

    args.print();

    const pid: std.os.linux.pid_t = @intCast(std.os.linux.fork());
    var status: u32 = 0;
    if (pid == 0) {
        // NOTE: ALSO HERE!!
        const errors = std.posix.execvpeZ(args.args.?[0].?, args.args.?, environ.variables);
        std.debug.print("{any}\n", .{errors});
    } else if (pid < 0) {
        return error.ForkFailed;
    } else {
        // NOTE: READ MORE OF THE MAN PAGES FOR THESE
        _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        while (!std.os.linux.W.IFEXITED(status) and !std.os.linux.W.IFSIGNALED(status)) {
            _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        }
    }
}
