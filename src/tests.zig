const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("stdlib.h");
});

const main = @import("main.zig");
const dbg_ck = main.dbg_ck;

fn str_contains(str: []const u8, pattern: []const u8) bool {
    var i: usize = 0;
    while (i <= str.len - pattern.len) {
        if (std.mem.eql(u8, str[i .. i + pattern.len], pattern)) {
            return true;
        }
        i += 1;
    }
    return false;
}

// TODO add test for double lock

test "create" {
    var alloc = std.testing.allocator;

    const sut_log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(sut_log_file_path) catch @panic("could not delete log file");

    const ret = c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/create");
    try testing.expect(ret == 0);

    const contents = try std.fs.cwd().readFileAlloc(alloc, sut_log_file_path, 8192);
    defer alloc.free(contents);

    // try testing.expectStringEndsWith(contents, "done!");
    try testing.expect(str_contains(contents, "done!"));
}

test "create intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/intercept.log";
    dbg_ck(c.setenv("LOG_FILE", log_file_path, 1));
    defer dbg_ck(c.unsetenv("LOG_FILE"));
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/create"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    // try testing.expectStringEndsWith(contents, "done!");
    try testing.expect(str_contains(contents, "fork"));
}

test "exit" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/exit"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    // TODO check return value in test
    // try testing.expect(str_contains(contents, "exited!"));
    try testing.expect(str_contains(contents, "done!"));
}

test "join intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/join_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/join_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/exit"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    // try testing.expectStringEndsWith(contents, "done!");
    try testing.expect(str_contains(contents, "join"));
}

test "lock" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/lock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "lock intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/lock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "acq"));
}

test "unlock" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/unlock_test.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete test log file");

    dbg_ck(c.system("PROG_LOG_FILE=.test/unlock_test.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/unlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "unlock intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/u_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/unlock_test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("PROG_LOG_FILE=.test/unlock_test.log LOG_FILE=.test/u_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/unlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "rel"));
}

test "barrier" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/barrier_test.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete test log file");

    dbg_ck(c.system("PROG_LOG_FILE=.test/barrier_test.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/barrier"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "barrier intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/barrier_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/barrier_test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("PROG_LOG_FILE=.test/barrier_test.log LOG_FILE=.test/barrier_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/barrier"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "rel"));
}

test "cond" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/cond"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "signal intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/sig_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/sig_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/cond"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "signal"));
}

test "wait intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/wait_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/wait_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/cond"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "wait"));
}

test "broadcast" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/broadcast"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "broadcast intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/broad_intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/broad_intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/broadcast"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "sigAll"));
}

test "abort on thread doesn't hang" {
    const ret = c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/abort");
    try testing.expect(ret != 0);
}

test "rwlock" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/rwlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "rwlock_unlock" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/rwlock_unlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "wrlock rdlock unlock" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/test.log";
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/wrlock_rdlock_unlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "done!"));
}

test "wrlock rdlock unlock intercepted" {
    var alloc = std.testing.allocator;

    const log_file_path = ".test/intercept.log";
    defer std.fs.cwd().deleteFile(log_file_path) catch @panic("could not delete log file");
    defer std.fs.cwd().deleteFile(".test/test.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LOG_FILE=.test/intercept.log LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/wrlock_rdlock_unlock"));

    const contents = try std.fs.cwd().readFileAlloc(alloc, log_file_path, 8192);
    defer alloc.free(contents);

    try testing.expect(str_contains(contents, "acq"));
    try testing.expect(str_contains(contents, "rel"));
}

test "sum is deterministic" {
    var alloc = std.testing.allocator;

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/determinism test-resources/determinism.c > .test/sum-a.log"));
    defer std.fs.cwd().deleteFile(".test/sum-a.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/determinism test-resources/determinism.c > .test/sum-b.log"));
    defer std.fs.cwd().deleteFile(".test/sum-b.log") catch @panic("could not delete test log file");

    const contents_a = try std.fs.cwd().readFileAlloc(alloc, ".test/sum-a.log", 8192);
    defer alloc.free(contents_a);

    const contents_b = try std.fs.cwd().readFileAlloc(alloc, ".test/sum-b.log", 8192);
    defer alloc.free(contents_b);

    var lines_a = std.mem.split(u8, contents_a, "\n");
    var last_line_a: ?[]const u8 = null;
    while (lines_a.next()) |l| {
        last_line_a = l;
    }

    var lines_b = std.mem.split(u8, contents_b, "\n");
    var last_line_b: ?[]const u8 = null;
    while (lines_b.next()) |l| {
        last_line_b = l;
    }

    try testing.expectEqualStrings(last_line_a.?, last_line_b.?);
}

test "seed changes schedule" {
    var alloc = std.testing.allocator;

    dbg_ck(c.system("RANDOM_SEED=3 LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/determinism test-resources/determinism.c 3 > .test/sum-a_d.log"));
    defer std.fs.cwd().deleteFile(".test/sum-a_d.log") catch @panic("could not delete test log file");

    dbg_ck(c.system("RANDOM_SEED=43 LD_PRELOAD=$(pwd)/zig-out/lib/libzigsched.so ./zig-out/bin/determinism test-resources/determinism.c 3 > .test/sum-b_d.log"));
    defer std.fs.cwd().deleteFile(".test/sum-b_d.log") catch @panic("could not delete test log file");

    const contents_a = try std.fs.cwd().readFileAlloc(alloc, ".test/sum-a_d.log", 8192);
    defer alloc.free(contents_a);

    const contents_b = try std.fs.cwd().readFileAlloc(alloc, ".test/sum-b_d.log", 8192);
    defer alloc.free(contents_b);

    var lines_a = std.mem.split(u8, contents_a, "\n");
    var last_line_a: ?[]const u8 = null;
    while (lines_a.next()) |l| {
        last_line_a = l;
    }

    var lines_b = std.mem.split(u8, contents_b, "\n");
    var last_line_b: ?[]const u8 = null;
    while (lines_b.next()) |l| {
        last_line_b = l;
    }

    // std.log.debug("last = {?s}", .{last_line_b);
    try testing.expectError(error.TestExpectedEqual, testing.expectEqualStrings(last_line_a.?, last_line_b.?));
}
