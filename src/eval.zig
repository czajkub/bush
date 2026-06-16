const std = @import("std");
const bush = @import("root.zig");
const env = bush.env;
const ts = bush.ts;
const interp = @import("interpreter.zig");

pub fn evalSourceFile(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    var cursor = ts.ts_tree_cursor_new(node);
    defer ts.ts_tree_cursor_delete(&cursor);

    if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
        while (true) {
            const child = ts.ts_tree_cursor_current_node(&cursor);
            if (ts.ts_node_is_named(child)) {
                _ = try self.eval(child);
            }
            if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
        }
    }
    return null;
}

pub fn evalAssignment(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const name_node = ts.ts_node_child_by_field_name(node, "variable", @intCast("variable".len));
    const expr_node = ts.ts_node_child_by_field_name(node, "expression", @intCast("expression".len));

    if (ts.ts_node_is_null(name_node) or ts.ts_node_is_null(expr_node)) {
        return error.SyntaxError;
    }

    const name = self.getNodeSource(name_node);
    const value = try self.eval(expr_node) orelse return error.ExpressionEvaluatedToNull;

    try self.environment.set(name, value);

    // Set as actual environment variable for child processes
    const env_name = if (name.len > 0 and name[0] == '$') name[1..] else name;
    const str_val = try valueToString(self.allocator, value);
    defer self.allocator.free(str_val);
    
    try self.environ_map.put(env_name, str_val);

    return value;
}

pub fn evalBinaryExpression(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const left_node = ts.ts_node_child_by_field_name(node, "left", @intCast("left".len));
    const op_node = ts.ts_node_child_by_field_name(node, "operator", @intCast("operator".len));
    const right_node = ts.ts_node_child_by_field_name(node, "right", @intCast("right".len));

    const left_val = try self.eval(left_node) orelse return error.ExpressionEvaluatedToNull;
    const right_val = try self.eval(right_node) orelse return error.ExpressionEvaluatedToNull;
    const op = self.getNodeSource(op_node);

    if (left_val == .integer and right_val == .integer) {
        const l = left_val.integer;
        const r = right_val.integer;
        
        const BinOp = enum {
            add, sub, mul, div, eq, neq, lt, le, gt, ge, log_and, log_or
        };
        const op_type = std.StaticStringMap(BinOp).initComptime(.{
            .{ "+", .add }, .{ "-", .sub }, .{ "*", .mul }, .{ "/", .div },
            .{ "==", .eq }, .{ "!=", .neq }, .{ "<", .lt }, .{ "<=", .le },
            .{ ">", .gt }, .{ ">=", .ge }, .{ "&&", .log_and }, .{ "||", .log_or },
        }).get(op) orelse return error.UnsupportedOperator;

        return switch (op_type) {
            .add => .{ .integer = l + r },
            .sub => .{ .integer = l - r },
            .mul => .{ .integer = l * r },
            .div => if (r == 0) error.DivisionByZero else .{ .integer = @divTrunc(l, r) },
            .eq => .{ .boolean = l == r },
            .neq => .{ .boolean = l != r },
            .lt => .{ .boolean = l < r },
            .le => .{ .boolean = l <= r },
            .gt => .{ .boolean = l > r },
            .ge => .{ .boolean = l >= r },
            .log_and => .{ .boolean = (l != 0) and (r != 0) },
            .log_or => .{ .boolean = (l != 0) or (r != 0) },
        };
    }

    return error.UnsupportedOperator;
}

pub fn evalUnaryExpression(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const op_node = ts.ts_node_child_by_field_name(node, "operator", @intCast("operator".len));
    const operand_node = ts.ts_node_child_by_field_name(node, "operand", @intCast("operand".len));
    
    const op = self.getNodeSource(op_node);
    const val = try self.eval(operand_node) orelse {
        return error.ExpressionEvaluatedToNull;
    };

    if (val == .integer) {
        if (op.len == 1) {
            return switch (op[0]) {
                '-' => .{ .integer = -val.integer },
                '+' => val,
                '!' => .{ .boolean = val.integer == 0 },
                else => error.UnsupportedOperator,
            };
        }
    }
    
    return error.UnsupportedOperator;
}

pub fn evalNumberLiteral(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const source = self.getNodeSource(node);
    const val = std.fmt.parseInt(i64, source, 10) catch return error.InvalidCharacter;
    return .{ .integer = val };
}

pub fn evalStringLiteral(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const source = self.getNodeSource(node);
    if (source.len >= 2) {
        const inner = try self.allocator.dupe(u8, source[1 .. source.len - 1]);
        return .{ .string = inner };
    }
    return .{ .string = try self.allocator.dupe(u8, "") };
}

