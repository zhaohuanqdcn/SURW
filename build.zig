const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "zigsched",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.force_pic = true;
    lib.linkLibC();
    b.installArtifact(lib);

    const test_executables = [_]struct {
        name: []const u8,
        source: []const u8,
        link_lib: bool,
    }{
        .{ .name = "create", .source = "test-resources/create.c", .link_lib = false },
        .{ .name = "exit", .source = "test-resources/exit.c", .link_lib = false },
        .{ .name = "lock", .source = "test-resources/lock.c", .link_lib = false },
        .{ .name = "barrier", .source = "test-resources/barrier.c", .link_lib = false },
        .{ .name = "unlock", .source = "test-resources/unlock.c", .link_lib = false },
        .{ .name = "cond", .source = "test-resources/cond.c", .link_lib = false },
        .{ .name = "broadcast", .source = "test-resources/broadcast.c", .link_lib = false },
        .{ .name = "abort", .source = "test-resources/abort.c", .link_lib = true },
        .{ .name = "rwlock", .source = "test-resources/rwlock.c", .link_lib = false },
        .{ .name = "rwlock_unlock", .source = "test-resources/rwlock_unlock.c", .link_lib = false },
        .{ .name = "wrlock_rdlock_unlock", .source = "test-resources/wrlock_rdlock_unlock.c", .link_lib = false },
        .{ .name = "determinism", .source = "test-resources/determinism.c", .link_lib = true },
    };

    const test_step = b.step("test", "Run library tests");

    for (test_executables) |exe_info| {
        const exe = b.addExecutable(.{
            .name = exe_info.name,
            .target = target,
            .optimize = optimize,
        });
        exe.addCSourceFile(.{
            .file = .{ .path = exe_info.source },
            .flags = &[_][]const u8{},
        });
        exe.linkLibC();
        if (exe_info.link_lib) {
            exe.linkLibrary(lib);
        }
        b.installArtifact(exe);
        test_step.dependOn(&exe.step);
    }
    const lib_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
}
