const std = @import("std");

// ============================================================
//  ANSI color / style codes
// ============================================================
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";

const FG_YELLOW = "\x1b[33m";
const FG_BRIGHT_RED = "\x1b[91m";
const FG_BRIGHT_GREEN = "\x1b[92m";
const FG_BRIGHT_YELLOW = "\x1b[93m";
const FG_BRIGHT_BLUE = "\x1b[94m";
const FG_BRIGHT_MAGENTA = "\x1b[95m";
const FG_BRIGHT_CYAN = "\x1b[96m";
const FG_BRIGHT_WHITE = "\x1b[97m";

// Match highlight: bold yellow on dark red
const BG_MATCH = "\x1b[1;33;41m";

// ============================================================
//  Config
// ============================================================
const Config = struct {
    pattern: []const u8,
    paths: []const []const u8,
    ignore_case: bool = false,
    show_line_numbers: bool = true,
    recursive: bool = true,
    color: bool = true,
    context_lines: usize = 0,
    max_depth: usize = 64,
    show_count: bool = false,
    files_only: bool = false,
    invert_match: bool = false,
    whole_word: bool = false,
    binary_skip: bool = true,
};

// ============================================================
//  Stats
// ============================================================
const Stats = struct {
    files_searched: usize = 0,
    files_matched: usize = 0,
    total_matches: usize = 0,
    bytes_searched: u64 = 0,
};

// ============================================================
//  Entry point
// ============================================================
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();

    var out_buf: [65536]u8 = undefined;
    var err_buf: [4096]u8 = undefined;

    var out_fw = stdout_file.writer(&out_buf);
    var err_fw = stderr_file.writer(&err_buf);
    const stdout = &out_fw.interface;
    const stderr = &err_fw.interface;

    defer out_fw.interface.flush() catch {};
    defer err_fw.interface.flush() catch {};

    if (args.len < 2) {
        try printBanner(stdout);
        try printHelp(stdout);
        return;
    }

    // Check for help flag first
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printBanner(stdout);
            try printHelp(stdout);
            return;
        }
    }

    var config = parseArgs(allocator, args) catch |err| {
        const msg = switch (err) {
            error.NoPatternSpecified => "No pattern specified.",
            error.UnknownFlag => "Unknown flag. Run zigrep --help for usage.",
            else => return err,
        };
        try stderr.print("{s}✗  {s}{s}\n", .{ FG_BRIGHT_RED, msg, RESET });
        try err_fw.interface.flush();
        std.process.exit(1);
    };
    defer allocator.free(config.paths);

    if (config.paths.len == 0) {
        // Search current directory
        const default_paths = try allocator.alloc([]const u8, 1);
        default_paths[0] = ".";
        allocator.free(config.paths);
        config.paths = default_paths;
    }

    // Detect if stdout is a terminal
    const is_tty = std.posix.isatty(stdout_file.handle);
    if (!is_tty) config.color = false;

    var stats = Stats{};
    var timer = try std.time.Timer.start();

    if (config.color) {
        try printSearchHeader(stdout, config.pattern, config.paths);
    }

    for (config.paths) |path| {
        searchPath(allocator, stdout, stderr, path, &config, &stats, 0) catch |err| {
            if (config.color) {
                try stderr.print("{s}⚠  Error searching '{s}': {}{s}\n", .{ FG_YELLOW, path, err, RESET });
            } else {
                try stderr.print("Error searching '{s}': {}\n", .{ path, err });
            }
        };
    }

    try out_fw.interface.flush();

    const elapsed_ns = timer.read();
    if (config.color) {
        try printSummary(stdout, &stats, elapsed_ns);
    } else {
        try stdout.print("\n{d} match(es) in {d} file(s)\n", .{ stats.total_matches, stats.files_matched });
    }
}

