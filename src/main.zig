const std = @import("std");
const testing = std.testing;
pub const std_options = struct {
    // Set this to .info, .debug, .warn, or .err.
    pub const log_level = .debug;
};

const c = @cImport({
    @cInclude("dlfcn.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
    @cInclude("pthread.h");
    @cInclude("stdlib.h");
    @cInclude("errno.h");
});

const METHOD = enum(u32) {
    ALWAYS_FALSE = 0,
    SCHED_YIELD = 1,
    TARGET_ADDR = 2,
    ALWAYS_TRUE = 3,
    LOCK_AS_MEM = 4,
};
var method = METHOD.ALWAYS_FALSE;

const ALG = enum(u32) {
    NO_SWITCH = 0,
    RANDOM_WALK = 1,
    PCT = 2,
    POS = 3,
    UNIFORM_RW = 4,
    RANDOM_PRI = 5,
};
var alg1 = ALG.RANDOM_WALK;
var alg2 = ALG.RANDOM_WALK;

// Used by PCT
var MAX_THREAD: u32 = 1000;
var MAX_EVENTS: u32 = 100000;
const MAX_d: u16 = 100;
var PCT_d: u16 = 5;
var change_points: [MAX_d]u32 = [_]u32{0} ** MAX_d;
var EVENT_COUNT: u32 = 0;
var INTERESTING_EVENT_COUNT: u32 = 0;

// Used by Uniform RW
var alg1_next_id: i32 = -1;
var target_mem_addr: ?u64 = null;
var end_mem_addr: ?u64 = null;
var numbers: std.AutoHashMap(u32, u16) = undefined;

// Starvation prevention
var STAY_COUNT: u32 = 0;
const TIMEOUT: u32 = 1000;

const TRACE = false;
const TRACE_CTXT_SWITCH = false;
const TRACE_SY_SWITCH = false;

var PRNG = std.rand.DefaultPrng.init(0);

pub const PTHREAD_COND_INITIALIZER = std.c.PTHREAD_COND_INITIALIZER;

const RTLD_NEXT_VAL: isize = -1;
const RTLD_NEXT: ?*anyopaque = @ptrFromInt(@as(usize, @bitCast(RTLD_NEXT_VAL)));

var real_malloc: *(fn (size_bytes: usize) [*c]u8) = undefined;
var real_free: *(fn (ptr: [*c]u8) void) = undefined;
var real_realloc: *(fn (ptr: [*c]u8, size_bytes: usize) [*c]u8) = undefined;
var real_calloc: *(fn (nitems: usize, size: usize) [*c]u8) = undefined;

const START_TYPE = *const fn (?*anyopaque) callconv(.C) ?*anyopaque;
const PTHREAD_CREATE_TYPE = *(fn (thread: *c.pthread_t, attr: ?*c.pthread_attr_t, start_routine: START_TYPE, arg: ?*anyopaque) c_int);
var real_pthread_create: PTHREAD_CREATE_TYPE = undefined;

const PTHREAD_JOIN_TYPE = *(fn (thread: *c.pthread_t, retval: ?*anyopaque) c_int);
var real_pthread_join: PTHREAD_JOIN_TYPE = undefined;

const PTHREAD_EXIT_TYPE = *(fn (retval: ?*anyopaque) c_int);
var real_pthread_exit: PTHREAD_EXIT_TYPE = undefined;

const PTHREAD_MTX_LK_TYPE = *(fn (lock: ?*std.c.pthread_mutex_t) c_int);
var real_pthread_mutex_lock: PTHREAD_MTX_LK_TYPE = undefined;
var real_pthread_mutex_unlock: PTHREAD_MTX_LK_TYPE = undefined;

const PTHREAD_CND_WAIT_TYPE = *(fn (cond: ?*std.c.pthread_cond_t, lock: ?*std.c.pthread_mutex_t) c_int);
var real_pthread_cond_wait: PTHREAD_CND_WAIT_TYPE = undefined;

const PTHREAD_CND_SIG_TYPE = *(fn (cond: ?*std.c.pthread_cond_t) c_int);
var real_pthread_cond_signal: PTHREAD_CND_SIG_TYPE = undefined;
var real_pthread_cond_broadcast: PTHREAD_CND_SIG_TYPE = undefined;

const PTHREAD_BAR_INIT_TYPE = *(fn (barrier: ?*c.pthread_barrier_t, attr: ?*const c.pthread_barrierattr_t, count: c_uint) c_int);
var real_pthread_barrier_init: PTHREAD_BAR_INIT_TYPE = undefined;
const PTHREAD_BAR_WAIT_TYPE = *(fn (barrier: ?*c.pthread_barrier_t) c_int);
var real_pthread_barrier_wait: PTHREAD_BAR_WAIT_TYPE = undefined;

const PTHREAD_RWLOCK_LOCK_TYPE = *(fn (rwlock: ?*std.c.pthread_rwlock_t) c_int);
var real_pthread_rwlock_rdlock: PTHREAD_RWLOCK_LOCK_TYPE = undefined;
var real_pthread_rwlock_wrlock: PTHREAD_RWLOCK_LOCK_TYPE = undefined;
var real_pthread_rwlock_unlock: PTHREAD_RWLOCK_LOCK_TYPE = undefined;

const PTHREAD_CANCEL_TYPE = *(fn (t: ?*std.c.pthread_t) c_int);
var real_pthread_cancel: PTHREAD_CANCEL_TYPE = undefined;

pub fn dbg_ck(retcode: c_int) void {
    std.debug.assert(retcode == 0);
}

fn is_pct() bool {
    return alg2 == ALG.PCT;
}
fn is_uniform_rw() bool {
    return alg1 == ALG.UNIFORM_RW;
}

fn pct_init() void {
    const max_t = c.getenv("MAX_THREAD");
    if (max_t != null) {
        MAX_THREAD = std.fmt.parseUnsigned(u32, std.mem.span(max_t), 10) catch @panic("Parse MAX_THREAD error");
    }
    const max_e = c.getenv("MAX_EVENTS");
    if (max_e != null) {
        MAX_EVENTS = std.fmt.parseUnsigned(u32, std.mem.span(max_e), 10) catch @panic("Parse MAX_EVENTS error");
    }
    const max_d = c.getenv("MAX_DEPTH");
    if (max_d != null) {
        PCT_d = std.fmt.parseUnsigned(u16, std.mem.span(max_d), 10) catch @panic("Parse MAX_DEPTH error");
    }
    std.log.debug("PCT depth = {d}", .{PCT_d});
    for (0..PCT_d - 1) |i| {
        change_points[i] = PRNG.random().uintLessThan(u32, MAX_EVENTS);
    }
}

fn urw_init() !void {
    const file = try std.fs.cwd().openFile("estimate.in", .{});
    defer file.close();

    const allocator = std.heap.page_allocator;
    const buffer_size = 2048;
    const read_bytes = try file.readToEndAlloc(allocator, buffer_size);
    defer allocator.free(read_bytes);

    numbers = std.AutoHashMap(u32, u16).init(SAFE_ALLOC);
    var is_count: bool = false;
    var thr: u32 = 0;
    var iter = std.mem.split(u8, read_bytes, "\n");
    while (iter.next()) |word| {
        if (is_count) {
            const num = std.fmt.parseUnsigned(u16, word, 10) catch break;
            try numbers.put(thr, num);
            std.log.debug("#{d} events: {d}", .{ thr, num });
            is_count = false;
        } else {
            thr = std.fmt.parseUnsigned(u32, word, 10) catch break;
            is_count = true;
        }
    }
}

fn parse_method(name: []const u8) METHOD {
    if (std.mem.eql(u8, name, "always_false")) {
        return METHOD.ALWAYS_FALSE;
    } else if (std.mem.eql(u8, name, "sched_yield")) {
        return METHOD.SCHED_YIELD;
    } else if (std.mem.eql(u8, name, "memory_addr")) {
        return METHOD.TARGET_ADDR;
    } else if (std.mem.eql(u8, name, "always_true")) {
        return METHOD.ALWAYS_TRUE;
    } else if (std.mem.eql(u8, name, "lock_addr")) {
        return METHOD.LOCK_AS_MEM;
    } else {
        @panic("Unrecognized METHOD. Please choose from [always_false, sched_yield, memory_addr].");
    }
}

fn parse_algo(name: []const u8) ALG {
    if (std.mem.eql(u8, name, "ns")) {
        return ALG.NO_SWITCH;
    } else if (std.mem.eql(u8, name, "rw")) {
        return ALG.RANDOM_WALK;
    } else if (std.mem.eql(u8, name, "rp")) {
        return ALG.RANDOM_PRI;
    } else if (std.mem.eql(u8, name, "pct")) {
        return ALG.PCT;
    } else if (std.mem.eql(u8, name, "pos")) {
        return ALG.POS;
    } else if (std.mem.eql(u8, name, "urw")) {
        return ALG.UNIFORM_RW;
    } else {
        @panic("Unrecognized ALG. Please choose from [ns, rw, rp, pct, pos, urw].");
    }
}

var logfile_name: ?[]u8 = undefined;
var logfile_writer: ?std.fs.File.Writer = undefined;

var SHOULD_LOG = false;
var HAS_INITIALIZED = false;
export fn init() void {
    const r = @cmpxchgStrong(bool, &HAS_INITIALIZED, false, true, std.atomic.Ordering.Monotonic, std.atomic.Ordering.Monotonic);
    if (r != null) {
        return;
    }
    std.log.debug("Start initialization...", .{});

    real_malloc = @as(*(fn (size_bytes: usize) [*c]u8), @ptrCast(std.c.dlsym(RTLD_NEXT, "malloc").?));
    real_free = @as(*(fn (ptr: [*c]u8) void), @ptrCast(std.c.dlsym(RTLD_NEXT, "free").?));
    real_realloc = @as(*(fn (ptr: [*c]u8, size_bytes: usize) [*c]u8), @ptrCast(std.c.dlsym(RTLD_NEXT, "realloc").?));
    real_calloc = @as(*(fn (nitems: usize, size: usize) [*c]u8), @ptrCast(std.c.dlsym(RTLD_NEXT, "calloc").?));

    real_pthread_create = @as(PTHREAD_CREATE_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_create").?));
    real_pthread_join = @as(PTHREAD_JOIN_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_join").?));
    real_pthread_exit = @as(PTHREAD_EXIT_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_exit").?));
    real_pthread_mutex_lock = @as(PTHREAD_MTX_LK_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_mutex_lock").?));
    real_pthread_mutex_unlock = @as(PTHREAD_MTX_LK_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_mutex_unlock").?));
    real_pthread_cond_wait = @as(PTHREAD_CND_WAIT_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_cond_wait").?));
    real_pthread_cond_signal = @as(PTHREAD_CND_SIG_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_cond_signal").?));
    real_pthread_cond_broadcast = @as(PTHREAD_CND_SIG_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_cond_broadcast").?));
    real_pthread_barrier_init = @as(PTHREAD_BAR_INIT_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_barrier_init").?));
    real_pthread_barrier_wait = @as(PTHREAD_BAR_WAIT_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_barrier_wait").?));
    real_pthread_rwlock_rdlock = @as(PTHREAD_RWLOCK_LOCK_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_rwlock_rdlock").?));
    real_pthread_rwlock_wrlock = @as(PTHREAD_RWLOCK_LOCK_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_rwlock_wrlock").?));
    real_pthread_rwlock_unlock = @as(PTHREAD_RWLOCK_LOCK_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_rwlock_unlock").?));
    real_pthread_cancel = @as(PTHREAD_CANCEL_TYPE, @ptrCast(std.c.dlsym(RTLD_NEXT, "pthread_cancel").?));

    const maybe_logfile_name = c.getenv("LOG_FILE");
    if (maybe_logfile_name != null) {
        logfile_name = std.mem.span(maybe_logfile_name);
        SHOULD_LOG = true;
        const logfile_file = std.fs.cwd().createFile(logfile_name.?, .{}) catch @panic("Cannot open logfile!");
        logfile_writer = logfile_file.writer();
    }
    const rand_seed = c.getenv("RANDOM_SEED");
    if (rand_seed != null) {
        const rand_seed_parsed = std.fmt.parseUnsigned(u64, std.mem.span(rand_seed), 10) catch @panic("Parse RANDOM_SEED error");
        // const seed = @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
        PRNG = std.rand.DefaultPrng.init(rand_seed_parsed);
        std.log.debug("Random seed set", .{});
    }
    const method_str = c.getenv("METHOD");
    if (method_str != null) {
        method = parse_method(std.mem.sliceTo(method_str, 0));
        std.log.debug("Method {s} is chosen", .{method_str});
    }

    if (method == METHOD.TARGET_ADDR or method == METHOD.LOCK_AS_MEM) {
        const target_addr = c.getenv("TARGET_ADDR");
        if (target_addr != null) {
            target_mem_addr = std.fmt.parseUnsigned(u64, std.mem.span(target_addr), 16) catch @panic("Parse TARGET_ADDR error");
            std.log.debug("target mem address @{?}", .{target_mem_addr});
        }
        const end_addr = c.getenv("END_ADDR");
        if (end_addr != null) {
            end_mem_addr = std.fmt.parseUnsigned(u64, std.mem.span(end_addr), 16) catch @panic("Parse END_ADDR error");
            std.log.debug("end mem address @{?}", .{end_mem_addr});
        } else {
            end_mem_addr = target_mem_addr;
        }
    }

    const alg1_str = c.getenv("ALG1");
    if (alg1_str != null) {
        alg1 = parse_algo(std.mem.sliceTo(alg1_str, 0));
        std.log.debug("{s} is chosen as algorithm 1.", .{alg1_str});
    }
    const alg2_str = c.getenv("ALG2");
    if (alg2_str != null) {
        alg2 = parse_algo(std.mem.sliceTo(alg2_str, 0));
        std.log.debug("{s} is chosen as algorithm 2.", .{alg2_str});
    }

    // TODO: disallow pct/urw

    if (is_pct()) {
        pct_init();
    }

    if (is_uniform_rw()) {
        urw_init() catch @panic("Error initializing URW");
    }

    current_thread = Thread.init(0);
    next_thread_id = current_thread.tid;
    threads = std.ArrayList(*Thread).init(SAFE_ALLOC);
    mutexes = std.AutoArrayHashMap(?*std.c.pthread_mutex_t, Mutex).init(SAFE_ALLOC);
    rwlocks = std.AutoArrayHashMap(?*std.c.pthread_rwlock_t, Rwlock).init(SAFE_ALLOC);
    barriers = std.AutoArrayHashMap(?*c.pthread_barrier_t, Barrier).init(SAFE_ALLOC);
    conds = std.AutoArrayHashMap(?*std.c.pthread_cond_t, Cond).init(SAFE_ALLOC);
    threads.append(&current_thread) catch @panic("OOM");

    _ = current_thread;

    std.log.debug("End initialization.", .{});
}

var GPA = std.heap.GeneralPurposeAllocator(.{}){};
const SAFE_ALLOC = GPA.allocator();

const Metadata = struct {
    len: usize,
};

const EVENT_TYPE = enum(u32) {
    MEM_OP = 0,
    SCH_YIELD = 1,
    THR_CREATE = 2,
    LOCK_ACQ = 3,
    LOCK_REL = 4,
};

const Event = struct {
    op: EVENT_TYPE,
    instr_addr: ?*const anyopaque,
    mem_addr: ?*const anyopaque,
    size: usize,
    is_write: bool,
};

fn get_events_left(det_id: u32) u16 {
    if (is_uniform_rw() and numbers.contains(det_id)) {
        return numbers.get(det_id).?;
    } else return 0;
}

const Thread = struct {
    tid: c.pid_t,
    det_id: u32,
    num_children: u32,
    pthread: c.pthread_t,
    is_blocking: bool = false,
    suspend_cond: std.c.pthread_cond_t = PTHREAD_COND_INITIALIZER,
    retval: ?*anyopaque = null,
    next_event: ?Event = null,
    waiters: std.ArrayList(*Thread),
    priority: i16 = -1,
    events_left: u16 = 0,
    alg_blocked: bool = false,

    fn init(det_id: u32) Thread {
        return Thread{ .tid = std.os.linux.gettid(), .det_id = det_id, .num_children = 0, .pthread = c.pthread_self(), .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC), .events_left = get_events_left(det_id) };
    }

    fn init_alloc(allocator: std.mem.Allocator, det_id: u32) *Thread {
        var t = allocator.create(Thread);
        t.* = Thread{ .tid = std.os.linux.gettid(), .det_id = det_id, .num_children = 0, .pthread = c.pthread_self(), .waiters = std.ArrayList(*Thread).init(allocator), .events_left = get_events_left(det_id) };
        return t;
    }
};

const Mutex = struct {
    owner: c.pid_t,
    recursive_count: u32,
    waiters: std.ArrayList(*Thread),
};

const Rwlock = struct {
    owner: c.pid_t,
    is_exclusive: bool,
    recursive_count: u32,
    waiters: std.ArrayList(*Thread),
    waiter_is_rdlock: std.ArrayList(bool),
};

const Cond = struct {
    cond: ?*std.c.pthread_cond_t,
    mutex: ?*std.c.pthread_mutex_t,
    waiters: std.ArrayList(*Thread),
};

const Barrier = struct {
    count: c_uint,
    waiters: std.ArrayList(*Thread),
};

const ThreadStartArg = struct {
    start_routine: START_TYPE,
    args: ?*anyopaque,
    start_cond: std.c.pthread_cond_t,
    det_id: u32,
};

var global_mutex: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER;

threadlocal var current_thread: Thread = undefined;
var next_thread_id: c.pid_t = undefined;

var threads: std.ArrayList(*Thread) = undefined;
var mutexes: std.AutoArrayHashMap(?*std.c.pthread_mutex_t, Mutex) = undefined;
var rwlocks: std.AutoArrayHashMap(?*std.c.pthread_rwlock_t, Rwlock) = undefined;
var barriers: std.AutoArrayHashMap(?*c.pthread_barrier_t, Barrier) = undefined;
var conds: std.AutoArrayHashMap(?*std.c.pthread_cond_t, Cond) = undefined;

fn log_state() void {
    std.log.debug("[{}] STATE", .{current_thread.det_id});
    for (threads.items) |t| {
        for (t.waiters.items) |w| {
            std.log.debug("\t thread {}: {}", .{ t.det_id, w.det_id });
        }
    }
    for (mutexes.keys()) |k| {
        for (mutexes.get(k).?.waiters.items) |w| {
            std.log.debug("\t {*}: {}", .{ k, w.det_id });
        }
    }

    for (conds.keys()) |k| {
        for (conds.get(k).?.waiters.items) |w| {
            std.log.debug("\t {*}: {}", .{ k, w.det_id });
        }
    }

    for (barriers.keys()) |k| {
        for (barriers.get(k).?.waiters.items) |w| {
            std.log.debug("\t {*}: {}", .{ k, w.det_id });
        }
    }
}

// METHODS

fn is_sched_yield(t: *Thread) bool {
    return t.next_event != null and t.next_event.?.op == EVENT_TYPE.SCH_YIELD;
}

fn is_thread_create(t: *Thread) bool {
    return t.next_event != null and t.next_event.?.op == EVENT_TYPE.THR_CREATE;
}

fn is_mem_op(t: *Thread) bool {
    return t.next_event != null and t.next_event.?.op == EVENT_TYPE.MEM_OP and t.next_event.?.mem_addr != null;
}

fn is_target_mem(t: *Thread) bool {
    return is_mem_op(t) and target_mem_addr != null and
        (@intFromPtr(t.next_event.?.mem_addr.?) >= target_mem_addr.? and @intFromPtr(t.next_event.?.mem_addr.?) <= end_mem_addr.?);
}

fn is_racy(t1: *Thread, t2: *Thread) bool {
    return is_mem_op(t1) and is_mem_op(t2) and
        (t1.next_event.?.mem_addr.? == t2.next_event.?.mem_addr.?) and
        (t1.next_event.?.is_write or t2.next_event.?.is_write);
}

fn is_interesting(t: *Thread) bool {
    return switch (method) {
        METHOD.ALWAYS_FALSE => false,
        METHOD.ALWAYS_TRUE => true,
        METHOD.SCHED_YIELD => is_sched_yield(t),
        METHOD.TARGET_ADDR => is_target_mem(t),
        METHOD.LOCK_AS_MEM => is_target_mem(t),
    };
}

// UNBLOCKING

fn generic_unblock(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) bool {
    alg1_next_id = -1;
    var unblocked = false;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                t.alg_blocked = false;
                unblocked = true;
            }
            // std.log.debug("#{} unblocked", .{t.det_id});
        }
    }
    return unblocked;
}

// ALGORITHMS

fn choose_highest_priority(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    var max_priority: i16 = -1;
    var max_priority_thread_idx: ?usize = null;
    var idx: usize = 0;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                // std.log.debug("{} blocked", .{t.det_id});
                idx += 1;
                continue;
            }
            if (t.priority < 0) {
                t.priority = @as(i16, @bitCast(PRNG.random().uintLessThan(u16, 10000)));
            }
            if (t.priority > max_priority) {
                max_priority = t.priority;
                max_priority_thread_idx = idx;
            }
        }
        idx += 1;
    }
    if (max_priority_thread_idx) |t_idx| {
        return t_idx;
    } else {
        return MAX_THREAD + 1;
    }
}

fn no_switch(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    if (!allow_blocking and current_thread.is_blocking) {
        return random_walk(threads_to_choose, allow_blocking);
    } else if (current_thread.alg_blocked) {
        return random_walk(threads_to_choose, allow_blocking);
    } else {
        var idx: usize = 0;
        for (threads_to_choose.items) |t| {
            if (t.det_id == current_thread.det_id) {
                return idx;
            }
            idx += 1;
        }
        // current_thread not found
        return random_walk(threads_to_choose, allow_blocking);
    }
}

fn random_walk(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    var total: u32 = 0;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                continue;
            }
            total += 1;
        }
    }
    if (total == 0) {
        return MAX_THREAD + 1;
    }
    var rand: i32 = @as(i32, @bitCast(PRNG.random().uintLessThan(u32, total))) + 1;
    var idx: usize = 0;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                idx += 1;
                continue;
            }
            rand -= 1;
            if (rand <= 0) {
                return idx;
            }
        }
        idx += 1;
    }
    return MAX_THREAD + 1;
}

fn random_pri(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    return choose_highest_priority(threads_to_choose, allow_blocking);
}

fn pos(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    return choose_highest_priority(threads_to_choose, allow_blocking);
}

fn pct(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    return choose_highest_priority(threads_to_choose, allow_blocking);
}

fn uniform_rw(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    var total_events_left: u32 = 0;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                continue;
            }
            total_events_left += t.events_left;
        }
    }
    var idx: usize = 0;
    var rand_events: i32 = @as(i32, @bitCast(PRNG.random().uintLessThan(u32, total_events_left))) + 1;
    // std.log.debug("rand: {d}", .{rand_events});
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (t.alg_blocked) {
                continue;
            }
            rand_events -= t.events_left;
            if (rand_events <= 0 and t.events_left > 0) {
                std.log.debug("#{d} selected w.p. {d}/{d}", .{ t.det_id, t.events_left, total_events_left });
                return idx;
            }
        }
        idx += 1;
    }
    return MAX_THREAD + 1;
}

