const std = @import("std");
const bush = @import("root.zig");
const env = bush.env;
const ts = bush.ts;
const eval_logic = @import("eval.zig");

pub const EvalError = error{
    InvalidAssignment,
    ExpressionEvaluatedToNull,
    UndefinedVariable,
    SyntaxError,
    Overflow,
    InvalidCharacter,
    OutOfMemory,
    UnsupportedOperator,
    DivisionByZero,
    ReturnTriggered,
    CommandFailed,
};

const NodeType = enum {
    source_file,
    assignment,
    number_literal,
    variable_identifier,
    binary_expression,
    unary_expression,
    string_literal,
    parenthesized_expression,
    function_definition,
    while_statement,
    if_statement,
    return_statement,
    block,
    call_expression,
    simple_command,
    piped_command,
    unknown,
};

const node_type_map = std.StaticStringMap(NodeType).initComptime(.{
    .{ "source_file", .source_file },
    .{ "assignment", .assignment },
    .{ "number_literal", .number_literal },
    .{ "variable_identifier", .variable_identifier },
    .{ "binary_expression", .binary_expression },
    .{ "unary_expression", .unary_expression },
    .{ "string_literal", .string_literal },
    .{ "parenthesized_expression", .parenthesized_expression },
    .{ "function_definition", .function_definition },
    .{ "while_statement", .while_statement },
    .{ "if_statement", .if_statement },
    .{ "return_statement", .return_statement },
    .{ "block", .block },
    .{ "call_expression", .call_expression },
    .{ "simple_command", .simple_command },
    .{ "piped_command", .piped_command },
});

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    environment: *env.Environment,
    return_value: ?env.Value = null,
    environ_map: *std.process.Environ.Map,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, environment: *env.Environment, io: std.Io, environ_map: *std.process.Environ.Map) !Interpreter {
        return .{
            .allocator = allocator,
            .source = source,
            .environment = environment,
            .return_value = null,
            .environ_map = environ_map,
            .io = io,
        };
    }

    pub fn eval(self: *Interpreter, node: ts.TSNode) EvalError!?env.Value {
        if (ts.ts_node_is_null(node)) return null;
        if (ts.ts_node_is_error(node)) {
            const point = ts.ts_node_start_point(node);
            const out = std.Io.File.stdout();
            out.writeStreamingAll(self.io, "\nParsing Error at line ") catch {};

            var buf: [20]u8 = undefined;
            const line_str = std.fmt.bufPrint(&buf, "{d}", .{point.row + 1}) catch "??";
            out.writeStreamingAll(self.io, line_str) catch {};
            out.writeStreamingAll(self.io, ", column ") catch {};
            const col_str = std.fmt.bufPrint(&buf, "{d}", .{point.column + 1}) catch "??";
            out.writeStreamingAll(self.io, col_str) catch {};
            out.writeStreamingAll(self.io, ": Execution stopped.\n") catch {};

            // Find and print the line from source
            var lines = std.mem.splitScalar(u8, self.source, '\n');
            var current_row: u32 = 0;
            while (lines.next()) |line| : (current_row += 1) {
                if (current_row == point.row) {
                    const row_str = std.fmt.bufPrint(&buf, " {d} | ", .{current_row + 1}) catch "?? | ";
                    out.writeStreamingAll(self.io, row_str) catch {};
                    out.writeStreamingAll(self.io, line) catch {};
                    out.writeStreamingAll(self.io, "\n   | ") catch {};

                    const num_len = std.fmt.count("{d}", .{current_row + 1});
                    for (0..num_len) |_| out.writeStreamingAll(self.io, " ") catch {};
                    for (0..point.column) |_| out.writeStreamingAll(self.io, " ") catch {};
                    out.writeStreamingAll(self.io, "^\n") catch {};
                    break;
                }
            }

            return error.SyntaxError;
        }

        const type_name = std.mem.span(ts.ts_node_type(node));
        const node_type = node_type_map.get(type_name) orelse .unknown;

        switch (node_type) {
            .source_file => return try eval_logic.evalSourceFile(self, node),
            .assignment => return try eval_logic.evalAssignment(self, node),
            .number_literal => return try eval_logic.evalNumberLiteral(self, node),
            .variable_identifier => return try eval_logic.evalVariableLookup(self, node),
            .binary_expression => return try eval_logic.evalBinaryExpression(self, node),
            .unary_expression => return try eval_logic.evalUnaryExpression(self, node),
            .string_literal => return try eval_logic.evalStringLiteral(self, node),
            .parenthesized_expression => {
                const child = ts.ts_node_named_child(node, 0);
                return try self.eval(child);
            },
            .function_definition => return try eval_logic.evalFunctionDefinition(self, node),
            .while_statement => return try eval_logic.evalWhile(self, node),
            .if_statement => return try eval_logic.evalIf(self, node),
            .block => return try eval_logic.evalBlock(self, node),
            .call_expression => return try eval_logic.evalCall(self, node),
            .return_statement => return try eval_logic.evalReturn(self, node),
            .simple_command => return try eval_logic.evalSimpleCommand(self, node),
            .piped_command => return try eval_logic.evalPipedCommand(self, node),
            .unknown => {
                // If it's a wrapper node or unknown node, evaluate its children
                var result: ?env.Value = null;
                var cursor = ts.ts_tree_cursor_new(node);
                defer ts.ts_tree_cursor_delete(&cursor);
                if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
                    while (true) {
                        const child = ts.ts_tree_cursor_current_node(&cursor);
                        // Recurse into all children if the parent is unknown
                        const child_result = try self.eval(child);
                        if (child_result != null) {
                            result = child_result;
                        }
                        if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
                    }
                }
                return result;
            },
        }
    }

    pub fn getNodeSource(self: *Interpreter, node: ts.TSNode) []const u8 {
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        return self.source[start..end];
    }
};
