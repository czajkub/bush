const std = @import("std");
const bush = @import("root.zig");
const env = bush.env;
const interp = bush.interpreter;
const ts = bush.ts;

extern fn tree_sitter_bush() callconv(.c) *ts.TSLanguage;

const keywords = [_][]const u8{ "function", "if", "while", "return" };

const PROMPT = "bush> ";
const CONT_PROMPT = "...>  ";

/// Run an interactive read-eval-print loop. The global environment persists
/// across lines, and every parsed tree + its source buffer is kept alive for
/// the whole session so function definitions stay valid when called later.
pub fn repl(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
) !void {
    const language = tree_sitter_bush();
    const parser = ts.ts_parser_new();
    defer ts.ts_parser_delete(parser);
    _ = ts.ts_parser_set_language(parser, language);

    var global_env = env.Environment.init(allocator, null);
    defer global_env.deinit();

    var interpreter = try interp.Interpreter.init(allocator, "", &global_env, io, environ_map);

    var trees: std.ArrayList(*ts.TSTree) = .empty;
    defer {
        for (trees.items) |t| ts.ts_tree_delete(t);
        trees.deinit(allocator);
    }
    var sources: std.ArrayList([]u8) = .empty;
    defer {
        for (sources.items) |s| allocator.free(s);
        sources.deinit(allocator);
    }

    const out = std.Io.File.stdout();
    const in = std.Io.File.stdin();

    var editor = Editor.init(allocator, io, in, out);
    defer editor.deinit();
    editor.environment = &global_env;

    out.writeStreamingAll(io, "bush interactive shell. Type :q or Ctrl-D to exit.\n") catch {};

    // Accumulator for the (possibly multi-line) current statement.
    var input: std.ArrayList(u8) = .empty;
    defer input.deinit(allocator);

    session: while (true) {
        input.clearRetainingCapacity();

        // Read physical lines until braces/parens balance.
        while (true) {
            const prompt = if (input.items.len == 0) PROMPT else CONT_PROMPT;
            const line = editor.readLine(prompt) catch |err| switch (err) {
                error.EndOfStream => {
                    if (input.items.len == 0) {
                        out.writeStreamingAll(io, "\n") catch {};
                        break :session;
                    }
                    break; // EOF mid-statement: try to run what we have.
                },
                else => return err,
            };
            if (input.items.len != 0) try input.append(allocator, '\n');
            try input.appendSlice(allocator, line);
            if (!isIncomplete(input.items)) break;
        }

        const trimmed = std.mem.trim(u8, input.items, " \t\r\n");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, ":q") or std.mem.eql(u8, trimmed, "exit")) break;
        if (std.mem.eql(u8, trimmed, ":env") or std.mem.eql(u8, trimmed, "showenv")) {
            printEnv(out, io, &global_env);
            continue;
        }

        // Own a copy of the source for the lifetime of the session and parse it.
        const src = try allocator.dupe(u8, input.items);
        const tree = ts.ts_parser_parse_string(parser, null, src.ptr, @intCast(src.len)) orelse {
            allocator.free(src);
            out.writeStreamingAll(io, "Error: failed to parse input.\n") catch {};
            continue;
        };
        try trees.append(allocator, tree);
        try sources.append(allocator, src);

        interpreter.source = src;
        const root_node = ts.ts_tree_root_node(tree);
        const result = interpreter.eval(root_node) catch |err| {
            if (err != error.SyntaxError) {
                std.debug.print("Runtime Error: {any}\n", .{err});
            }
            continue;
        };

        if (result) |value| printValue(out, io, value);
    }
}

/// True if `src` has more opening than closing braces/parens (ignoring those
/// inside strings and comments), meaning the statement isn't finished yet.
fn isIncomplete(src: []const u8) bool {
    var depth: i32 = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const c = src[i];
        switch (c) {
            '"' => {
                i += 1;
                while (i < src.len and src[i] != '"') : (i += 1) {}
            },
            '/' => {
                if (i + 1 < src.len and src[i + 1] == '/') {
                    i += 1;
                    while (i < src.len and src[i] != '\n') : (i += 1) {}
                } else if (i + 1 < src.len and src[i + 1] == '*') {
                    i += 2;
                    while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) : (i += 1) {}
                    i += 1;
                }
            },
            '{', '(' => depth += 1,
            '}', ')' => depth -= 1,
            else => {},
        }
    }
    return depth > 0;
}

