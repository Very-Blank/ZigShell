const std = @import("std");
const Args = @import("args.zig").Args;
const InputReader = @import("inputReader.zig").InputReader;
const Environ = @import("environ.zig").Environ;
const Executer = @import("executer.zig").Executer;

// TODO:
// maybe change to execvpeZ to execveZ and get the absolute path yourself?

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.print("{any}\n", .{gpa.deinit()});
    const allocator = gpa.allocator();

    const stdout = std.io.getStdIn().writer();

    var inputReader = InputReader.init(allocator);
    defer inputReader.clear();

    var args: Args = Args.init(allocator);
    defer args.clear();

    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    var executer: Executer = try Executer.init(allocator);
    defer executer.deinit();

    var delimeter: u8 = '\n';

    while (true) {
        _ = try stdout.write(" > ");
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

        //args.print();

        executer.executeArgs(&args, &environ) catch |err| {
            switch (err) {
                error.Exit, error.ChildExit => break,
                //Non fatal errors
                error.ArgsNull, error.InvalidPath, error.NoCommand, error.ArgsTooShort => {},
                else => return err,
            }
        };

        inputReader.clear();
        args.clear();
    }
}
