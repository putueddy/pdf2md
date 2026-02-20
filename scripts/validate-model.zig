const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator();

    std.debug.print("═══════════════════════════════════════════════════\n", .{});
    std.debug.print("  ONNX Model Validator for zml\n", .{});
    std.debug.print("═══════════════════════════════════════════════════\n\n", .{});

    // Check available model directories
    const model_dirs = [_][]const u8{
        "models/nougat-base",
        "models/layoutlmv3-base",
        "models/layoutlmv3-onnx",
    };

    var found_any = false;
    var onnx_models_found: u32 = 0;

    for (model_dirs) |dir| {
        std.debug.print("📁 Checking: {s}/\n", .{dir});

        var dir_handle = std.fs.cwd().openDir(dir, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("   ⏸️  Directory not found\n\n", .{});
                continue;
            }
            return err;
        };
        defer dir_handle.close();

        found_any = true;

        // List files in directory
        var iter = dir_handle.iterate();
        var has_model = false;
        var total_size: u64 = 0;

        while (try iter.next()) |entry| {
            const name = entry.name;
            total_size += 1;

            if (std.mem.endsWith(u8, name, ".onnx")) {
                has_model = true;
                onnx_models_found += 1;
                std.debug.print("   ✅ Model: {s}\n", .{name});

                // Check file size
                const file = dir_handle.openFile(name, .{}) catch continue;
                defer file.close();
                const stat = try file.stat();
                std.debug.print("      Size: {d:.2} MB\n", .{@as(f64, @floatFromInt(stat.size)) / 1024.0 / 1024.0});
            } else if (std.mem.eql(u8, name, "tokenizer.json") or
                std.mem.eql(u8, name, "vocab.json"))
            {
                std.debug.print("   📄 Tokenizer: {s}\n", .{name});
            }
        }

        if (total_size == 0) {
            std.debug.print("   ⚠️  Empty directory\n", .{});
        } else if (!has_model) {
            std.debug.print("   ⚠️  Tokenizer files only - ONNX model missing!\n", .{});
        }

        std.debug.print("\n", .{});
    }

    if (!found_any) {
        std.debug.print("❌ No model directories found!\n\n", .{});
        std.debug.print("💡 To download models:\n", .{});
        std.debug.print("   ./scripts/download-model.sh\n\n", .{});
        std.debug.print("   Or manually:\n", .{});
        std.debug.print("   pip install optimum[onnxruntime]\n", .{});
        std.debug.print("   optimum-cli export onnx --model facebook/nougat-base ./models/nougat-base/\n", .{});
        return error.NoModelsFound;
    }

    std.debug.print("═══════════════════════════════════════════════════\n", .{});
    if (onnx_models_found > 0) {
        std.debug.print("✅ Status: {d} ONNX model(s) ready for zml\n", .{onnx_models_found});
    } else {
        std.debug.print("⚠️  Status: Tokenizers present, ONNX models missing\n", .{});
    }
    std.debug.print("═══════════════════════════════════════════════════\n", .{});
}