// CALLBACKS

fn pri_callback(t_idx: usize, threads_to_choose: *std.ArrayList(*Thread)) void {
    var thr = threads_to_choose.items[t_idx];
    thr.priority = -1;
}

fn pos_callback(t_idx: usize, threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) void {
    var thr = threads_to_choose.items[t_idx];
    thr.priority = -1;
    for (threads_to_choose.items) |t| {
        if (allow_blocking or !t.is_blocking) {
            if (is_racy(t, thr)) {
                t.priority = -1;
            }
        }
    }
}

fn pct_callback(t_idx: usize, threads_to_choose: *std.ArrayList(*Thread)) void {
    var thr = threads_to_choose.items[t_idx];
    for (0..PCT_d - 1) |i| {
        if (EVENT_COUNT == change_points[i]) {
            thr.priority = @intCast(i);
            std.log.debug("pct change points at {d}", .{EVENT_COUNT});
            break;
        }
    }
}

fn urw_callback(t_idx: usize, threads_to_choose: *std.ArrayList(*Thread)) void {
    var thr = threads_to_choose.items[t_idx];
    thr.events_left -= 1;
}

fn empty_callback() void {}

fn reset_pct(threads_to_choose: *std.ArrayList(*Thread)) void {
    for (0..PCT_d - 1) |i| {
        change_points[i] = PRNG.random().uintLessThan(u32, MAX_EVENTS);
    }
    reset_priority(threads_to_choose);
    EVENT_COUNT %= MAX_EVENTS;
}

