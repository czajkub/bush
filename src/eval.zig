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
    const name_node = ts.ts_node_child_by_field_name(node, "variable", 8);
    const expr_node = ts.ts_node_child_by_field_name(node, "expression", 10);

    if (ts.ts_node_is_null(name_node) or ts.ts_node_is_null(expr_node)) {
        return error.SyntaxError;
    }

    const name = self.getNodeSource(name_node);
    const value = try self.eval(expr_node) orelse return error.ExpressionEvaluatedToNull;

    try self.environment.set(name, value);
    return value;
}

pub fn evalBinaryExpression(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const left_node = ts.ts_node_child_by_field_name(node, "left", 4);
    const op_node = ts.ts_node_child_by_field_name(node, "operator", 8);
    const right_node = ts.ts_node_child_by_field_name(node, "right", 5);

    const left_val = try self.eval(left_node) orelse return error.ExpressionEvaluatedToNull;
    const right_val = try self.eval(right_node) orelse return error.ExpressionEvaluatedToNull;
    const op = self.getNodeSource(op_node);

    if (left_val == .integer and right_val == .integer) {
        const l = left_val.integer;
        const r = right_val.integer;
        if (std.mem.eql(u8, op, "+")) return .{ .integer = l + r };
        if (std.mem.eql(u8, op, "-")) return .{ .integer = l - r };
        if (std.mem.eql(u8, op, "*")) return .{ .integer = l * r };
        if (std.mem.eql(u8, op, "/")) {
            if (r == 0) return error.DivisionByZero;
            return .{ .integer = @divTrunc(l, r) };
        }
        if (std.mem.eql(u8, op, "==")) return .{ .boolean = l == r };
        if (std.mem.eql(u8, op, "!=")) return .{ .boolean = l != r };
        if (std.mem.eql(u8, op, "<")) return .{ .boolean = l < r };
        if (std.mem.eql(u8, op, "<=")) return .{ .boolean = l <= r };
        if (std.mem.eql(u8, op, ">")) return .{ .boolean = l > r };
        if (std.mem.eql(u8, op, ">=")) return .{ .boolean = l >= r };
        if (std.mem.eql(u8, op, "&&")) return .{ .boolean = (l != 0) and (r != 0) };
        if (std.mem.eql(u8, op, "||")) return .{ .boolean = (l != 0) or (r != 0) };
    }

    return error.UnsupportedOperator;
}

pub fn evalUnaryExpression(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!env.Value {
    const op_node = ts.ts_node_child_by_field_name(node, "operator", 8);
    const operand_node = ts.ts_node_child_by_field_name(node, "operand", 7);
    
    const op = self.getNodeSource(op_node);
    const val = try self.eval(operand_node) orelse {
        return error.ExpressionEvaluatedToNull;
    };

    if (val == .integer) {
        if (std.mem.eql(u8, op, "-")) return .{ .integer = -val.integer };
        if (std.mem.eql(u8, op, "+")) return val;
        if (std.mem.eql(u8, op, "!")) return .{ .boolean = val.integer == 0 };
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
    const name_node = ts.ts_node_child_by_field_name(node, "name", 4);
    if (ts.ts_node_is_null(name_node)) return error.SyntaxError;
    const name = self.getNodeSource(name_node);
    const value = env.Value{ .function = node };
    try self.environment.set(name, value);
    return value;
}

pub fn evalWhile(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const condition_node = ts.ts_node_child_by_field_name(node, "condition", 9);
    const body_node = ts.ts_node_child_by_field_name(node, "body", 4);
    if (ts.ts_node_is_null(condition_node) or ts.ts_node_is_null(body_node)) return error.SyntaxError;

    var last_val: ?env.Value = null;
    while (try isTruthy(try self.eval(condition_node))) {
        last_val = try self.eval(body_node);
    }
    return last_val;
}

pub fn evalIf(self: *interp.Interpreter, node: ts.TSNode) interp.EvalError!?env.Value {
    const condition_node = ts.ts_node_child_by_field_name(node, "condition", 9);
    const consequence_node = ts.ts_node_child_by_field_name(node, "consequence", 11);
    const alternative_node = ts.ts_node_child_by_field_name(node, "alternative", 11);

    if (ts.ts_node_is_null(condition_node) or ts.ts_node_is_null(consequence_node)) return error.SyntaxError;

    if (try isTruthy(try self.eval(condition_node))) {
        return try self.eval(consequence_node);
    } else if (!ts.ts_node_is_null(alternative_node)) {
        return try self.eval(alternative_node);
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
    const func_node = ts.ts_node_child_by_field_name(node, "function", 8);
    if (ts.ts_node_is_null(func_node)) return error.SyntaxError;

    const func_name = self.getNodeSource(func_node);
    const func_val = self.environment.get(func_name) orelse return error.UndefinedVariable;

    if (func_val != .function) return error.UnsupportedOperator;

    const def_node = func_val.function;
    const params_node = ts.ts_node_child_by_field_name(def_node, "parameters", 10);
    const args_node = ts.ts_node_child_by_field_name(node, "arguments", 9);
    
    // Create new environment for the function call
    var call_env = env.Environment.init(self.allocator, self.environment);
    defer call_env.deinit();

    // Bind arguments to parameters
    if (!ts.ts_node_is_null(params_node)) {
        const param_count = ts.ts_node_named_child_count(params_node);
        const arg_count = if (ts.ts_node_is_null(args_node)) 0 else ts.ts_node_named_child_count(args_node);
        
        if (param_count != arg_count) {
            // Special case: if param_count is 0 but params_node is not null, 
            // maybe params_node IS the parameter (if it's a single param)
            if (param_count == 0 and arg_count == 1) {
                const param_name = self.getNodeSource(params_node);
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
                const param_name = self.getNodeSource(param);
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

    // Evaluate body
    var cursor = ts.ts_tree_cursor_new(def_node);
    defer ts.ts_tree_cursor_delete(&cursor);

    var result: ?env.Value = null;
    if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
        while (true) {
            const child = ts.ts_tree_cursor_current_node(&cursor);
            const type_name = std.mem.span(ts.ts_node_type(child));
            
            if (ts.ts_node_is_named(child)) {
                if (std.mem.eql(u8, type_name, "assignment") or 
                    std.mem.eql(u8, type_name, "if_statement") or 
                    std.mem.eql(u8, type_name, "while_statement") or 
                    std.mem.eql(u8, type_name, "return_statement") or
                    std.mem.eql(u8, type_name, "simple_command")) {
                    
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
    const expr_node = ts.ts_node_child_by_field_name(node, "expression", 10);
    if (!ts.ts_node_is_null(expr_node)) {
        self.return_value = try self.eval(expr_node);
    } else {
        self.return_value = null;
    }
    return error.ReturnTriggered;
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
