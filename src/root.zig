const std = @import("std");

pub const env = @import("env.zig");
pub const interpreter = @import("interpreter.zig");
pub const cli = @import("cli.zig");

pub const ts = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const Language = opaque {
    pub extern fn tree_sitter_bush() *Language;
};