fn reset_priority(threads_to_choose: *std.ArrayList(*Thread)) void {
    for (threads_to_choose.items) |t| {
        t.priority = -1;
    }
    std.log.debug("priorities reset", .{});
    _ = generic_unblock(threads_to_choose, true);
}

// MULTIPLEXING

fn choose_with_algorithm(alg: ALG, threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    return switch (alg) {
        ALG.NO_SWITCH => no_switch(threads_to_choose, allow_blocking),
        ALG.RANDOM_WALK => random_walk(threads_to_choose, allow_blocking),
        ALG.POS => pos(threads_to_choose, allow_blocking),
        ALG.PCT => pct(threads_to_choose, allow_blocking),
        ALG.UNIFORM_RW => uniform_rw(threads_to_choose, allow_blocking),
        ALG.RANDOM_PRI => random_pri(threads_to_choose, allow_blocking),
    };
}

fn callback_with_algorithm(alg: ALG, t_idx: usize, threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) void {
    return switch (alg) {
        ALG.NO_SWITCH => empty_callback(),
        ALG.RANDOM_WALK => empty_callback(),
        ALG.POS => pos_callback(t_idx, threads_to_choose, allow_blocking),
        ALG.PCT => pct_callback(t_idx, threads_to_choose),
        ALG.UNIFORM_RW => urw_callback(t_idx, threads_to_choose),
        ALG.RANDOM_PRI => pri_callback(t_idx, threads_to_choose),
    };
}

