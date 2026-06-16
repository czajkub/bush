const std = @import("std");

const bush = @import("root.zig");
const ts = bush.ts;

/// A defined function: its definition node plus the source buffer the node's
/// byte offsets index into. The source is owned elsewhere (the file buffer in
/// script mode, or the REPL's session-lived source list), never by the Value.
pub const Function = struct {
    node: ts.TSNode,
    source: []const u8,
};

pub const Value = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    function: Function,

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

pub const Environment = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap(Value),
    parent: ?*Environment,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) Environment {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap(Value).init(allocator),
            .parent = parent,
        };
    }

    pub fn deinit(self: *Environment) void {
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
        }
        self.variables.deinit();
    }

    pub fn set(self: *Environment, name: []const u8, value: Value) !void {
        // If variable exists in this or parent scope, update it there
        if (self.getPtr(name)) |existing| {
            existing.deinit(self.allocator);
            existing.* = value;
            return;
        }

        // Otherwise, create new variable in current scope
        const name_copy = try self.allocator.dupe(u8, name);
        try self.variables.put(name_copy, value);
    }

    pub fn get(self: *const Environment, name: []const u8) ?Value {
        if (self.variables.get(name)) |val| return val;
        if (self.parent) |p| return p.get(name);
        return null;
    }

    fn getPtr(self: *Environment, name: []const u8) ?*Value {
        if (self.variables.getPtr(name)) |val| return val;
        if (self.parent) |p| return p.getPtr(name);
        return null;
    }
};