// ============================================================
//  Argument parser
// ============================================================
fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    var config = Config{
        .pattern = "",
        .paths = &[_][]const u8{},
    };

    var path_list = std.ArrayListUnmanaged([]const u8){};
    defer path_list.deinit(allocator);
    var pattern_set = false;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len == 0) continue;

        if (arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
                config.ignore_case = true;
            } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursive")) {
                config.recursive = true;
            } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--line-number")) {
                config.show_line_numbers = true;
            } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--count")) {
                config.show_count = true;
            } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--files-with-matches")) {
                config.files_only = true;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--invert-match")) {
                config.invert_match = true;
            } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--word-regexp")) {
                config.whole_word = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                config.color = false;
            } else if (std.mem.startsWith(u8, arg, "-C") or std.mem.startsWith(u8, arg, "--context=")) {
                const val_str = if (std.mem.startsWith(u8, arg, "-C"))
                    arg[2..]
                else
                    arg[10..];
                if (val_str.len > 0) {
                    config.context_lines = std.fmt.parseInt(usize, val_str, 10) catch 2;
                } else {
                    config.context_lines = 2;
                }
            } else if (std.mem.startsWith(u8, arg, "--max-depth=")) {
                config.max_depth = std.fmt.parseInt(usize, arg[12..], 10) catch 64;
            } else {
                return error.UnknownFlag;
            }
        } else if (!pattern_set) {
            config.pattern = arg;
            pattern_set = true;
        } else {
            try path_list.append(allocator, arg);
        }
    }

    if (!pattern_set) {
        return error.NoPatternSpecified;
    }

    config.paths = try path_list.toOwnedSlice(allocator);
    return config;
}

// ============================================================
//  Recursive file walk + search
// ============================================================
fn searchPath(
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
    path: []const u8,
    config: *const Config,
    stats: *Stats,
    depth: usize,
) !void {
    if (depth > config.max_depth) return;

    const stat = std.fs.cwd().statFile(path) catch |err| {
        if (err == error.FileNotFound) {
            if (config.color) {
                try stderr.print("{s}✗  Not found: {s}{s}\n", .{ FG_YELLOW, path, RESET });
            } else {
                try stderr.print("error: not found: {s}\n", .{path});
            }
        }
        return;
    };

    switch (stat.kind) {
        .file => try searchFile(allocator, stdout, stderr, path, config, stats),
        .directory => {
            if (!config.recursive) return;
            var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
            defer dir.close();

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.name[0] == '.') continue; // skip hidden
                const child_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
                defer allocator.free(child_path);
                try searchPath(allocator, stdout, stderr, child_path, config, stats, depth + 1);
            }
        },
        else => {},
    }
}

fn isBinaryContent(data: []const u8) bool {
    const sample_len = @min(data.len, 8192);
    var null_count: usize = 0;
    for (data[0..sample_len]) |byte| {
        if (byte == 0) null_count += 1;
    }
    return null_count > sample_len / 10;
}