fn deadlock(threads_to_choose: *std.ArrayList(*Thread)) void {
    std.log.debug("{} threads total", .{threads_to_choose.items.len});
    log_state();
    @panic("No active threads!\n");
}

// Main Scheduling function

fn choose_next_thread_idx(threads_to_choose: *std.ArrayList(*Thread), comptime allow_blocking: bool) usize {
    if (TRACE) {
        const start = std.time.Instant.now() catch @panic("No time available");
        defer {
            const end = std.time.Instant.now() catch @panic("No time available");
            const elapsed = end.since(start);
            std.debug.print("@@@choose_next_thread_idx,{}\n", .{elapsed});
        }
    }
    var t_idx: usize = choose_with_algorithm(alg2, threads_to_choose, allow_blocking);
    if (t_idx >= threads_to_choose.items.len) {
        // alg1_next_id is blocked. unblock other threads to continue
        var unblocked = generic_unblock(threads_to_choose, allow_blocking);
        if (!unblocked) {
            deadlock(threads_to_choose);
        }
        std.log.debug("all threads unblocked by alg1", .{});
        return choose_next_thread_idx(threads_to_choose, allow_blocking);
    }
    var thr = threads_to_choose.items[t_idx];

    if (!thr.is_blocking and !thr.alg_blocked and is_interesting(thr)) {
        if (thr.events_left == 0)
            thr.events_left += 1;
        // choose alg1_next_id with alg1
        if (alg1_next_id < 0) {
            var next_idx: usize = choose_with_algorithm(alg1, threads_to_choose, allow_blocking);
            alg1_next_id = @intCast(threads_to_choose.items[next_idx].det_id);
        }
        // block unmatched thread
        if (thr.det_id != alg1_next_id) {
            thr.alg_blocked = true;
            return choose_next_thread_idx(threads_to_choose, allow_blocking);
        }
        // continue execution with alg1
        else {
            INTERESTING_EVENT_COUNT += 1;
            callback_with_algorithm(alg1, t_idx, threads_to_choose, allow_blocking);
            thr.next_event = null;
            _ = generic_unblock(threads_to_choose, allow_blocking);
            // std.log.debug("#{d} executed by alg1", .{thr.det_id});
        }
    } else {
        // not interesting: continue with alg2
        EVENT_COUNT += 1;
        if (EVENT_COUNT >= MAX_EVENTS and is_pct()) {
            reset_pct(threads_to_choose);
        }
        callback_with_algorithm(alg2, t_idx, threads_to_choose, allow_blocking);
        thr.next_event = null;
        // std.log.debug("#{d} executed by alg2", .{thr.det_id});
    }

    if (thr.det_id == current_thread.det_id) {
        STAY_COUNT += 1;
        // minimal fairness
        // otherwise, busy waiting may stall the program
        if (STAY_COUNT >= TIMEOUT) {
            reset_priority(threads_to_choose);
            STAY_COUNT = 0;
        }
    } else STAY_COUNT = 0;
    return t_idx;
}
var ctxt_switch_start: ?std.time.Instant = null;
var ctxt_switch_end: ?std.time.Instant = null;