pub fn evalVariableLookup(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const name = self.getNodeSource(node);
    if (self.environment.get(name)) |val| {
        return val;
    }
    std.debug.print("Undefined variable: {s}\n", .{name});
    return error.UndefinedVariable;
}

pub fn evalFunctionDefinition(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const name_node = ts.ts_node_child_by_field_name(node, "name", @intCast("name".len));
    if (ts.ts_node_is_null(name_node)) return error.SyntaxError;
    const name = self.getNodeSource(name_node);
    const value = env.Value{ .function = .{ .node = node, .source = self.source } };
    try self.environment.set(name, value);
    return value;
}

pub fn evalWhile(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const condition_node = ts.ts_node_child_by_field_name(node, "condition", @intCast("condition".len));
    if (ts.ts_node_is_null(condition_node)) return error.SyntaxError;

    var last_val: ?env.Value = null;
    while (try isTruthy(try self.eval(condition_node))) {
        var cursor = ts.ts_tree_cursor_new(node);
        defer ts.ts_tree_cursor_delete(&cursor);

        if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
            while (true) {
                const child = ts.ts_tree_cursor_current_node(&cursor);
                if (ts.ts_node_is_named(child)) {
                    const type_name = std.mem.span(ts.ts_node_type(child));
                    if (!std.mem.eql(u8, type_name, "binary_expression") and 
                        !std.mem.eql(u8, type_name, "number_literal") and 
                        !std.mem.eql(u8, type_name, "variable_identifier") and
                        !std.mem.eql(u8, type_name, "unary_expression") and
                        !std.mem.eql(u8, type_name, "parenthesized_expression") and
                        !std.mem.eql(u8, type_name, "call_expression") and
                        !std.mem.eql(u8, type_name, "string_literal")
                    ) {
                         last_val = try self.eval(child);
                    }
                }
                if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
            }
        }
    }
    return last_val;
}

pub fn evalIf(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const condition_node = ts.ts_node_child_by_field_name(node, "condition", @intCast("condition".len));
    if (ts.ts_node_is_null(condition_node)) return error.SyntaxError;

    if (try isTruthy(try self.eval(condition_node))) {
        var cursor = ts.ts_tree_cursor_new(node);
        defer ts.ts_tree_cursor_delete(&cursor);

        var last_val: ?env.Value = null;
        if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
            while (true) {
                const child = ts.ts_tree_cursor_current_node(&cursor);
                if (ts.ts_node_is_named(child)) {
                    const type_name = std.mem.span(ts.ts_node_type(child));
                    if (!std.mem.eql(u8, type_name, "binary_expression") and 
                        !std.mem.eql(u8, type_name, "number_literal") and 
                        !std.mem.eql(u8, type_name, "variable_identifier") and
                        !std.mem.eql(u8, type_name, "unary_expression") and
                        !std.mem.eql(u8, type_name, "parenthesized_expression") and
                        !std.mem.eql(u8, type_name, "call_expression") and
                        !std.mem.eql(u8, type_name, "string_literal")
                    ) {
                         last_val = try self.eval(child);
                    }
                }
                if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
            }
        }
        return last_val;
    }

    return null;
}

pub fn evalBlock(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    var cursor = ts.ts_tree_cursor_new(node);
    defer ts.ts_tree_cursor_delete(&cursor);

    var last_val: ?env.Value = null;
    if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
        while (true) {
            const child = ts.ts_tree_cursor_current_node(&cursor);
            if (ts.ts_node_is_named(child)) {
                last_val = try self.eval(child);
            }
            if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
        }
    }
    return last_val;
}