fn searchFile(
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
    path: []const u8,
    config: *const Config,
    stats: *Stats,
) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (config.color) {
            try stderr.print("{s}⚠  Cannot open '{s}': {s}{s}\n", .{ FG_YELLOW, path, @errorName(err), RESET });
        } else {
            try stderr.print("warning: cannot open '{s}': {s}\n", .{ path, @errorName(err) });
        }
        return;
    };
    defer file.close();

    const max_size = 128 * 1024 * 1024;
    const content = file.readToEndAlloc(allocator, max_size) catch |err| {
        if (err == error.FileTooBig) {
            if (config.color) {
                try stderr.print("{s}⚠  Skipping '{s}': file exceeds 128 MiB{s}\n", .{ FG_YELLOW, path, RESET });
            } else {
                try stderr.print("warning: skipping '{s}': file exceeds 128 MiB\n", .{path});
            }
        }
        return;
    };
    defer allocator.free(content);

    stats.files_searched += 1;
    stats.bytes_searched += content.len;

    // Skip binary
    if (config.binary_skip and isBinaryContent(content)) return;

    // Split into lines
    var lines = std.ArrayListUnmanaged([]const u8){};
    defer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        try lines.append(allocator, line);
    }

    var match_indices = std.ArrayListUnmanaged(usize){};
    defer match_indices.deinit(allocator);

    var match_count: usize = 0;

    for (lines.items, 0..) |line, idx| {
        const matched = lineMatches(line, config);
        if (matched != config.invert_match) {
            try match_indices.append(allocator, idx);
            match_count += 1;
        }
    }

    if (match_count == 0) return;

    stats.files_matched += 1;
    stats.total_matches += match_count;

    if (config.files_only) {
        if (config.color) {
            try stdout.print("{s}◈ {s}{s}{s}\n", .{ FG_BRIGHT_CYAN, BOLD, path, RESET });
        } else {
            try stdout.print("{s}\n", .{path});
        }
        return;
    }

    if (config.show_count) {
        if (config.color) {
            try stdout.print("{s}◈ {s}{s}{s}  {s}[{d} match(es)]{s}\n", .{ FG_BRIGHT_CYAN, BOLD, path, RESET, FG_BRIGHT_YELLOW, match_count, RESET });
        } else {
            try stdout.print("{s}:{d}\n", .{ path, match_count });
        }
        return;
    }

    // Print file header
    if (config.color) {
        try printFileHeader(stdout, path, match_count);
    } else {
        try stdout.print("\n--- {s} ({d} match(es)) ---\n", .{ path, match_count });
    }

    // Print matches with context
    var printed = std.AutoHashMapUnmanaged(usize, void){};
    defer printed.deinit(allocator);

    var last_printed: i64 = -2;

    for (match_indices.items) |match_idx| {
        const ctx = config.context_lines;
        const start = if (match_idx >= ctx) match_idx - ctx else 0;
        const end = @min(lines.items.len, match_idx + ctx + 1);

        // Separator if there's a gap
        if (last_printed >= 0 and @as(i64, @intCast(start)) > last_printed + 1) {
            if (config.color) {
                try stdout.print("{s}  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌{s}\n", .{ DIM, RESET });
            } else {
                try stdout.print("  --\n", .{});
            }
        }

        var j = start;
        while (j < end) : (j += 1) {
            if (printed.contains(j)) continue;
            try printed.put(allocator, j, {});
            last_printed = @intCast(j);

            const is_match_line = lineMatches(lines.items[j], config) != config.invert_match;
            try printLine(stdout, lines.items[j], j + 1, is_match_line, config);
        }
    }

    if (config.color) {
        try stdout.print("\n", .{});
    }
}

fn lineMatches(line: []const u8, config: *const Config) bool {
    if (config.ignore_case) {
        // Case-insensitive: compare lowercased
        // We do a simple scan since we don't have regex
        return containsIgnoreCase(line, config.pattern, config.whole_word);
    }
    if (config.whole_word) {
        return containsWholeWord(line, config.pattern);
    }
    return std.mem.indexOf(u8, line, config.pattern) != null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8, whole_word: bool) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = haystack[i + j];
            if (std.ascii.toLower(hc) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) {
            if (whole_word) {
                const before_ok = i == 0 or !isWordChar(haystack[i - 1]);
                const after_ok = (i + needle.len) >= haystack.len or !isWordChar(haystack[i + needle.len]);
                if (before_ok and after_ok) return true;
            } else {
                return true;
            }
        }
    }
    return false;
}

fn containsWholeWord(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var start: usize = 0;
    while (std.mem.indexOf(u8, haystack[start..], needle)) |idx| {
        const abs = start + idx;
        const before_ok = abs == 0 or !isWordChar(haystack[abs - 1]);
        const after_ok = (abs + needle.len) >= haystack.len or !isWordChar(haystack[abs + needle.len]);
        if (before_ok and after_ok) return true;
        start = abs + 1;
        if (start >= haystack.len) break;
    }
    return false;
}

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

// ============================================================
//  Visual output helpers
// ============================================================
fn printBanner(writer: anytype) !void {
    try writer.print("\n", .{});
    try writer.print("{s}╔══════════════════════════════════════════════╗{s}\n", .{ FG_BRIGHT_CYAN, RESET });
    try writer.print("{s}║{s} {s}  ⚡  Z I G R E P  ⚡{s}                        {s}║{s}\n", .{ FG_BRIGHT_CYAN, RESET, BOLD ++ FG_BRIGHT_YELLOW, RESET, FG_BRIGHT_CYAN, RESET });
    try writer.print("{s}║{s} {s}  blazing-fast file search{s}                 {s}║{s}\n", .{ FG_BRIGHT_CYAN, RESET, DIM ++ FG_BRIGHT_WHITE, RESET, FG_BRIGHT_CYAN, RESET });
    try writer.print("{s}╚══════════════════════════════════════════════╝{s}\n", .{ FG_BRIGHT_CYAN, RESET });
    try writer.print("\n", .{});
}

