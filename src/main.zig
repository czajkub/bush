const std = @import("std");
const bush = @import("tree-sitter-bush");
const env = bush.env;
const interp = bush.interpreter;
const ts = bush.ts;

extern fn tree_sitter_bush() callconv(.c) *ts.TSLanguage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <file>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const path = args[1];
    const source_code = try read_file(allocator, path);
    defer allocator.free(source_code);

    try run(allocator, path, source_code);
}

fn run(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !void {
    const language = tree_sitter_bush();
    const parser = ts.ts_parser_new();
    defer ts.ts_parser_delete(parser);
    _ = ts.ts_parser_set_language(parser, language);

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len));
    defer ts.ts_tree_delete(tree);

    const root_node = ts.ts_tree_root_node(tree);
    
    // Debug: Print the parsed tree with indentation
    std.debug.print("Parsed tree:\n", .{});
    print_node(root_node, 0, source);
    std.debug.print("\n", .{});
    
    var global_env = env.Environment.init(allocator, null);
    defer global_env.deinit();

    var interpreter = interp.Interpreter.init(allocator, source, &global_env);
    _ = try interpreter.eval(root_node);

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

fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error opening file {s}: {any}\n", .{ path, err });
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, size);
    const bytes_read = try file.readAll(buffer);
    
    if (bytes_read != size) return error.IncompleteRead;
    return buffer;
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