pub fn evalCall(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const func_node = ts.ts_node_child_by_field_name(node, "function", @intCast("function".len));
    if (ts.ts_node_is_null(func_node)) return error.SyntaxError;

    const func_name = self.getNodeSource(func_node);
    const func_val = self.environment.get(func_name) orelse return error.UndefinedVariable;

    if (func_val != .function) return error.UnsupportedOperator;

    const def_node = func_val.function.node;
    const params_node = ts.ts_node_child_by_field_name(def_node, "parameters", @intCast("parameters".len));
    const args_node = ts.ts_node_child_by_field_name(node, "arguments", @intCast("arguments".len));
    
    // Create new environment for the function call
    var call_env = env.Environment.init(self.allocator, self.environment);
    defer call_env.deinit();

    // Def nodes index into def_source; args are evaluated against caller source.
    const caller_source = self.source;
    const def_source = func_val.function.source;

    // Bind arguments to parameters
    if (!ts.ts_node_is_null(params_node)) {
        const param_count = ts.ts_node_named_child_count(params_node);
        const arg_count = if (ts.ts_node_is_null(args_node)) 0 else ts.ts_node_named_child_count(args_node);

        if (param_count != arg_count) {
            // Special case: if param_count is 0 but params_node is not null,
            // maybe params_node IS the parameter (if it's a single param)
            if (param_count == 0 and arg_count == 1) {
                self.source = def_source;
                const param_name = self.getNodeSource(params_node);
                self.source = caller_source;
                const arg = ts.ts_node_named_child(args_node, 0);
                const arg_val = try self.eval(arg) orelse return error.ExpressionEvaluatedToNull;
                try call_env.set(param_name, arg_val);
            } else {
                return error.UnsupportedOperator;
            }
        } else {
            var i: u32 = 0;
            while (i < param_count) : (i += 1) {
                const param = ts.ts_node_named_child(params_node, i);
                const arg = ts.ts_node_named_child(args_node, i);
                self.source = def_source;
                const param_name = self.getNodeSource(param);
                self.source = caller_source;
                // Evaluate arg in the OLD environment
                const arg_val = try self.eval(arg) orelse return error.ExpressionEvaluatedToNull;
                try call_env.set(param_name, arg_val);
            }
        }
    }

    // Save old environment and switch to call environment
    const old_env = self.environment;
    self.environment = &call_env;
    defer self.environment = old_env;

    self.source = def_source;
    defer self.source = caller_source;

    // Evaluate body
    var cursor = ts.ts_tree_cursor_new(def_node);
    defer ts.ts_tree_cursor_delete(&cursor);

    var result: ?env.Value = null;
    if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
        while (true) {
            const child = ts.ts_tree_cursor_current_node(&cursor);
            const type_name = std.mem.span(ts.ts_node_type(child));
            
            if (ts.ts_node_is_named(child)) {
                if (!std.mem.eql(u8, type_name, "command_name") and !std.mem.eql(u8, type_name, "parameter_list")) {
                    result = self.eval(child) catch |err| {
                        if (err == error.ReturnTriggered) {
                            const ret = self.return_value;
                            self.return_value = null;
                            return ret;
                        }
                        return err;
                    };
                }
            }

            if (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) break;
        }
    }

    return result;
}

pub fn evalReturn(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const expr_node = ts.ts_node_child_by_field_name(node, "expression", @intCast("expression".len));
    if (!ts.ts_node_is_null(expr_node)) {
        self.return_value = try self.eval(expr_node);
    } else {
        self.return_value = null;
    }
    return error.ReturnTriggered;
}

pub fn evalSimpleCommand(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    var argv = try collectArgv(self, node);
    defer {
        for (argv.items) |arg| self.allocator.free(arg);
        argv.deinit(self.allocator);
    }

    var child = std.process.spawn(self.io, .{
        .argv = argv.items,
        .environ_map = self.environ_map,
    }) catch return error.CommandFailed;
    const term = child.wait(self.io) catch return error.CommandFailed;

    return switch (term) {
        .exited => |code| .{ .integer = @intCast(code) },
        else => .{ .integer = -1 },
    };
}

fn collectPipelineCommands(allocator: std.mem.Allocator, node: ts.TSNode, list: *std.ArrayList(ts.TSNode)) !void {
    const type_name = std.mem.span(ts.ts_node_type(node));
    if (std.mem.eql(u8, type_name, "piped_command")) {
        const left = ts.ts_node_child_by_field_name(node, "left", @intCast("left".len));
        const right = ts.ts_node_child_by_field_name(node, "right", @intCast("right".len));
        try collectPipelineCommands(allocator, left, list);
        try collectPipelineCommands(allocator, right, list);
    } else if (std.mem.eql(u8, type_name, "simple_command")) {
        try list.append(allocator, node);
    } else {
        return error.SyntaxError;
    }
}

fn pipeShuttle(io: std.Io, in: std.Io.File, out: std.Io.File) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = in.readStreaming(io, &.{&buf}) catch break;
        if (n == 0) break;
        out.writeStreamingAll(io, buf[0..n]) catch break;
    }
    out.close(io);
}