/// Print every variable and function currently defined in `environment`.
fn printEnv(out: std.Io.File, io: std.Io, environment: *const env.Environment) void {
    var buf: [256]u8 = undefined;
    var any = false;
    var it = environment.variables.iterator();
    while (it.next()) |entry| {
        any = true;
        const name = entry.key_ptr.*;
        switch (entry.value_ptr.*) {
            .integer => |v| writeFmt(out, io, &buf, "{s} = {d}\n", .{ name, v }),
            .float => |v| writeFmt(out, io, &buf, "{s} = {d}\n", .{ name, v }),
            .boolean => |v| writeFmt(out, io, &buf, "{s} = {}\n", .{ name, v }),
            .string => |v| writeFmt(out, io, &buf, "{s} = \"{s}\"\n", .{ name, v }),
            .function => |f| {
                const params_node = ts.ts_node_child_by_field_name(f.node, "parameters", @intCast("parameters".len));
                const params = if (ts.ts_node_is_null(params_node)) "" else nodeText(f.source, params_node);
                writeFmt(out, io, &buf, "function {s}({s})\n", .{ name, params });
            },
        }
    }
    if (!any) out.writeStreamingAll(io, "(empty environment)\n") catch {};
}

fn nodeText(source: []const u8, node: ts.TSNode) []const u8 {
    return source[ts.ts_node_start_byte(node)..ts.ts_node_end_byte(node)];
}

fn writeFmt(out: std.Io.File, io: std.Io, buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(buf, fmt, args) catch return;
    out.writeStreamingAll(io, s) catch {};
}

