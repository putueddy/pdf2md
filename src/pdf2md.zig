const std = @import("std");
const nougat = @import("ml/nougat_engine.zig");
const thread_pool = @import("ml/thread_pool.zig");

const PageFilter = thread_pool.PageFilter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(
            \\nPDF to Markdown Converter (Pure Zig + ONNX Runtime)
            \\nUsage: {s} <pdf-file> [output.md] [options]
            \\n
            \\nOptions:
            \\n  --max-tokens N      Maximum tokens per page (default: 512)
            \\n  --dpi N            DPI for PDF rendering (default: 200)
            \\n  --page N           Process only page N
            \\n  --pages N,M,...    Process specific pages (comma-separated)
            \\n  --pages N-M        Process page range N to M (inclusive)
            \\n  --append           Append to output file instead of overwriting
            \\n  --models DIR       Use models from DIR (default: models/nougat-onnx)
            \\n  --jobs N, -j N     Number of parallel workers (default: 1, use 0 for auto)
            \\n
            \\nExamples:
            \\n  {s} doc.pdf output.md                           # Process all pages (sequential)
            \\n  {s} doc.pdf output.md -j 4                      # Process with 4 parallel workers
            \\n  {s} doc.pdf output.md --jobs 0                  # Auto-detect CPU cores
            \\n  {s} doc.pdf output.md --page 5                  # Process only page 5
            \\n  {s} doc.pdf output.md --pages 1,3,5             # Process pages 1, 3, and 5
            \\n  {s} doc.pdf output.md --pages 1-5               # Process pages 1-5
            \\n  {s} doc.pdf output.md --append --page 6         # Append page 6 to existing file
            \\n  {s} doc.pdf output.md --models models/nougat-onnx-int8  # Use INT8 quantized models
            \\n
        , .{ args[0], args[0], args[0], args[0], args[0], args[0], args[0], args[0], args[0] });
        return error.MissingArguments;
    }

    const pdf_path = args[1];
    const output_path = if (args.len > 2 and !std.mem.startsWith(u8, args[2], "--")) args[2] else "output.md";

    // Parse optional args
    var max_tokens: usize = 512;
    var dpi: u32 = 200;
    var page_filter = PageFilter{ .all = {} };
    var append_mode = false;
    var model_dir: []const u8 = "models/nougat-onnx";
    var num_jobs: usize = 1; // Default to sequential processing
    var i: usize = 2;

    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--max-tokens") and i + 1 < args.len) {
            max_tokens = std.fmt.parseUnsigned(usize, args[i + 1], 10) catch 512;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--dpi") and i + 1 < args.len) {
            dpi = std.fmt.parseUnsigned(u32, args[i + 1], 10) catch 200;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--page") and i + 1 < args.len) {
            const page_num = std.fmt.parseUnsigned(u32, args[i + 1], 10) catch 1;
            page_filter = PageFilter{ .single = page_num };
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--pages") and i + 1 < args.len) {
            const pages_str = args[i + 1];

            // Check if it's a range (contains '-')
            if (std.mem.indexOfScalar(u8, pages_str, '-')) |dash_pos| {
                const start = std.fmt.parseUnsigned(u32, pages_str[0..dash_pos], 10) catch 1;
                const end = std.fmt.parseUnsigned(u32, pages_str[dash_pos + 1 ..], 10) catch 1;
                page_filter = PageFilter{ .range = .{ .start = start, .end = end } };
            } else if (std.mem.indexOfScalar(u8, pages_str, ',')) |_| {
                // It's a list - manually manage array
                // Count commas to estimate size
                var count: usize = 1;
                for (pages_str) |c| {
                    if (c == ',') count += 1;
                }

                var pages_list = try allocator.alloc(u32, count);
                defer allocator.free(pages_list);
                var list_len: usize = 0;

                var iter = std.mem.splitScalar(u8, pages_str, ',');
                while (iter.next()) |page_str| {
                    const trimmed = std.mem.trim(u8, page_str, " ");
                    if (trimmed.len == 0) continue;
                    const page_num = std.fmt.parseUnsigned(u32, trimmed, 10) catch continue;
                    if (list_len < count) {
                        pages_list[list_len] = page_num;
                        list_len += 1;
                    }
                }

                if (list_len > 0) {
                    // Allocate exact size and copy
                    const final_list = try allocator.alloc(u32, list_len);
                    @memcpy(final_list, pages_list[0..list_len]);
                    page_filter = PageFilter{ .list = final_list };
                }
            } else {
                // Single page
                const page_num = std.fmt.parseUnsigned(u32, pages_str, 10) catch 1;
                page_filter = PageFilter{ .single = page_num };
            }
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--append")) {
            append_mode = true;
        } else if (std.mem.eql(u8, args[i], "--models") and i + 1 < args.len) {
            model_dir = args[i + 1];
            i += 1;
        } else if ((std.mem.eql(u8, args[i], "--jobs") or std.mem.eql(u8, args[i], "-j")) and i + 1 < args.len) {
            num_jobs = std.fmt.parseUnsigned(usize, args[i + 1], 10) catch 1;
            // Auto-detect CPU cores if 0
            if (num_jobs == 0) {
                num_jobs = std.Thread.getCpuCount() catch 4;
            }
            i += 1;
        }
    }

    const encoder_path = try std.fs.path.join(allocator, &.{ model_dir, "encoder_model.onnx" });
    defer allocator.free(encoder_path);
    const decoder_path = try std.fs.path.join(allocator, &.{ model_dir, "decoder_model.onnx" });
    defer allocator.free(decoder_path);
    const tokenizer_path = try std.fs.path.join(allocator, &.{ model_dir, "tokenizer.json" });
    defer allocator.free(tokenizer_path);
    const temp_dir = ".tmp/pdf2md";

    std.debug.print("PDF to Markdown Converter\n", .{});
    std.debug.print("=========================\n\n", .{});

    // Validate inputs
    _ = std.fs.cwd().openFile(pdf_path, .{}) catch {
        std.debug.print("Error: Cannot open PDF file: {s}\n", .{pdf_path});
        return error.FileNotFound;
    };

    _ = std.fs.cwd().openFile(encoder_path, .{}) catch {
        std.debug.print("Error: Encoder model not found: {s}\n", .{encoder_path});
        std.debug.print("Run: ./scripts/export-nougat.sh\n", .{});
        return error.FileNotFound;
    };

    // Initialize engine
    std.debug.print("Loading models...\n", .{});
    var timer = try std.time.Timer.start();

    var engine = nougat.NougatEngine.init(allocator, encoder_path, decoder_path, tokenizer_path, max_tokens) catch |err| {
        std.debug.print("Error: Failed to initialize engine: {s}\n", .{@errorName(err)});
        return err;
    };
    defer {
        engine.deinit();
        // Clean up list allocation if needed
        switch (page_filter) {
            .list => |list| allocator.free(list),
            else => {},
        }
    }

    const init_time = timer.read() / std.time.ns_per_ms;
    std.debug.print("  Models loaded in {d}ms\n", .{init_time});

    // Print GPU status
    const onnx = @import("ml/onnx_runtime_c_wrapper.zig");
    const gpu_name = onnx.getGpuProviderName();
    const using_gpu = onnx.isGpuAvailable();
    if (using_gpu) {
        std.debug.print("  GPU Acceleration: {s} (10x faster inference)\n", .{gpu_name});
    } else {
        std.debug.print("  GPU Acceleration: Not available (using CPU)\n", .{});
    }
    std.debug.print("\n", .{});

    // Convert PDF
    try std.fs.cwd().makePath(temp_dir);

    std.debug.print("Converting PDF to images (DPI: {d})...\n", .{dpi});
    timer.reset();

    const prefix = try std.fs.path.join(allocator, &.{ temp_dir, "page" });
    defer allocator.free(prefix);

    const dpi_str = try std.fmt.allocPrint(allocator, "{d}", .{dpi});
    defer allocator.free(dpi_str);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pdftoppm", "-png", "-r", dpi_str, pdf_path, prefix },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Error: PDF conversion failed\n", .{});
        return error.PdfConversionError;
    }

    // Collect and sort page files
    var dir = try std.fs.cwd().openDir(temp_dir, .{ .iterate = true });
    defer dir.close();

    // First pass: count pages
    var page_count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".png")) page_count += 1;
    }

    // Allocate array for page info
    const PageInfo = struct { num: u32, name: []const u8 };
    var page_files = try allocator.alloc(PageInfo, page_count);
    defer {
        for (page_files) |item| {
            allocator.free(item.name);
        }
        allocator.free(page_files);
    }

    // Second pass: fill array
    var idx: usize = 0;
    iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".png")) continue;

        // Extract page number from filename (e.g., "page-01.png" → 1)
        const page_num = extractPageNumber(entry.name) catch continue;

        page_files[idx] = .{
            .num = page_num,
            .name = try allocator.dupe(u8, entry.name),
        };
        idx += 1;
    }

    // Sort by page number using simple swap sort
    var si: usize = 0;
    while (si < idx) : (si += 1) {
        var sj: usize = si + 1;
        while (sj < idx) : (sj += 1) {
            if (page_files[sj].num < page_files[si].num) {
                const tmp = page_files[si];
                page_files[si] = page_files[sj];
                page_files[sj] = tmp;
            }
        }
    }

    const convert_time = timer.read() / std.time.ns_per_ms;
    std.debug.print("  {d} pages in {d}ms\n\n", .{ idx, convert_time });

    // Process pages
    std.debug.print("Processing pages...\n", .{});

    // Open output file (create new or append)
    const out_file = blk: {
        if (append_mode) {
            // Try to open existing file for appending
            break :blk std.fs.cwd().openFile(output_path, .{ .mode = .write_only }) catch
                try std.fs.cwd().createFile(output_path, .{});
        } else {
            break :blk try std.fs.cwd().createFile(output_path, .{});
        }
    };
    defer out_file.close();

    // If appending, seek to end
    if (append_mode) {
        try out_file.seekFromEnd(0);
        // Add separator if file not empty
        const stat = try out_file.stat();
        if (stat.size > 0) {
            try out_file.writeAll("\n\n---\n\n");
        }
    } else {
        // Write header for new file
        try out_file.writeAll("# OCR Output\n\n");
        try out_file.writeAll("Generated by pdf2md (Pure Zig + ONNX Runtime)\n\n");
        try out_file.writeAll("---\n\n");
    }

    var total_chars: usize = 0;
    var processed: u32 = 0;
    timer.reset();

    // Use parallel processing if num_jobs > 1
    if (num_jobs > 1) {
        std.debug.print("Processing pages with {d} parallel workers...\n", .{num_jobs});

        // Create page info array for thread pool
        const PoolPageInfo = struct {
            num: u32,
            name: []const u8,
        };
        var pool_pages = try allocator.alloc(PoolPageInfo, idx);
        defer allocator.free(pool_pages);

        for (page_files[0..idx], 0..) |page_info, page_idx| {
            pool_pages[page_idx] = .{
                .num = page_info.num,
                .name = page_info.name,
            };
        }

        // Process in parallel
        var parallel_results = try thread_pool.processPagesParallel(
            allocator,
            @ptrCast(pool_pages),
            page_filter,
            encoder_path,
            decoder_path,
            tokenizer_path,
            max_tokens,
            num_jobs,
            temp_dir,
        );
        defer parallel_results.deinit(allocator);

        processed = parallel_results.processed;

        // Write results in order
        for (parallel_results.results) |page_result| {
            if (!page_result.success) {
                std.debug.print("  [{d}] Failed ({s})\n", .{ page_result.page_num, page_result.error_msg orelse "unknown" });
                continue;
            }

            try out_file.writeAll("## Page ");
            const page_num_str = try std.fmt.allocPrint(allocator, "{d}\n\n", .{page_result.page_num});
            defer allocator.free(page_num_str);
            try out_file.writeAll(page_num_str);
            try out_file.writeAll(page_result.text);
            try out_file.writeAll("\n\n---\n\n");

            total_chars += page_result.text.len;
            std.debug.print("  [{d}] {d} chars\n", .{ page_result.page_num, page_result.text.len });

            // Delete processed page file
            const page_filename = try std.fmt.allocPrint(allocator, "page-{d:0>2}.png", .{page_result.page_num});
            defer allocator.free(page_filename);
            const page_path = try std.fs.path.join(allocator, &.{ temp_dir, page_filename });
            defer allocator.free(page_path);
            std.fs.cwd().deleteFile(page_path) catch {};
        }
    } else {
        // Sequential processing
        for (page_files[0..idx]) |page_info| {
            // Check if this page should be processed based on filter
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
                // Clean up skipped page
                const page_path = try std.fs.path.join(allocator, &.{ temp_dir, page_info.name });
                defer allocator.free(page_path);
                std.fs.cwd().deleteFile(page_path) catch {};
                continue;
            }

            processed += 1;
            const page_path = try std.fs.path.join(allocator, &.{ temp_dir, page_info.name });
            defer allocator.free(page_path);

            // Progress indicator
            std.debug.print("  [{d}] ", .{page_info.num});

            const text = engine.processImage(page_path) catch |err| {
                std.debug.print("Failed ({s})\n", .{@errorName(err)});
                continue;
            };
            defer allocator.free(text);

            try out_file.writeAll("## Page ");
            const page_num_str = try std.fmt.allocPrint(allocator, "{d}\n\n", .{page_info.num});
            defer allocator.free(page_num_str);
            try out_file.writeAll(page_num_str);
            try out_file.writeAll(text);
            try out_file.writeAll("\n\n---\n\n");

            total_chars += text.len;
            std.debug.print("{d} chars\n", .{text.len});

            std.fs.cwd().deleteFile(page_path) catch {};
        }
    }

    const process_time = timer.read() / std.time.ns_per_ms;

    // Summary
    std.debug.print("\n=========================\n", .{});
    std.debug.print("Complete!\n", .{});
    std.debug.print("  Output: {s}\n", .{output_path});
    std.debug.print("  Mode:   {s}\n", .{if (append_mode) "append" else "overwrite"});
    std.debug.print("  Pages:  {d} processed", .{processed});

    switch (page_filter) {
        .single => |n| std.debug.print(" (page {d} only)", .{n}),
        .list => |list| {
            std.debug.print(" (", .{});
            for (list, 0..) |n, j| {
                if (j > 0) std.debug.print(",", .{});
                std.debug.print("{d}", .{n});
            }
            std.debug.print(")", .{});
        },
        .range => |r| std.debug.print(" (pages {d}-{d})", .{ r.start, r.end }),
        .all => {},
    }
    std.debug.print("\n", .{});

    std.debug.print("  Chars:  {d}\n", .{total_chars});
    std.debug.print("  Time:   {d}ms\n", .{process_time});
    if (processed > 0) {
        std.debug.print("  Avg:    {d}ms/page\n", .{process_time / processed});
    }

    // Cleanup
    std.fs.cwd().deleteTree(temp_dir) catch {};
}

fn extractPageNumber(filename: []const u8) !u32 {
    // Extract number from "page-01.png" format
    const start = std.mem.indexOfScalar(u8, filename, '-') orelse return error.InvalidFormat;
    const end = std.mem.indexOfScalar(u8, filename, '.');

    const num_str = if (end) |e| filename[start + 1 .. e] else filename[start + 1 ..];
    return std.fmt.parseUnsigned(u32, num_str, 10);
}
