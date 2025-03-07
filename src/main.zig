const std = @import("std");
const CommandQueue = @import("commandQueue.zig").CommandQueue;
const InputReader = @import("inputReader.zig").InputReader;
const Environ = @import("environ.zig").Environ;
const Executer = @import("executer.zig").Executer;

// TODO:
// maybe change to execvpeZ to execveZ and get the absolute path yourself?

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    defer std.debug.print("{any}\n", .{debug_allocator.deinit()});
    const allocator = debug_allocator.allocator();

    const stdout = std.io.getStdIn().writer();

    var inputReader = InputReader.init(allocator);
    defer inputReader.clear();

    var commandQueue: CommandQueue = CommandQueue.init(allocator);
    defer commandQueue.clear();

    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    var executer: Executer = try Executer.init(allocator);
    defer executer.deinit();

    var delimeter: u8 = '\n';

    while (true) {
        _ = try stdout.write(" > ");
        while (true) {
            try inputReader.read(delimeter);

            commandQueue.parse(if (inputReader.buffer) |cBuffer| cBuffer else return error.NoArguments, .normal) catch |err| {
                switch (err) {
                    error.QuoteDidNotEnd => {
                        delimeter = '"';
                        inputReader.clear();
                        continue;
                    },
                    else => return err,
                }
            };

            break;
        }

        //args.print();

        executer.executeCommands(&commandQueue, &environ) catch |err| {
            switch (err) {
                error.Exit, error.ChildExit => break,
                //Non fatal errors
                error.InvalidPath => _ = try stdout.write("cd: Path was invalid\n"),
                error.ChangeDirError => _ = try stdout.write("cd: Path was incorrect\n"),
                error.ArgsNull, error.NoCommand, error.ArgsTooShort => {},
                //
                else => return err,
            }
        };

        inputReader.clear();
        commandQueue.clear();
    }
}
