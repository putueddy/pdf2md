const std = @import("std");

pub fn main() !void {
    std.debug.print("═══════════════════════════════════════════════════\n", .{});
    std.debug.print("  PDF → Image Pipeline Test\n", .{});
    std.debug.print("═══════════════════════════════════════════════════\n\n", .{});

    // Check CLI arguments
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: test-pdf-pipeline <pdf-file> [dpi]\n\n", .{});
        std.debug.print("Example: zig run scripts/test-pdf-pipeline.zig document.pdf 300\n\n", .{});
        std.debug.print("Requirements:\n", .{});
        std.debug.print("  - pdftoppm (install: brew install poppler)\n", .{});
        std.debug.print("  - pdfinfo (usually included with poppler)\n\n", .{});
        return error.MissingArguments;
    }

    const pdf_path = args[1];
    const dpi = if (args.len > 2)
        std.fmt.parseUnsigned(u32, args[2], 10) catch 200
    else
        200;

    // Check if pdftoppm is available
    std.debug.print("🔍 Checking dependencies...\n", .{});
    const check_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pdftoppm", "-v" },
    }) catch |err| {
        std.debug.print("❌ pdftoppm not found ({s})!\n", .{@errorName(err)});
        std.debug.print("💡 Install with: brew install poppler\n", .{});
        return error.MissingDependency;
    };
    defer allocator.free(check_result.stdout);
    defer allocator.free(check_result.stderr);
    std.debug.print("✅ pdftoppm available\n\n", .{});

    // Check if PDF exists
    std.debug.print("📄 Checking PDF file: {s}\n", .{pdf_path});
    const file = std.fs.cwd().openFile(pdf_path, .{}) catch |err| {
        std.debug.print("❌ Cannot open PDF: {s}\n", .{@errorName(err)});
        return err;
    };
    file.close();
    std.debug.print("✅ PDF file found\n\n", .{});

    // Create temp directory
    const temp_dir = ".tmp/pdf2md";
    try std.fs.cwd().makePath(temp_dir);
    std.debug.print("📁 Temp directory: {s}\n", .{temp_dir});

    // Prepare output prefix
    const output_prefix = try std.fs.path.join(allocator, &.{ temp_dir, "page" });
    defer allocator.free(output_prefix);

    // Format DPI
    const dpi_str = try std.fmt.allocPrint(allocator, "{d}", .{dpi});
    defer allocator.free(dpi_str);

    std.debug.print("🔄 Converting PDF to PNG images (DPI: {d})...\n", .{dpi});

    // Run pdftoppm
    var timer = try std.time.Timer.start();

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "pdftoppm",
            "-png",
            "-r",
            dpi_str,
            pdf_path,
            output_prefix,
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("❌ pdftoppm failed with exit code {d}\n", .{result.term.Exited});
        std.debug.print("stderr: {s}\n", .{result.stderr});
        return error.PdfConversionError;
    }

    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    std.debug.print("✅ Conversion completed in {d}ms\n\n", .{elapsed_ms});

    // Count generated files
    var temp_dir_handle = try std.fs.cwd().openDir(temp_dir, .{});
    defer temp_dir_handle.close();

    var iter = temp_dir_handle.iterate();
    var page_count: u32 = 0;
    var total_bytes: u64 = 0;

    std.debug.print("📊 Generated files:\n", .{});
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".png")) continue;

        const file_handle = try temp_dir_handle.openFile(entry.name, .{});
        defer file_handle.close();
        const stat = try file_handle.stat();

        page_count += 1;
        total_bytes += stat.size;

        std.debug.print("   {s}: {d:.2} KB\n", .{ entry.name, @as(f64, @floatFromInt(stat.size)) / 1024.0 });
    }

    std.debug.print("\n═══════════════════════════════════════════════════\n", .{});
    std.debug.print("Summary:\n", .{});
    std.debug.print("═══════════════════════════════════════════════════\n", .{});
    std.debug.print("Total pages: {d}\n", .{page_count});
    std.debug.print("Total size: {d:.2} MB\n", .{@as(f64, @floatFromInt(total_bytes)) / 1024.0 / 1024.0});
    std.debug.print("Average per page: {d:.2} KB\n", .{@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(page_count)) / 1024.0});
    std.debug.print("Time: {d}ms\n", .{elapsed_ms});

    std.debug.print("\n💡 Files saved to: {s}/\n", .{temp_dir});
    std.debug.print("   Next step: Process images with ML model\n", .{});
}