fn resume_next_thread(next: *Thread, comptime and_suspend: bool) void {
    if (next != &current_thread) {
        if (TRACE_CTXT_SWITCH) {
            ctxt_switch_start = std.time.Instant.now() catch @panic("No time avail");
        }
        const r_sig = real_pthread_cond_signal(&next.suspend_cond);
        _ = r_sig;
        if (and_suspend) {
            suspend_current();
        }
        return;
    } else {
        return;
    }
}

fn suspend_current() void {
    dbg_ck(real_pthread_cond_wait(&current_thread.suspend_cond, &global_mutex));
    if (TRACE_CTXT_SWITCH) {
        ctxt_switch_end = std.time.Instant.now() catch @panic("No time avail");
        const elapsed = ctxt_switch_end.?.since(ctxt_switch_start.?);
        std.debug.print("@@@ctxt_switch,{}\n", .{elapsed});
    }
}

fn context_switch() void {
    // std.log.debug("# of threads: {d}", .{threads.items.len});
    if (threads.items.len == 1) {
        if (is_interesting(threads.items[0])) {
            INTERESTING_EVENT_COUNT += 1;
            if (threads.items[0].events_left > 0) {
                threads.items[0].events_left -= 1;
            }
        } else {
            EVENT_COUNT += 1;
        }
        threads.items[0].next_event = null;
        return;
    }
    var t = threads.items[choose_next_thread_idx(&threads, false)];
    resume_next_thread(t, true);
}

export fn pthread_create(thread: *c.pthread_t, attr: ?*c.pthread_attr_t, start_routine: START_TYPE, args: ?*anyopaque) c_int {
    init();

    current_thread.next_event = Event{
        .op = EVENT_TYPE.THR_CREATE,
        .instr_addr = null,
        .mem_addr = null,
        .size = 0,
        .is_write = false,
    };

    var start_arg = SAFE_ALLOC.create(ThreadStartArg) catch @panic("OOM");
    start_arg.start_routine = start_routine;
    start_arg.args = args;
    start_arg.start_cond = std.c.PTHREAD_COND_INITIALIZER;
    std.debug.assert(current_thread.num_children < 999);
    std.debug.assert(current_thread.det_id + 1000 < (2 << 32));
    start_arg.det_id = ((current_thread.det_id / 1000 + 1) * 1000) + ((current_thread.det_id % 100) * 100) + current_thread.num_children + 1;

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    const r = real_pthread_create(thread, attr, thread_start_wrapper, @as(?*anyopaque, @ptrCast(start_arg)));
    std.log.debug("[{}] BLOCKING done real create, blocking on {*}!", .{ current_thread.det_id, &start_arg.*.start_cond });
    current_thread.is_blocking = true;
    dbg_ck(real_pthread_cond_wait(&start_arg.*.start_cond, &global_mutex));
    std.log.debug("[{}] done wait create!", .{current_thread.det_id});
    current_thread.num_children += 1;
    current_thread.is_blocking = false;

    // non-urw: alg1_next_id is outdated; reselect with the new thread created
    if (!is_uniform_rw() and method != METHOD.ALWAYS_FALSE) {
        alg1_next_id = -1;
        _ = generic_unblock(&threads, false);
    }
    // urw: with probability, transfer alg1_next_id to its child
    if (is_uniform_rw() and current_thread.events_left > 0) {
        var child_event = get_events_left(start_arg.det_id);

        if (current_thread.det_id == alg1_next_id) {
            var rand_events: i32 = @as(i32, @bitCast(PRNG.random().uintLessThan(u32, current_thread.events_left))) + 1;
            if (child_event >= rand_events) {
                alg1_next_id = @intCast(start_arg.det_id);
                std.log.debug("#{d} selected by parent #{d}", .{ start_arg.det_id, current_thread.det_id });
            } else {
                std.log.debug("staying on parent #{d}", .{current_thread.det_id});
            }
        }
        // update parent count
        if (current_thread.events_left >= child_event) {
            current_thread.events_left -= child_event;
        } else {
            current_thread.events_left = 0;
        }
        // std.log.debug("parent thread event count = {d}", .{current_thread.events_left});
    }

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|fork({})|0\n", .{ current_thread.det_id, start_arg.det_id }) catch @panic("Failed to log to file");
        }
    }

    context_switch();
    return r;
}

fn thread_start_wrapper(arg: ?*anyopaque) callconv(.C) ?*anyopaque {
    var start_arg: *ThreadStartArg align(@alignOf(ThreadStartArg)) = @as(*ThreadStartArg, @ptrCast(@alignCast(arg)));
    current_thread = Thread.init(start_arg.det_id);
    dbg_ck(real_pthread_mutex_lock(&global_mutex));

    threads.append(&current_thread) catch @panic("OOM");

    std.log.debug("[{}] new thread started, of {}, signal {*}", .{ current_thread.det_id, threads.items.len, &start_arg.*.start_cond });
    dbg_ck(real_pthread_cond_signal(&start_arg.*.start_cond));
    suspend_current();
    dbg_ck(real_pthread_mutex_unlock(&global_mutex));

    var retval = start_arg.start_routine(start_arg.args);
    std.log.debug("[{}] exiting from return of {}", .{ current_thread.det_id, threads.items.len });
    dbg_ck(pthread_exit(retval));
    return retval; // unreachable
}