fn printHelp(writer: anytype) !void {
    try writer.print("{s}USAGE{s}\n", .{ BOLD ++ FG_BRIGHT_WHITE, RESET });
    try writer.print("  {s}zigrep{s} {s}[OPTIONS]{s} {s}<PATTERN>{s} {s}[PATH...]{s}\n\n", .{
        FG_BRIGHT_CYAN,    RESET,
        FG_BRIGHT_MAGENTA, RESET,
        FG_BRIGHT_YELLOW,  RESET,
        FG_BRIGHT_GREEN,   RESET,
    });

    try writer.print("{s}OPTIONS{s}\n", .{ BOLD ++ FG_BRIGHT_WHITE, RESET });
    const opts = [_][3][]const u8{
        .{ "-i, --ignore-case", "Case-insensitive matching", "" },
        .{ "-r, --recursive", "Recurse into directories (default: on)", "" },
        .{ "-n, --line-number", "Show line numbers (default: on)", "" },
        .{ "-c, --count", "Print match count per file", "" },
        .{ "-l, --files-with-matches", "Print only filenames", "" },
        .{ "-v, --invert-match", "Invert match (print non-matching lines)", "" },
        .{ "-w, --word-regexp", "Match whole words only", "" },
        .{ "-C<N>", "Show N lines of context around matches", "" },
        .{ "--no-color", "Disable color output", "" },
        .{ "--max-depth=N", "Max directory recursion depth", "" },
        .{ "-h, --help", "Show this help", "" },
    };

    for (opts) |opt| {
        try writer.print("  {s}{s:<30}{s}  {s}{s}{s}\n", .{
            FG_BRIGHT_GREEN, opt[0], RESET,
            DIM,             opt[1], RESET,
        });
    }

    try writer.print("\n{s}EXAMPLES{s}\n", .{ BOLD ++ FG_BRIGHT_WHITE, RESET });
    try writer.print("  {s}zigrep{s} {s}fn{s} {s}src/{s}\n", .{ FG_BRIGHT_CYAN, RESET, FG_BRIGHT_YELLOW, RESET, FG_BRIGHT_GREEN, RESET });
    try writer.print("  {s}zigrep{s} {s}-i{s} {s}todo{s} {s}.{s}\n", .{ FG_BRIGHT_CYAN, RESET, FG_BRIGHT_MAGENTA, RESET, FG_BRIGHT_YELLOW, RESET, FG_BRIGHT_GREEN, RESET });
    try writer.print("  {s}zigrep{s} {s}-C2{s} {s}main{s} {s}src/main.zig{s}\n", .{ FG_BRIGHT_CYAN, RESET, FG_BRIGHT_MAGENTA, RESET, FG_BRIGHT_YELLOW, RESET, FG_BRIGHT_GREEN, RESET });
    try writer.print("  {s}zigrep{s} {s}-l{s} {s}error{s}\n", .{ FG_BRIGHT_CYAN, RESET, FG_BRIGHT_MAGENTA, RESET, FG_BRIGHT_YELLOW, RESET });
    try writer.print("\n", .{});
}

fn printSearchHeader(writer: anytype, pattern: []const u8, paths: []const []const u8) !void {
    try writer.print("\n", .{});
    try writer.print("{s}╭─{s} {s}Searching{s} {s}❯ {s}{s}{s}\n", .{
        FG_BRIGHT_CYAN,   RESET,
        DIM,              RESET,
        FG_BRIGHT_YELLOW, BOLD,
        pattern,          RESET,
    });
    try writer.print("{s}│  {s}{s}Path:{s}", .{ FG_BRIGHT_CYAN, RESET, DIM, RESET });
    for (paths) |p| {
        try writer.print(" {s}{s}{s}", .{ FG_BRIGHT_GREEN, p, RESET });
    }
    try writer.print("\n{s}╰──────────────────────────────────────────{s}\n\n", .{ FG_BRIGHT_CYAN, RESET });
}

