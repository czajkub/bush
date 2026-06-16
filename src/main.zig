const std = @import("std");
const bush = @import("tree-sitter-bush");
const env = bush.env;
const interp = bush.interpreter;
const ts = bush.ts;

extern fn tree_sitter_bush() callconv(.c) *ts.TSLanguage;

pub fn main(init: std.process.Init) void {
    const allocator = init.gpa;

    const args = init.minimal.args.toSlice(allocator) catch |err| {
        std.debug.print("Fatal: failed to allocate arguments: {any}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(args);

    var path: ?[]const u8 = null;
    var only_tree = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--tree")) {
            only_tree = true;
        } else if (path == null) {
            path = arg;
        } else {
            std.debug.print("Too many arguments\n", .{});
            std.process.exit(1);
        }
    }

    if (path == null) {
        if (only_tree) {
            std.debug.print("Usage: {s} [--tree] <file>\n", .{args[0]});
            std.process.exit(1);
        }
        bush.cli.repl(allocator, init.io, init.environ_map) catch |err| {
            std.debug.print("Fatal Error: {any}\n", .{err});
            std.process.exit(1);
        };
        return;
    }

    const source_code = read_file(allocator, init.io, path.?) catch {
        std.process.exit(1);
    };
    defer allocator.free(source_code);

    run(allocator, init.io, init.environ_map, path.?, source_code, only_tree) catch |err| {
        std.debug.print("Fatal Error: {any}\n", .{err});
        std.process.exit(1);
    };
}

fn run(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map, path: []const u8, source: []const u8, only_tree: bool) !void {
    const language = tree_sitter_bush();
    const parser = ts.ts_parser_new();
    defer ts.ts_parser_delete(parser);
    _ = ts.ts_parser_set_language(parser, language);

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len));
    defer ts.ts_tree_delete(tree);

    const root_node = ts.ts_tree_root_node(tree);
    
    if (only_tree) {
        std.debug.print("Parsed tree:\n", .{});
        print_node(root_node, 0, source);
        std.debug.print("\n", .{});
        return;
    }

    var global_env = env.Environment.init(allocator, null);
    defer global_env.deinit();

    var interpreter = try interp.Interpreter.init(allocator, source, &global_env, io, environ_map);
    _ = interpreter.eval(root_node) catch |err| {
        if (err != error.SyntaxError) {
            std.debug.print("Runtime Error: {any}\n", .{err});
        }
    };

    std.debug.print("\nFinal Global Environment:\n", .{});
    var it = global_env.variables.iterator();
    while (it.next()) |entry| {
        switch (entry.value_ptr.*) {
            .integer => |v| std.debug.print("{s} = {d}\n", .{ entry.key_ptr.*, v }),
            .string => |v| std.debug.print("{s} = \"{s}\"\n", .{ entry.key_ptr.*, v }),
            .float => |v| std.debug.print("{s} = {d}\n", .{ entry.key_ptr.*, v }),
            .boolean => |v| std.debug.print("{s} = {}\n", .{ entry.key_ptr.*, v }),
            .function => std.debug.print("{s} = <function>\n", .{entry.key_ptr.*}),
        }
    }
    _ = path;
}

fn read_file(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    const cwd = std.Io.Dir.cwd();
    return cwd.readFileAlloc(io, path, allocator, .unlimited) catch |err| {
        std.debug.print("Error opening file {s}: {any}\n", .{ path, err });
        return err;
    };
}

fn checkSyntax(io: std.Io, node: ts.TSNode, source: []const u8) void {
    _ = io;
    _ = node;
    _ = source;
}

fn print_node(node: ts.TSNode, indent: usize, source: []const u8) void {
    const kind = ts.ts_node_type(node);
    const is_named = ts.ts_node_is_named(node);

    var i: usize = 0;
    while (i < indent) : (i += 1) std.debug.print("  ", .{});

    const start = ts.ts_node_start_byte(node);
    const end = ts.ts_node_end_byte(node);
    const text = source[start..end];

    const child_count = ts.ts_node_child_count(node);
    if (child_count == 0) {
        // Leaf node
        if (is_named) {
            std.debug.print("({s} \"{s}\")\n", .{ kind, text });
        } else {
            // Print unnamed leaves (like operators) if they aren't just whitespace
            const trimmed = std.mem.trim(u8, text, " \t\n\r");
            if (trimmed.len > 0) {
                std.debug.print("\"{s}\"\n", .{trimmed});
            } else {
                // Remove the indentation we already printed if we're not printing anything
                std.debug.print("\r", .{});
            }
        }
    } else {
        // Internal node
        if (is_named) {
            std.debug.print("({s}\n", .{kind});
            var j: u32 = 0;
            while (j < child_count) : (j += 1) {
                print_node(ts.ts_node_child(node, j), indent + 1, source);
            }
            i = 0;
            while (i < indent) : (i += 1) std.debug.print("  ", .{});
            std.debug.print(")\n", .{});
        } else {
            // Unnamed internal node (rare, but just in case)
            var j: u32 = 0;
            while (j < child_count) : (j += 1) {
                print_node(ts.ts_node_child(node, j), indent, source);
            }
        }
    }
}