// TODO wrap pthread cancel as well

fn thread_exit_wrapper_internal() callconv(.C) void {
    std.log.debug("[{}] Reached exit wrapper", .{current_thread.det_id});
    var i: u32 = 0;
    while (i < threads.items.len) {
        if (threads.items[i] == &current_thread) {
            const removed = threads.swapRemove(i);
            _ = removed;
            break;
        }
        i += 1;
    }

    for (current_thread.waiters.items) |waiter| {
        waiter.is_blocking = false;
    }

    current_thread.is_blocking = true; // hack to avoid staying on this thread
    current_thread.events_left = 0;

    var t = threads.items[choose_next_thread_idx(&threads, false)];
    resume_next_thread(t, false);
}

export fn pthread_join(thread: *c.pthread_t, retval: ?*anyopaque) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var det_id: ?u32 = null;
    for (threads.items) |t| {
        if (t.pthread == thread.*) {
            t.waiters.append(&current_thread) catch @panic("OOM");
            std.log.debug("[{}] BLOCKING joining on {}", .{ current_thread.det_id, t.det_id });
            current_thread.is_blocking = true;
            det_id = t.det_id;
            context_switch();
            break;
        }
    }
    std.log.debug("[{}] Unblocked from join!... ", .{current_thread.det_id});
    const r = real_pthread_join(thread, retval);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|join({?})|0\n", .{
                current_thread.det_id, det_id,
            }) catch @panic("Failed to log to file");
        }
    }

    return r;
}

export fn pthread_exit(retval: ?*anyopaque) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    context_switch();

    thread_exit_wrapper_internal();

    dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    return real_pthread_exit(retval);
}

export fn pthread_barrier_init(noalias barrier: ?*c.pthread_barrier_t, noalias attr: ?*const c.pthread_barrierattr_t, count: c_uint) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var r = real_pthread_barrier_init(barrier, attr, count);
    if (r == 0) {
        barriers.put(barrier, Barrier{
            .count = count,
            .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC),
        }) catch @panic("OOM");
    }

    return r;
}

export fn pthread_barrier_wait(barrier: ?*c.pthread_barrier_t) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    std.log.debug("[{}] BLOCKING barrier wait on {*}", .{ current_thread.det_id, barrier });

    var entry = barriers.getEntry(barrier) orelse return c.EINVAL;
    current_thread.is_blocking = true;

    var internal_barrier = entry.value_ptr;
    internal_barrier.*.waiters.append(&current_thread) catch @panic("OOM");

    std.log.debug("[{}] reach barr w. {} of {} total waiters", .{ current_thread.det_id, internal_barrier.*.waiters.items.len, internal_barrier.*.count });
    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|bwait({*})|0\n", .{ current_thread.det_id, barrier }) catch @panic("Failed to log to file");
        }
    }

    if (internal_barrier.*.waiters.items.len >= internal_barrier.*.count) {
        while (internal_barrier.*.waiters.popOrNull()) |t| {
            t.is_blocking = false;
            if (SHOULD_LOG) {
                if (logfile_writer != null) {
                    std.fmt.format(logfile_writer.?, "{}|brel({*})|0\n", .{ t.det_id, barrier }) catch @panic("Failed to log to file");
                }
            }
        }
    }

    context_switch();

    return 0; // TODO one thread returns special value
}

fn record_lock_op(lock: ?*std.c.pthread_mutex_t, is_rel: bool) void {
    // lock_as_mem: acq = read, rel = write
    if (method == METHOD.LOCK_AS_MEM) {
        current_thread.next_event = Event{
            .op = EVENT_TYPE.MEM_OP,
            .instr_addr = null,
            .mem_addr = lock,
            .size = 32,
            .is_write = is_rel,
        };
    }
}

fn record_rwlock_op(lock: ?*std.c.pthread_rwlock_t, is_rel: bool) void {
    // lock_as_mem: acq = read, rel = write
    if (method == METHOD.LOCK_AS_MEM) {
        current_thread.next_event = Event{
            .op = EVENT_TYPE.MEM_OP,
            .instr_addr = null,
            .mem_addr = lock,
            .size = 32,
            .is_write = is_rel,
        };
    }
}