fn printFileHeader(writer: anytype, path: []const u8, count: usize) !void {
    try writer.print("{s}┌─{s} {s}{s}{s}", .{ FG_BRIGHT_BLUE, RESET, BOLD ++ FG_BRIGHT_CYAN, path, RESET });
    try writer.print("  {s}[{d} ✦]{s}\n", .{ FG_BRIGHT_YELLOW, count, RESET });
    try writer.print("{s}│{s}\n", .{ FG_BRIGHT_BLUE, RESET });
}

fn printLine(
    writer: anytype,
    line: []const u8,
    line_num: usize,
    is_match: bool,
    config: *const Config,
) !void {
    if (!config.color) {
        if (config.show_line_numbers) {
            try writer.print("{d}:{s}\n", .{ line_num, line });
        } else {
            try writer.print("{s}\n", .{line});
        }
        return;
    }

    if (is_match) {
        // Match line
        if (config.show_line_numbers) {
            try writer.print("{s}│{s} {s}{d:>5}{s} {s}│{s} ", .{
                FG_BRIGHT_BLUE,        RESET,
                FG_BRIGHT_RED ++ BOLD, line_num,
                RESET,                 FG_BRIGHT_RED,
                RESET,
            });
        } else {
            try writer.print("{s}│{s} {s}│{s} ", .{ FG_BRIGHT_BLUE, RESET, FG_BRIGHT_RED, RESET });
        }
        try printLineWithHighlight(writer, line, config);
        try writer.print("\n", .{});
    } else {
        // Context line
        if (config.show_line_numbers) {
            try writer.print("{s}│{s} {s}{d:>5}{s} {s}│{s} {s}{s}{s}\n", .{
                FG_BRIGHT_BLUE, RESET,
                DIM,            line_num,
                RESET,          DIM,
                RESET,          DIM,
                line,           RESET,
            });
        } else {
            try writer.print("{s}│{s} {s}│{s} {s}{s}{s}\n", .{
                FG_BRIGHT_BLUE, RESET,
                DIM,            RESET,
                DIM,            line,
                RESET,
            });
        }
    }
}

fn printLineWithHighlight(writer: anytype, line: []const u8, config: *const Config) !void {
    var remaining = line;

    while (remaining.len > 0) {
        const pos_opt = findPatternIndex(remaining, config);
        if (pos_opt == null) {
            try writer.print("{s}", .{remaining});
            break;
        }

        const pos = pos_opt.?;
        const pattern_len = config.pattern.len;

        if (pos > 0) {
            try writer.print("{s}", .{remaining[0..pos]});
        }

        try writer.print("{s}{s}{s}", .{
            BG_MATCH ++ FG_BRIGHT_YELLOW ++ BOLD,
            remaining[pos .. pos + pattern_len],
            RESET,
        });

        remaining = remaining[pos + pattern_len ..];
    }
}

fn findPatternIndex(line: []const u8, config: *const Config) ?usize {
    if (config.ignore_case) {
        if (config.pattern.len == 0) return 0;
        if (line.len < config.pattern.len) return null;
        var i: usize = 0;
        while (i <= line.len - config.pattern.len) : (i += 1) {
            var match = true;
            for (config.pattern, 0..) |nc, j| {
                if (std.ascii.toLower(line[i + j]) != std.ascii.toLower(nc)) {
                    match = false;
                    break;
                }
            }
            if (match) {
                if (config.whole_word) {
                    const before_ok = i == 0 or !isWordChar(line[i - 1]);
                    const after_ok = (i + config.pattern.len) >= line.len or !isWordChar(line[i + config.pattern.len]);
                    if (before_ok and after_ok) return i;
                } else {
                    return i;
                }
            }
        }
        return null;
    }
    if (config.whole_word) {
        var start: usize = 0;
        while (std.mem.indexOf(u8, line[start..], config.pattern)) |idx| {
            const abs = start + idx;
            const before_ok = abs == 0 or !isWordChar(line[abs - 1]);
            const after_ok = (abs + config.pattern.len) >= line.len or !isWordChar(line[abs + config.pattern.len]);
            if (before_ok and after_ok) return abs;
            start = abs + 1;
            if (start >= line.len) break;
        }
        return null;
    }
    return std.mem.indexOf(u8, line, config.pattern);
}