fn printValue(out: std.Io.File, io: std.Io, value: env.Value) void {
    var buf: [64]u8 = undefined;
    switch (value) {
        .integer => |v| {
            const s = std.fmt.bufPrint(&buf, "{d}\n", .{v}) catch return;
            out.writeStreamingAll(io, s) catch {};
        },
        .float => |v| {
            const s = std.fmt.bufPrint(&buf, "{d}\n", .{v}) catch return;
            out.writeStreamingAll(io, s) catch {};
        },
        .boolean => |v| {
            out.writeStreamingAll(io, if (v) "true\n" else "false\n") catch {};
        },
        .string => |v| {
            out.writeStreamingAll(io, v) catch {};
            out.writeStreamingAll(io, "\n") catch {};
        },
        .function => out.writeStreamingAll(io, "<function>\n") catch {},
    }
}

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// A single-line editor over a raw-mode TTY: left/right cursor movement,
/// backspace, and Tab keyword completion. Falls back to plain line-buffered
/// reads when stdin is not a TTY.
const Editor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    in: std.Io.File,
    out: std.Io.File,
    buf: std.ArrayList(u8),
    cursor: usize = 0,
    raw_capable: bool,
    // Submitted lines, navigated with Up/Down. `hist_index` points into
    // `history` while browsing and equals `history.len` when editing a fresh
    // line; `draft` holds that fresh line while browsing older entries.
    history: std.ArrayList([]u8),
    hist_index: usize = 0,
    draft: std.ArrayList(u8),
    // Used to offer defined variable/function names as completions.
    environment: ?*const env.Environment = null,

    fn init(allocator: std.mem.Allocator, io: std.Io, in: std.Io.File, out: std.Io.File) Editor {
        // If we can read the terminal attributes, stdin is a TTY and we can
        // drive raw-mode editing; otherwise (pipe/file) fall back to plain reads.
        const raw_capable = if (std.posix.tcgetattr(std.posix.STDIN_FILENO)) |_| true else |_| false;
        return .{
            .allocator = allocator,
            .io = io,
            .in = in,
            .out = out,
            .buf = .empty,
            .raw_capable = raw_capable,
            .history = .empty,
            .draft = .empty,
        };
    }

    fn deinit(self: *Editor) void {
        self.buf.deinit(self.allocator);
        for (self.history.items) |h| self.allocator.free(h);
        self.history.deinit(self.allocator);
        self.draft.deinit(self.allocator);
    }

    /// Replace the line content with `text` and move the cursor to the end.
    fn setBuf(self: *Editor, text: []const u8, prompt: []const u8) !void {
        self.buf.clearRetainingCapacity();
        try self.buf.appendSlice(self.allocator, text);
        self.cursor = self.buf.items.len;
        self.refresh(prompt);
    }

    /// Append the current line to history, skipping empties and consecutive
    /// duplicates.
    fn pushHistory(self: *Editor) !void {
        if (self.buf.items.len == 0) return;
        if (self.history.getLastOrNull()) |last| {
            if (std.mem.eql(u8, last, self.buf.items)) return;
        }
        const entry = try self.allocator.dupe(u8, self.buf.items);
        try self.history.append(self.allocator, entry);
    }

    fn write(self: *Editor, s: []const u8) void {
        self.out.writeStreamingAll(self.io, s) catch {};
    }

    /// Read one line. Returns a slice valid until the next readLine call.
    /// Returns error.EndOfStream on EOF.
    fn readLine(self: *Editor, prompt: []const u8) ![]const u8 {
        if (!self.raw_capable) return self.readLinePlain(prompt);
        return self.readLineRaw(prompt);
    }

    fn readLinePlain(self: *Editor, prompt: []const u8) ![]const u8 {
        self.write(prompt);
        self.buf.clearRetainingCapacity();
        var byte: [1]u8 = undefined;
        var any = false;
        while (true) {
            const n = self.in.readStreaming(self.io, &.{&byte}) catch 0;
            if (n == 0) {
                if (!any) return error.EndOfStream;
                break;
            }
            any = true;
            if (byte[0] == '\n') break;
            try self.buf.append(self.allocator, byte[0]);
        }
        return self.buf.items;
    }

    fn readLineRaw(self: *Editor, prompt: []const u8) ![]const u8 {
        const orig = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        var raw = orig;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
        defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, orig) catch {};

        self.buf.clearRetainingCapacity();
        self.cursor = 0;
        self.hist_index = self.history.items.len;
        self.refresh(prompt);

        var byte: [1]u8 = undefined;
        while (true) {
            const n = self.in.readStreaming(self.io, &.{&byte}) catch 0;
            if (n == 0) {
                if (self.buf.items.len == 0) return error.EndOfStream;
                break;
            }
            const c = byte[0];
            switch (c) {
                '\r', '\n' => {
                    self.write("\r\n");
                    try self.pushHistory();
                    break;
                },
                4 => { // Ctrl-D
                    if (self.buf.items.len == 0) {
                        self.write("\r\n");
                        return error.EndOfStream;
                    }
                },
                3 => { // Ctrl-C: discard the current line.
                    self.buf.clearRetainingCapacity();
                    self.cursor = 0;
                    self.write("\r\n");
                    break;
                },
                127, 8 => { // Backspace
                    if (self.cursor > 0) {
                        _ = self.buf.orderedRemove(self.cursor - 1);
                        self.cursor -= 1;
                        self.refresh(prompt);
                    }
                },
                '\t' => try self.complete(prompt),
                0x1b => try self.handleEscape(prompt),
                else => {
                    if (c >= 0x20 and c < 0x7f) {
                        try self.buf.insert(self.allocator, self.cursor, c);
                        self.cursor += 1;
                        self.refresh(prompt);
                    }
                },
            }
        }
        return self.buf.items;
    }

    fn handleEscape(self: *Editor, prompt: []const u8) !void {
        var b: [1]u8 = undefined;
        if ((self.in.readStreaming(self.io, &.{&b}) catch 0) == 0) return;
        if (b[0] != '[') return;
        if ((self.in.readStreaming(self.io, &.{&b}) catch 0) == 0) return;
        switch (b[0]) {
            'C' => if (self.cursor < self.buf.items.len) { // right
                self.cursor += 1;
                self.refresh(prompt);
            },
            'D' => if (self.cursor > 0) { // left
                self.cursor -= 1;
                self.refresh(prompt);
            },
            'H' => { // Home
                self.cursor = 0;
                self.refresh(prompt);
            },
            'F' => { // End
                self.cursor = self.buf.items.len;
                self.refresh(prompt);
            },
            'A' => try self.historyPrev(prompt), // Up
            'B' => try self.historyNext(prompt), // Down
            // Extended sequences (e.g. "1~") are consumed and ignored.
            '0'...'9' => {
                var d: [1]u8 = undefined;
                while ((self.in.readStreaming(self.io, &.{&d}) catch 0) != 0 and d[0] != '~') {}
            },
            else => {},
        }
    }

    /// Up arrow: move to an older history entry, saving the in-progress line.
    fn historyPrev(self: *Editor, prompt: []const u8) !void {
        if (self.hist_index == 0) return;
        if (self.hist_index == self.history.items.len) {
            // Leaving the fresh line: stash it so Down can restore it.
            self.draft.clearRetainingCapacity();
            try self.draft.appendSlice(self.allocator, self.buf.items);
        }
        self.hist_index -= 1;
        try self.setBuf(self.history.items[self.hist_index], prompt);
    }

    /// Down arrow: move to a newer entry, or back to the in-progress line.
    fn historyNext(self: *Editor, prompt: []const u8) !void {
        if (self.hist_index >= self.history.items.len) return;
        self.hist_index += 1;
        if (self.hist_index == self.history.items.len) {
            try self.setBuf(self.draft.items, prompt);
        } else {
            try self.setBuf(self.history.items[self.hist_index], prompt);
        }
    }

    fn complete(self: *Editor, prompt: []const u8) !void {
        // Identify the word ending at the cursor; include a leading '$' so
        // variable identifiers (e.g. "$ab") complete as a unit.
        var start = self.cursor;
        while (start > 0 and isWordChar(self.buf.items[start - 1])) start -= 1;
        if (start > 0 and self.buf.items[start - 1] == '$') start -= 1;
        const word = self.buf.items[start..self.cursor];
        if (word.len == 0) return;

        // Candidates: keywords plus every name defined in the environment
        // (variables keyed as "$x", functions by their name).
        var candidates: std.ArrayList([]const u8) = .empty;
        defer candidates.deinit(self.allocator);
        for (keywords) |kw| try candidates.append(self.allocator, kw);
        if (self.environment) |e| {
            var it = e.variables.iterator();
            while (it.next()) |entry| try candidates.append(self.allocator, entry.key_ptr.*);
        }

        // Keep prefix matches that would actually add characters.
        var matches: std.ArrayList([]const u8) = .empty;
        defer matches.deinit(self.allocator);
        for (candidates.items) |c| {
            if (c.len > word.len and std.mem.startsWith(u8, c, word)) {
                try matches.append(self.allocator, c);
            }
        }
        if (matches.items.len == 0) return;

        if (matches.items.len == 1) {
            try self.insertAtCursor(matches.items[0][word.len..]);
            self.refresh(prompt);
            return;
        }

        // Multiple: extend by the longest common prefix, then list candidates.
        const common = longestCommonPrefix(matches.items);
        if (common.len > word.len) {
            try self.insertAtCursor(common[word.len..]);
        }
        self.write("\r\n");
        for (matches.items, 0..) |m, i| {
            if (i != 0) self.write("  ");
            self.write(m);
        }
        self.write("\r\n");
        self.refresh(prompt);
    }

    fn insertAtCursor(self: *Editor, text: []const u8) !void {
        for (text) |ch| {
            try self.buf.insert(self.allocator, self.cursor, ch);
            self.cursor += 1;
        }
    }

    /// Redraw the current line and reposition the cursor.
    fn refresh(self: *Editor, prompt: []const u8) void {
        var tmp: [32]u8 = undefined;
        self.write("\r"); // column 0
        self.write(prompt);
        self.write(self.buf.items);
        self.write("\x1b[K"); // clear to end of line
        const col = prompt.len + self.cursor + 1; // 1-based absolute column
        const move = std.fmt.bufPrint(&tmp, "\x1b[{d}G", .{col}) catch return;
        self.write(move);
    }
};

fn longestCommonPrefix(words: []const []const u8) []const u8 {
    if (words.len == 0) return "";
    var prefix = words[0];
    for (words[1..]) |w| {
        var i: usize = 0;
        while (i < prefix.len and i < w.len and prefix[i] == w[i]) : (i += 1) {}
        prefix = prefix[0..i];
    }
    return prefix;
}