export fn pthread_mutex_trylock(lock: ?*std.c.pthread_mutex_t) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    record_lock_op(lock, false);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|r({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|acq({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }

    var entry = mutexes.getEntry(lock);
    if (entry != null) {
        var mutex = entry.?.value_ptr;
        if (mutex.*.owner == current_thread.tid) {
            return c.EBUSY;
        }
    }

    const ret_val = mutex_lock_internal(lock, false);

    if (ret_val != 0) {
        return c.EBUSY;
    }

    return 0;
}

export fn pthread_mutex_lock(lock: ?*std.c.pthread_mutex_t) c_int {
    init();

    record_lock_op(lock, false);

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    _ = mutex_lock_internal(lock, true);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|r({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|acq({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }

    return 0;
}

fn mutex_lock_internal(lock: ?*std.c.pthread_mutex_t, block: bool) c_int {
    // should only take one iteration
    while (true) {
        var entry = mutexes.getOrPutValue(lock, Mutex{
            .owner = current_thread.tid,
            .recursive_count = 0,
            .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC),
        }) catch @panic("OOM");
        if (entry.value_ptr.*.owner == current_thread.tid) {
            std.log.debug("[{}] acquired mutex {*}", .{ current_thread.det_id, lock });
            entry.value_ptr.*.recursive_count += 1;
            break;
        }
        if (!block) { // non-blocking
            return 1;
        }
        entry.value_ptr.*.waiters.append(&current_thread) catch @panic("OOM");
        std.log.debug("[{}] BLOCKING on lock {*}!", .{ current_thread.det_id, lock });
        current_thread.is_blocking = true;
        context_switch();
    }
    return 0;
}

export fn pthread_mutex_unlock(lock: ?*std.c.pthread_mutex_t) c_int {
    init();

    record_lock_op(lock, true);

    std.log.debug("[{}] releasing {*}...", .{ current_thread.det_id, lock });

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    const r = mutex_unlock_internal(lock);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|w({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|rel({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }

    return r;
}

fn mutex_unlock_internal(lock: ?*std.c.pthread_mutex_t) c_int {
    var entry = mutexes.getEntry(lock) orelse {
        return c.EINVAL;
    };
    var mutex = entry.value_ptr;

    if (mutex.*.owner != current_thread.tid) {
        return c.EPERM;
    }

    mutex.*.recursive_count -= 1;

    if (mutex.*.recursive_count > 0) {
        return 0;
    }

    if (mutex.*.waiters.items.len == 0) {
        const removed = mutexes.swapRemove(lock);
        _ = removed;
        return 0;
    }

    const idx = choose_next_thread_idx(&mutex.*.waiters, true);
    var to_wake = mutex.*.waiters.swapRemove(idx);
    to_wake.is_blocking = false;
    mutex.*.owner = to_wake.tid;
    return 0;
}

export fn pthread_cond_wait(pt_cond: ?*std.c.pthread_cond_t, lock: ?*std.c.pthread_mutex_t) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var r = mutex_unlock_internal(lock);
    if (r != 0) {
        return r;
    }

    var entry = conds.getOrPutValue(pt_cond, Cond{
        .cond = pt_cond,
        .mutex = lock,
        .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC),
    }) catch @panic("OOM");
    std.debug.assert(entry.value_ptr.*.mutex == lock);

    entry.value_ptr.*.waiters.append(&current_thread) catch @panic("OOM");
    std.log.debug("[{}] BLOCKING cond wait on {*}", .{ current_thread.det_id, pt_cond });
    current_thread.is_blocking = true;
    context_switch();

    _ = mutex_lock_internal(lock, true);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|wait_sleep({*})|0\n", .{ current_thread.det_id, pt_cond }) catch @panic("Failed to log to file");
        }
    }

    return 0;
}

export fn pthread_cond_timedwait(cond: ?*std.c.pthread_cond_t, lock: ?*std.c.pthread_mutex_t, time: ?*std.c.timespec) c_int {
    _ = time;
    _ = lock;
    init();
    std.log.debug("[{}] cond timedwait on {*}", .{ current_thread.det_id, cond });

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    return 110; // [ETIMEDOUT]
}

export fn pthread_cond_signal(pt_cond: ?*std.c.pthread_cond_t) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var entry = conds.getEntry(pt_cond) orelse return 0;
    var cond = entry.value_ptr;

    if (cond.*.waiters.items.len == 0) {
        return 0;
    }
    const i = PRNG.random().uintLessThan(usize, cond.*.waiters.items.len);
    var to_wake = cond.*.waiters.swapRemove(i);
    to_wake.is_blocking = false;
    std.log.debug("[{}] signaling {} on {*}", .{ current_thread.det_id, to_wake.det_id, pt_cond });

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|signal({*}, ?)|0\n", .{ current_thread.det_id, pt_cond }) catch @panic("Failed to log to file");
        }
    }

    return 0;
}

export fn pthread_cond_broadcast(pt_cond: ?*std.c.pthread_cond_t) c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var entry = conds.getEntry(pt_cond) orelse return 0;
    var cond = entry.value_ptr;
    for (cond.*.waiters.items) |to_wake| {
        to_wake.is_blocking = false;
        std.log.debug("[{}] broadcast signaling {} on {*}", .{ current_thread.det_id, to_wake.det_id, pt_cond });
    }
    const removed = conds.swapRemove(pt_cond);
    _ = removed;

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|sigAll({*})|0\n", .{ current_thread.det_id, pt_cond }) catch @panic("Failed to log to file");
        }
    }

    return 0;
}

export fn pthread_cancel(t: ?*std.c.pthread_t) c_int {
    std.log.err("UNIMPLEMENTED pthread_cancel", .{});
    return real_pthread_cancel(t);
}

export fn pthread_rwlock_rdlock(lock: ?*std.c.pthread_rwlock_t) c_int {
    init();

    record_rwlock_op(lock, false);

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    // should only take one iteration
    while (true) {
        var entry = rwlocks.getOrPutValue(lock, Rwlock{
            .owner = current_thread.tid,
            .is_exclusive = false,
            .recursive_count = 0,
            .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC),
            .waiter_is_rdlock = std.ArrayList(bool).init(SAFE_ALLOC),
        }) catch @panic("OOM");

        var rwlock = entry.value_ptr;
        std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);

        if (!rwlock.*.is_exclusive) {
            std.log.debug("[{}] acquired rdlock {*}", .{ current_thread.det_id, lock });
            rwlock.*.recursive_count += 1;
            rwlock.*.is_exclusive = false;
            break;
        }

        rwlock.*.waiters.append(&current_thread) catch @panic("OOM");
        rwlock.*.waiter_is_rdlock.append(true) catch @panic("OOM");

        std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);
        std.log.debug("[{}] BLOCKING on rdlock {*}!", .{ current_thread.det_id, lock });
        current_thread.is_blocking = true;
        context_switch();
    }

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|r({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|acq({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }

    return 0;
}

export fn pthread_rwlock_unlock(lock: ?*std.c.pthread_rwlock_t) c_int {
    init();

    record_rwlock_op(lock, true);

    std.log.debug("[{}] releasing {*}...", .{ current_thread.det_id, lock });

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    var entry = rwlocks.getEntry(lock) orelse {
        return c.EINVAL;
    };
    var rwlock = entry.value_ptr;

    std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);

    if (rwlock.*.is_exclusive and rwlock.*.owner != current_thread.tid) {
        return c.EPERM;
    }

    rwlock.*.recursive_count -= 1;

    if (rwlock.*.recursive_count > 0) {
        return 0;
    }

    if (rwlock.*.waiters.items.len == 0) {
        const removed = rwlocks.swapRemove(lock);
        _ = removed;
    } else {
        const idx = choose_next_thread_idx(&rwlock.*.waiters, true);
        var to_wake = rwlock.*.waiters.swapRemove(idx);
        var is_read = rwlock.*.waiter_is_rdlock.swapRemove(idx);

        to_wake.is_blocking = false;
        rwlock.*.owner = to_wake.tid;

        if (is_read) {
            // Wake all other waiting readers if waiter was a rdlock
            var loop_idx: u32 = 0;
            while (loop_idx < rwlock.*.waiters.items.len) {
                if (rwlock.*.waiter_is_rdlock.items[loop_idx]) {
                    to_wake = rwlock.*.waiters.swapRemove(idx);
                    _ = rwlock.*.waiter_is_rdlock.swapRemove(idx);
                    to_wake.is_blocking = false;
                    // DON'T increment; swap places new item at current idx
                } else {
                    loop_idx += 1;
                }
            }
        }
    }
    std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|w({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|rel({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }

    return 0;
}

export fn pthread_rwlock_wrlock(lock: ?*std.c.pthread_rwlock_t) c_int {
    init();

    record_rwlock_op(lock, false);

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    // should only take one iteration
    while (true) {
        var entry = rwlocks.getOrPutValue(lock, Rwlock{
            .owner = current_thread.tid,
            .is_exclusive = true,
            .recursive_count = 0,
            .waiters = std.ArrayList(*Thread).init(SAFE_ALLOC),
            .waiter_is_rdlock = std.ArrayList(bool).init(SAFE_ALLOC),
        }) catch @panic("OOM");

        var rwlock = entry.value_ptr;
        std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);

        if (rwlock.*.owner == current_thread.tid) {
            std.log.debug("[{}] acquired wrlock {*}", .{ current_thread.det_id, lock });
            rwlock.*.recursive_count += 1;
            rwlock.*.is_exclusive = true;
            break;
        }

        rwlock.*.waiters.append(&current_thread) catch @panic("OOM");
        rwlock.*.waiter_is_rdlock.append(false) catch @panic("OOM");

        std.debug.assert(rwlock.*.waiters.items.len == rwlock.*.waiter_is_rdlock.items.len);
        std.log.debug("[{}] BLOCKING on wrlock {*}!", .{ current_thread.det_id, lock });
        current_thread.is_blocking = true;
        context_switch();
    }

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (method == METHOD.LOCK_AS_MEM) {
                std.fmt.format(logfile_writer.?, "{}|r({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|acq({*})|0\n", .{ current_thread.det_id, lock }) catch @panic("Failed to log to file");
            }
        }
    }
    return 0;
}

var sy_switch_start: ?std.time.Instant = null;
var sy_switch_end: ?std.time.Instant = null;

export fn sched_yield() c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));

    current_thread.next_event = Event{
        .op = EVENT_TYPE.SCH_YIELD,
        .instr_addr = null,
        .mem_addr = null,
        .size = 0,
        .is_write = false,
    };

    // For guaranteed yield, use force_yield() instead
    if (TRACE_SY_SWITCH) {
        sy_switch_start = std.time.Instant.now() catch @panic("No time avail");
    }
    context_switch();
    if (TRACE_SY_SWITCH) {
        sy_switch_end = std.time.Instant.now() catch @panic("No time avail");
        const elapsed = sy_switch_end.?.since(sy_switch_start.?);
        if (elapsed > 1000) {
            std.debug.print("@@@sy_switch,{}\n", .{elapsed});
        }
    }

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|sched_yield|0\n", .{current_thread.det_id}) catch @panic("Failed to log to file");
        }
    }
    return 0;
}