fn printSummary(writer: anytype, stats: *const Stats, elapsed_ns: u64) !void {
    const ms = elapsed_ns / 1_000_000;
    const us = (elapsed_ns % 1_000_000) / 1_000;
    const kb = stats.bytes_searched / 1024;

    try writer.print("{s}╭─────────────────────────────────────────────╮{s}\n", .{ FG_BRIGHT_BLUE, RESET });
    try writer.print("{s}│{s}  {s}⚡ Search complete{s}                           {s}│{s}\n", .{
        FG_BRIGHT_BLUE, RESET, BOLD ++ FG_BRIGHT_WHITE, RESET, FG_BRIGHT_BLUE, RESET,
    });
    try writer.print("{s}│{s}  {s}✦ Matches   :{s} {s}{d}{s}                              {s}│{s}\n", .{
        FG_BRIGHT_BLUE,           RESET,
        DIM,                      RESET,
        FG_BRIGHT_YELLOW ++ BOLD, stats.total_matches,
        RESET,                    FG_BRIGHT_BLUE,
        RESET,
    });
    try writer.print("{s}│{s}  {s}◈ Files hit :{s} {s}{d}{s} / {d}                         {s}│{s}\n", .{
        FG_BRIGHT_BLUE,         RESET,
        DIM,                    RESET,
        FG_BRIGHT_CYAN ++ BOLD, stats.files_matched,
        RESET,                  stats.files_searched,
        FG_BRIGHT_BLUE,         RESET,
    });
    try writer.print("{s}│{s}  {s}⏱ Time      :{s} {s}{d}ms {d}µs{s}                     {s}│{s}\n", .{
        FG_BRIGHT_BLUE,          RESET,
        DIM,                     RESET,
        FG_BRIGHT_GREEN ++ BOLD, ms,
        us,                      RESET,
        FG_BRIGHT_BLUE,          RESET,
    });
    try writer.print("{s}│{s}  {s}◎ Data      :{s} {s}{d} KB{s}                          {s}│{s}\n", .{
        FG_BRIGHT_BLUE,            RESET,
        DIM,                       RESET,
        FG_BRIGHT_MAGENTA ++ BOLD, kb,
        RESET,                     FG_BRIGHT_BLUE,
        RESET,
    });
    try writer.print("{s}╰─────────────────────────────────────────────╯{s}\n", .{ FG_BRIGHT_BLUE, RESET });
}

// ============================================================
//  Tests
// ============================================================
test "lineMatches basic" {
    const config = Config{
        .pattern = "hello",
        .paths = &[_][]const u8{},
        .ignore_case = false,
        .whole_word = false,
    };
    try std.testing.expect(lineMatches("say hello world", &config));
    try std.testing.expect(!lineMatches("goodbye", &config));
}

test "lineMatches ignore case" {
    const config = Config{
        .pattern = "HELLO",
        .paths = &[_][]const u8{},
        .ignore_case = true,
        .whole_word = false,
    };
    try std.testing.expect(lineMatches("say hello world", &config));
}

test "lineMatches whole word" {
    const config = Config{
        .pattern = "fn",
        .paths = &[_][]const u8{},
        .ignore_case = false,
        .whole_word = true,
    };
    try std.testing.expect(lineMatches("pub fn main()", &config));
    try std.testing.expect(!lineMatches("function", &config));
}

test "isBinaryContent" {
    const text = "Hello, world!\nThis is plain text.\n";
    try std.testing.expect(!isBinaryContent(text));

    var bin: [100]u8 = undefined;
    bin[0] = 0;
    bin[1] = 0;
    bin[2] = 0;
    bin[3] = 0;
    bin[4] = 0;
    bin[5] = 0;
    bin[6] = 0;
    bin[7] = 0;
    bin[8] = 0;
    bin[9] = 0;
    bin[10] = 0;
    @memset(bin[11..], 'a');
    try std.testing.expect(isBinaryContent(&bin));
}
