const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "build-shared", "Build a shared library") orelse true;
    const reuse_alloc = b.option(bool, "reuse-allocator", "Reuse the library allocator") orelse false;

    const library_name = "tree-sitter-bush";

    const lib = b.addLibrary(.{
        .name = library_name,
        .linkage = if (shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = if (shared) true else null,
        }),
    });

    lib.addCSourceFile(.{
        .file = b.path("tree-sitter-config/parser.c"),
        .flags = &.{"-std=c11"},
    });
    if (fileExists(b, "tree-sitter-config/scanner.c")) {
        lib.addCSourceFile(.{
            .file = b.path("tree-sitter-config/scanner.c"),
            .flags = &.{"-std=c11"},
        });
    }

    if (reuse_alloc) {
        lib.root_module.addCMacro("TREE_SITTER_REUSE_ALLOCATOR", "");
    }
    if (optimize == .Debug) {
        lib.root_module.addCMacro("TREE_SITTER_DEBUG", "");
    }

    lib.addIncludePath(b.path("tree-sitter-config"));
    lib.linkSystemLibrary("tree-sitter");

    b.installArtifact(lib);
    b.installFile("tree-sitter-config/node-types.json", "node-types.json");

    if (fileExists(b, "queries")) {
        b.installDirectory(.{
            .source_dir = b.path("queries"),
            .install_dir = .prefix,
            .install_subdir = "queries",
            .include_extensions = &.{"scm"},
        });
    }

    const module = b.addModule(library_name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport(library_name, module);
    tests.linkSystemLibrary("tree-sitter");

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const exe = b.addExecutable(.{
        .name = "bush",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.use_llvm = true;
    exe.use_lld = true;
    exe.root_module.addImport(library_name, module);
    exe.linkSystemLibrary("tree-sitter");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

inline fn fileExists(b: *std.Build, filename: []const u8) bool {
    const dir = b.build_root.handle;
    dir.access(filename, .{}) catch return false;
    return true;
}
