const std = @import("std");
const nougat = @import("nougat_engine.zig");

/// Process pages with separate engine per page (preparation for true parallelism)
pub fn processPagesParallel(
    allocator: std.mem.Allocator,
    page_files: []const PageInfo,
    page_filter: PageFilter,
    encoder_path: []const u8,
    decoder_path: []const u8,
    tokenizer_path: []const u8,
    max_tokens: usize,
    num_workers: usize,
    temp_dir: []const u8,
) !ParallelResults {
    _ = num_workers; // Reserved for future true parallel implementation

    // First pass: count pages to process
    var process_count: usize = 0;
    var skipped: u32 = 0;

    for (page_files) |page_info| {
        const should_process = switch (page_filter) {
            .all => true,
            .single => |n| page_info.num == n,
            .list => |list| blk: {
                for (list) |n| {
                    if (n == page_info.num) break :blk true;
                }
                break :blk false;
            },
            .range => |r| page_info.num >= r.start and page_info.num <= r.end,
        };

        if (should_process) {
            process_count += 1;
        } else {
            skipped += 1;
        }
    }

    if (process_count == 0) {
        // Clean up skipped files
        for (page_files) |page_info| {
            const page_path = try std.fs.path.join(allocator, &.{ temp_dir, page_info.name });
            defer allocator.free(page_path);
            std.fs.cwd().deleteFile(page_path) catch {};
        }
        return .{
            .results = try allocator.alloc(PageResult, 0),
            .processed = 0,
            .skipped = skipped,
        };
    }

    // Allocate results array
    const results = try allocator.alloc(PageResult, process_count);
    errdefer allocator.free(results);

    // Process pages with separate engine per page
    var result_idx: usize = 0;
    for (page_files) |page_info| {
        const should_process = switch (page_filter) {
            .all => true,
            .single => |n| page_info.num == n,
            .list => |list| blk: {
                for (list) |n| {
                    if (n == page_info.num) break :blk true;
                }
                break :blk false;
            },
            .range => |r| page_info.num >= r.start and page_info.num <= r.end,
        };

        if (!should_process) {
            const skip_path = try std.fs.path.join(allocator, &.{ temp_dir, page_info.name });
            defer allocator.free(skip_path);
            std.fs.cwd().deleteFile(skip_path) catch {};
            continue;
        }

        const page_path = try std.fs.path.join(allocator, &.{ temp_dir, page_info.name });
        defer allocator.free(page_path);

        // Create engine for this page
        var engine = nougat.NougatEngine.init(
            allocator,
            encoder_path,
            decoder_path,
            tokenizer_path,
            max_tokens,
        ) catch |err| {
            results[result_idx] = .{
                .page_num = page_info.num,
                .text = "",
                .success = false,
                .error_msg = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}),
            };
            result_idx += 1;
            continue;
        };
        defer engine.deinit();

        // Process the page
        const text = engine.processImage(page_path) catch |err| {
            results[result_idx] = .{
                .page_num = page_info.num,
                .text = "",
                .success = false,
                .error_msg = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}),
            };
            result_idx += 1;
            std.fs.cwd().deleteFile(page_path) catch {};
            continue;
        };

        results[result_idx] = .{
            .page_num = page_info.num,
            .text = text,
            .success = true,
            .error_msg = null,
        };
        result_idx += 1;

        // Delete processed file
        std.fs.cwd().deleteFile(page_path) catch {};
    }

    // Sort results by page number
    std.mem.sort(PageResult, results, {}, comparePageNum);

    return .{
        .results = results,
        .processed = @intCast(process_count),
        .skipped = skipped,
    };
}

fn comparePageNum(_: void, a: PageResult, b: PageResult) bool {
    return a.page_num < b.page_num;
}

pub const PageResult = struct {
    page_num: u32,
    text: []const u8,
    success: bool,
    error_msg: ?[]const u8,

    pub fn deinit(self: *PageResult, allocator: std.mem.Allocator) void {
        if (self.text.len > 0) allocator.free(self.text);
        if (self.error_msg) |msg| allocator.free(msg);
    }
};

pub const PageInfo = struct {
    num: u32,
    name: []const u8,
};

pub const PageFilter = union(enum) {
    all,
    single: u32,
    list: []const u32,
    range: struct { start: u32, end: u32 },
};

pub const ParallelResults = struct {
    results: []PageResult,
    processed: u32,
    skipped: u32,

    pub fn deinit(self: *ParallelResults, allocator: std.mem.Allocator) void {
        for (self.results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(self.results);
    }
};
