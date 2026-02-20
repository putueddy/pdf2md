const std = @import("std");

/// PaddleOCR engine backed by RapidOCR (Python) using ONNX models.
/// This keeps integration simple and uses Paddle's production postprocessing.
pub const PaddleOCREngine = struct {
    allocator: std.mem.Allocator,
    det_model_path: []const u8,
    rec_model_path: []const u8,
    dict_path: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        det_model_path: []const u8,
        rec_model_path: []const u8,
        dict_path: []const u8,
    ) !PaddleOCREngine {
        // Validate model files eagerly.
        const det_file = try std.fs.cwd().openFile(det_model_path, .{});
        det_file.close();
        const rec_file = try std.fs.cwd().openFile(rec_model_path, .{});
        rec_file.close();
        const dict_file = try std.fs.cwd().openFile(dict_path, .{});
        dict_file.close();

        const det_copy = try allocator.dupe(u8, det_model_path);
        errdefer allocator.free(det_copy);
        const rec_copy = try allocator.dupe(u8, rec_model_path);
        errdefer allocator.free(rec_copy);
        const dict_copy = try allocator.dupe(u8, dict_path);
        errdefer allocator.free(dict_copy);

        return PaddleOCREngine{
            .allocator = allocator,
            .det_model_path = det_copy,
            .rec_model_path = rec_copy,
            .dict_path = dict_copy,
        };
    }

    pub fn deinit(self: *PaddleOCREngine) void {
        self.allocator.free(self.det_model_path);
        self.allocator.free(self.rec_model_path);
        self.allocator.free(self.dict_path);
    }

    pub fn processImage(self: *PaddleOCREngine, image_path: []const u8) ![]const u8 {
        const script =
            "from rapidocr_onnxruntime import RapidOCR\n" ++
            "import sys\n" ++
            "ocr = RapidOCR(det_model_path=sys.argv[1], rec_model_path=sys.argv[2], rec_keys_path=sys.argv[3])\n" ++
            "res, _ = ocr(sys.argv[4])\n" ++
            "if not res:\n" ++
            "    print('')\n" ++
            "else:\n" ++
            "    lines = [r[1] for r in res if len(r) >= 3 and r[2] >= 0.6 and r[1].strip()]\n" ++
            "    print('\\n'.join(lines))\n";

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "python3",
                "-c",
                script,
                self.det_model_path,
                self.rec_model_path,
                self.dict_path,
                image_path,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.RunFailed;
        }

        const out = std.mem.trim(u8, result.stdout, "\r\n");
        return try self.allocator.dupe(u8, out);
    }
};