pub fn evalPipedCommand(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    var commands: std.ArrayList(ts.TSNode) = .empty;
    defer commands.deinit(self.allocator);

    collectPipelineCommands(self.allocator, node, &commands) catch return error.SyntaxError;
    if (commands.items.len < 2) return error.SyntaxError;

    var children: std.ArrayList(std.process.Child) = .empty;
    defer children.deinit(self.allocator);

    var argv_list: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    defer {
        for (argv_list.items) |*argv| {
            for (argv.items) |arg| self.allocator.free(arg);
            argv.deinit(self.allocator);
        }
        argv_list.deinit(self.allocator);
    }

    // Initialize and spawn all children
    for (commands.items, 0..) |cmd_node, i| {
        const argv = try collectArgv(self, cmd_node);
        try argv_list.append(self.allocator, argv);

        const child = std.process.spawn(self.io, .{
            .argv = argv.items,
            .environ_map = self.environ_map,
            .stdin = if (i > 0) .pipe else .inherit,
            .stdout = if (i < commands.items.len - 1) .pipe else .inherit,
        }) catch return error.CommandFailed;
        
        try children.append(self.allocator, child);
    }

    var threads: std.ArrayList(std.Thread) = .empty;
    defer threads.deinit(self.allocator);

    // Start shuttling threads
    for (0..children.items.len - 1) |i| {
        const in_file = children.items[i].stdout.?;
        const out_file = children.items[i+1].stdin.?;
        const thread = std.Thread.spawn(.{}, pipeShuttle, .{ self.io, in_file, out_file }) catch return error.CommandFailed;
        try threads.append(self.allocator, thread);
    }

    // Wait for all threads to finish shuttling
    for (threads.items) |thread| {
        thread.join();
    }

    for (children.items, 0..) |*child, i| {
        if (i > 0) {
            child.stdin = null;
        }
    }

    // Wait for all children
    var last_code: u32 = 0;
    for (children.items) |*child| {
        const term = child.wait(self.io) catch return error.CommandFailed;
        switch (term) {
            .exited => |code| last_code = code,
            else => last_code = 1,
        }
    }

    return .{ .integer = @intCast(last_code) };
}

pub fn valueToString(allocator: std.mem.Allocator, val: env.Value) ![]u8 {
    return switch (val) {
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .string => |s| try allocator.dupe(u8, s),
        .boolean => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        .function => try allocator.dupe(u8, "<function>"),
    };
}

fn collectArgv(self: *interp.Interpreter, node: ts.TSNode) !std.ArrayList([]const u8) {
    const name_node = ts.ts_node_child_by_field_name(node, "name", @intCast("name".len));
    if (ts.ts_node_is_null(name_node)) return error.SyntaxError;

    const cmd_name = try self.allocator.dupe(u8, self.getNodeSource(name_node));
    var argv = std.ArrayList([]const u8).empty;
    errdefer {
        for (argv.items) |arg| self.allocator.free(arg);
        argv.deinit(self.allocator);
    }

    try argv.append(self.allocator, cmd_name);

    const child_count = ts.ts_node_child_count(node);
    var j: u32 = 0;
    while (j < child_count) : (j += 1) {
        const child = ts.ts_node_child(node, j);
        if (!ts.ts_node_is_named(child)) continue;
        const type_name = std.mem.span(ts.ts_node_type(child));

        const ArgType = enum {
            simple_argument,
            variable_identifier,
            expression_argument,
            string_literal,
            other,
        };
        const arg_type = std.StaticStringMap(ArgType).initComptime(.{
            .{ "simple_argument", .simple_argument },
            .{ "variable_identifier", .variable_identifier },
            .{ "expression_argument", .expression_argument },
            .{ "string_literal", .string_literal },
        }).get(type_name) orelse .other;

        switch (arg_type) {
            .simple_argument => {
                try argv.append(self.allocator, try self.allocator.dupe(u8, self.getNodeSource(child)));
            },
            .variable_identifier => {
                const val = try self.eval(child) orelse return error.ExpressionEvaluatedToNull;
                // String value from eval(variable_identifier) is NOT a copy
                const str = try valueToString(self.allocator, val);
                try argv.append(self.allocator, str);
            },
            .expression_argument => {
                const expr = ts.ts_node_named_child(child, 0);
                const val = try self.eval(expr) orelse return error.ExpressionEvaluatedToNull;
                const str = try valueToString(self.allocator, val);
                try argv.append(self.allocator, str);
            },
            .string_literal => {
                const val = try self.eval(child) orelse return error.ExpressionEvaluatedToNull;
                // String value from eval(string_literal) IS a new copy
                defer if (val == .string) self.allocator.free(val.string);
                const str = try valueToString(self.allocator, val);
                try argv.append(self.allocator, str);
            },
            .other => {},
        }
    }
    return argv;
}

fn isTruthy(val: ?env.Value) !bool {
    const v = val orelse return false;
    return switch (v) {
        .integer => |i| i != 0,
        .float => |f| f != 0.0,
        .string => |s| s.len > 0,
        .boolean => |b| b,
        .function => true,
    };
}