export fn force_yield() c_int {
    init();

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));

    current_thread.next_event = Event{
        .op = EVENT_TYPE.SCH_YIELD,
        .instr_addr = null,
        .mem_addr = null,
        .size = 0,
        .is_write = false,
    };

    if (TRACE_SY_SWITCH) {
        sy_switch_start = std.time.Instant.now() catch @panic("No time avail");
    }

    if (threads.items.len == 1) {
        return 0;
    }

    // @TODO should add global counter that keeps track of whether or not
    // there are other available threads so we don't have to iterate here
    var num_unblocked: u32 = 0;
    for (threads.items) |t| {
        if (!t.is_blocking) {
            num_unblocked += 1;
        }
    }

    // if we are the only unblocked thread, setting the thread to blocking
    // after this check would cause a spurious deadlock panic in
    // choose_next_thread
    if (num_unblocked == 1) {
        return 0;
    }

    current_thread.is_blocking = true;
    var t = threads.items[choose_next_thread_idx(&threads, false)];
    current_thread.is_blocking = false;
    resume_next_thread(t, true);

    if (TRACE_SY_SWITCH) {
        sy_switch_end = std.time.Instant.now() catch @panic("No time avail");
        const elapsed = sy_switch_end.?.since(sy_switch_start.?);
        if (elapsed > 1000) {
            std.debug.print("@@@sy_switch,{}\n", .{elapsed});
        }
    }

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            std.fmt.format(logfile_writer.?, "{}|force_yield|0\n", .{current_thread.det_id}) catch @panic("Failed to log to file");
        }
    }
    return 0;
}

export fn sleep(seconds: c_uint) c_uint {
    _ = seconds;
    _ = sched_yield();
    return 0;
}

export fn usleep(usec: u32) c_int {
    _ = usec;
    _ = sched_yield();
    return 0;
}

export fn nanosleep(req: ?*std.c.timespec, rem: ?*std.c.timespec) c_int {
    _ = req;
    _ = rem;
    _ = sched_yield();
    return 0;
}

export fn schedule_memop(instr_addr: ?*const anyopaque, mem_addr: ?*const anyopaque, size: usize, is_write: bool) void {
    init();

    current_thread.next_event = Event{
        .op = EVENT_TYPE.MEM_OP,
        .instr_addr = instr_addr,
        .mem_addr = mem_addr,
        .size = size,
        .is_write = is_write,
    };

    dbg_ck(real_pthread_mutex_lock(&global_mutex));
    defer dbg_ck(real_pthread_mutex_unlock(&global_mutex));
    context_switch();

    if (SHOULD_LOG) {
        if (logfile_writer != null) {
            if (is_write) {
                std.fmt.format(logfile_writer.?, "{}|w({?})|{?x}\n", .{ current_thread.det_id, mem_addr, instr_addr }) catch @panic("Failed to log to file");
            } else {
                std.fmt.format(logfile_writer.?, "{}|r({?})|{?x)}\n", .{ current_thread.det_id, mem_addr, instr_addr }) catch @panic("Failed to log to file");
            }
        }
    }
}

export fn malloc_X(size_bytes: usize) [*c]u8 {
    init();
    // var bytes = real_malloc_X(size_bytes);
    // return bytes;
    var bytes = SAFE_ALLOC.alignedAlloc(u8, @alignOf(Metadata), size_bytes + @sizeOf(Metadata)) catch @panic("OOM");
    // std.log.debug("Malloc {*}", .{bytes});

    @memset(bytes, 0); // TODO calloc only
    var md = @as(*Metadata, @ptrCast(bytes.ptr));
    md.len = bytes.len;

    // std.log.debug("Mallocret", .{});
    return bytes.ptr + @sizeOf(Metadata);
}

export fn calloc_X(nitems: usize, size: usize) [*c]u8 {
    init();
    // std.log.debug("Calloc call", .{});

    var bytes = malloc_X(nitems * size);
    return bytes;
    // return real_calloc(nitems, size);
}

export fn realloc_X(ptr: [*c]u8, size_bytes: usize) [*c]u8 {
    init();
    std.log.debug("Realloc", .{});
    if (size_bytes == 0) {
        free_X(ptr);
        return null;
    }

    return malloc_X(size_bytes);
}

export fn free_X(ptr: [*c]u8) void {
    init();

    // real_free(ptr);
    if (ptr == null) {
        return;
    }

    var md = @as(*Metadata, @ptrCast(@alignCast(ptr - @sizeOf(Metadata))));
    const base: [*c]u8 align(8) = @alignCast(ptr - @sizeOf(Metadata));
    var slice = base[0..md.*.len];
    var slice_aligned: []u8 align(8) = @alignCast(slice);
    std.log.debug("Freeing {}", .{@alignOf(@TypeOf(slice_aligned))});
    std.log.debug("Freeing {*} (base : {*})", .{ ptr, base });
    SAFE_ALLOC.rawFree(slice_aligned, 3, @returnAddress());
    return;
}
