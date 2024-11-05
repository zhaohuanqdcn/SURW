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

    // b.installDirectory(std.build.InstallDirectoryOptions{ .source_dir = "src", .install_dir = std.build.InstallDir{ .custom = ".test" }, .install_subdir = "" });
    // const lib_test = b.addSharedLibrary(.{
    //     .name = "zigsched",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // lib_test.linkLibC();
    // b.installArtifact(lib_test);

    // b.installDirectory(std.build.InstallDirectoryOptions{ .source_dir = "test-resources", .install_dir = std.build.InstallDir{ .custom = ".test" }, .install_subdir = "" });

    const tst_exe = b.addExecutable(.{
        .name = "create",
        .root_source_file = .{ .path = "test-resources/create.c" },
        .target = target,
        .optimize = optimize,
    });
    tst_exe.linkLibC();
    b.installArtifact(tst_exe);

    const exit_tst_exe = b.addExecutable(.{
        .name = "exit",
        .root_source_file = .{ .path = "test-resources/exit.c" },
        .target = target,
        .optimize = optimize,
    });
    exit_tst_exe.linkLibC();
    b.installArtifact(exit_tst_exe);

    const lock_tst_exe = b.addExecutable(.{
        .name = "lock",
        .root_source_file = .{ .path = "test-resources/lock.c" },
        .target = target,
        .optimize = optimize,
    });
    lock_tst_exe.linkLibC();
    b.installArtifact(lock_tst_exe);

    const barrier_tst_exe = b.addExecutable(.{
        .name = "barrier",
        .root_source_file = .{ .path = "test-resources/barrier.c" },
        .target = target,
        .optimize = optimize,
    });
    barrier_tst_exe.linkLibC();
    b.installArtifact(barrier_tst_exe);

    const unlock_tst_exe = b.addExecutable(.{
        .name = "unlock",
        .root_source_file = .{ .path = "test-resources/unlock.c" },
        .target = target,
        .optimize = optimize,
    });
    unlock_tst_exe.linkLibC();
    b.installArtifact(unlock_tst_exe);

    const cond_tst_exe = b.addExecutable(.{
        .name = "cond",
        .root_source_file = .{ .path = "test-resources/cond.c" },
        .target = target,
        .optimize = optimize,
    });
    cond_tst_exe.linkLibC();
    b.installArtifact(cond_tst_exe);

    const broadcast_tst_exe = b.addExecutable(.{
        .name = "broadcast",
        .root_source_file = .{ .path = "test-resources/broadcast.c" },
        .target = target,
        .optimize = optimize,
    });
    broadcast_tst_exe.linkLibC();
    b.installArtifact(broadcast_tst_exe);

    const abort_tst_exe = b.addExecutable(.{
        .name = "abort",
        .root_source_file = .{ .path = "test-resources/abort.c" },
        .target = target,
        .optimize = optimize,
    });
    abort_tst_exe.linkLibC();
    abort_tst_exe.linkLibrary(lib);
    b.installArtifact(abort_tst_exe);

    const rwlock_tst_exe = b.addExecutable(.{
        .name = "rwlock",
        .root_source_file = .{ .path = "test-resources/rwlock.c" },
        .target = target,
        .optimize = optimize,
    });
    rwlock_tst_exe.linkLibC();
    b.installArtifact(rwlock_tst_exe);

    const rwlock_unlock_tst_exe = b.addExecutable(.{
        .name = "rwlock_unlock",
        .root_source_file = .{ .path = "test-resources/rwlock_unlock.c" },
        .target = target,
        .optimize = optimize,
    });
    rwlock_unlock_tst_exe.linkLibC();
    b.installArtifact(rwlock_unlock_tst_exe);

    const wrlock_rdlock_unlock_tst_exe = b.addExecutable(.{
        .name = "wrlock_rdlock_unlock",
        .root_source_file = .{ .path = "test-resources/wrlock_rdlock_unlock.c" },
        .target = target,
        .optimize = optimize,
    });
    wrlock_rdlock_unlock_tst_exe.linkLibC();
    b.installArtifact(wrlock_rdlock_unlock_tst_exe);

    const determinism_tst_exe = b.addExecutable(.{
        .name = "determinism",
        .root_source_file = .{ .path = "test-resources/determinism.c" },
        .target = target,
        .optimize = optimize,
    });
    determinism_tst_exe.linkLibC();
    determinism_tst_exe.linkLibrary(lib);
    b.installArtifact(determinism_tst_exe);

    // Creates a step for unit testing.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.linkLibC();

    const test_step = b.step("test", "Run library tests");
    // test_step.dependOn(&lib_test.step);
    test_step.dependOn(&tst_exe.step);
    test_step.dependOn(&exit_tst_exe.step);
    test_step.dependOn(&lock_tst_exe.step);
    test_step.dependOn(&unlock_tst_exe.step);
    test_step.dependOn(&cond_tst_exe.step);
    test_step.dependOn(&broadcast_tst_exe.step);
    test_step.dependOn(&abort_tst_exe.step);
    test_step.dependOn(&rwlock_tst_exe.step);
    test_step.dependOn(&rwlock_unlock_tst_exe.step);
    test_step.dependOn(&wrlock_rdlock_unlock_tst_exe.step);
    test_step.dependOn(&determinism_tst_exe.step);
    test_step.dependOn(&main_tests.step);
}
