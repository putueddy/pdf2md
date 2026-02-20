const std = @import("std");

/// Image preprocessor for ML models - pure Zig implementation
pub const ImagePreprocessor = struct {
    /// Nougat expects 896x672 RGB images
    pub const NOUGAT_HEIGHT = 896;
    pub const NOUGAT_WIDTH = 672;
    pub const NOUGAT_MEAN = [_]f32{ 0.5, 0.5, 0.5 };
    pub const NOUGAT_STD = [_]f32{ 0.5, 0.5, 0.5 };

    /// Resize image using bilinear interpolation
    pub fn resize(
        allocator: std.mem.Allocator,
        src: []const u8,
        src_width: u32,
        src_height: u32,
        dst_width: u32,
        dst_height: u32,
        channels: u32,
    ) ![]u8 {
        const dst_size = dst_width * dst_height * channels;
        var dst = try allocator.alloc(u8, dst_size);
        errdefer allocator.free(dst);

        const x_ratio = @as(f32, @floatFromInt(src_width)) / @as(f32, @floatFromInt(dst_width));
        const y_ratio = @as(f32, @floatFromInt(src_height)) / @as(f32, @floatFromInt(dst_height));

        for (0..dst_height) |dy| {
            for (0..dst_width) |dx| {
                const src_x = @as(f32, @floatFromInt(dx)) * x_ratio;
                const src_y = @as(f32, @floatFromInt(dy)) * y_ratio;

                const x0: u32 = @intFromFloat(@floor(src_x));
                const y0: u32 = @intFromFloat(@floor(src_y));
                const x1 = @min(x0 + 1, src_width - 1);
                const y1 = @min(y0 + 1, src_height - 1);

                const fx = src_x - @floor(src_x);
                const fy = src_y - @floor(src_y);

                for (0..channels) |c| {
                    const idx00 = ((y0 * src_width + x0) * channels + c);
                    const idx01 = ((y0 * src_width + x1) * channels + c);
                    const idx10 = ((y1 * src_width + x0) * channels + c);
                    const idx11 = ((y1 * src_width + x1) * channels + c);

                    const v00 = @as(f32, @floatFromInt(src[idx00]));
                    const v01 = @as(f32, @floatFromInt(src[idx01]));
                    const v10 = @as(f32, @floatFromInt(src[idx10]));
                    const v11 = @as(f32, @floatFromInt(src[idx11]));

                    const v0 = v00 * (1.0 - fx) + v01 * fx;
                    const v1 = v10 * (1.0 - fx) + v11 * fx;
                    const v = v0 * (1.0 - fy) + v1 * fy;

                    const dst_idx = ((dy * dst_width + dx) * channels + c);
                    dst[dst_idx] = @as(u8, @intFromFloat(@round(v)));
                }
            }
        }

        return dst;
    }

    /// Normalize image pixels to [-1, 1] range
    pub fn normalizeToTensor(
        allocator: std.mem.Allocator,
        src: []const u8,
        height: u32,
        width: u32,
        mean: []const f32,
        std_dev: []const f32,
    ) ![]f32 {
        const channels: u32 = 3;
        const size = height * width * channels;
        var dst = try allocator.alloc(f32, size);
        errdefer allocator.free(dst);

        for (0..height) |y| {
            for (0..width) |x| {
                for (0..channels) |c| {
                    const src_idx = (y * width + x) * channels + c;
                    const dst_idx = (c * height + y) * width + x; // CHW format

                    const pixel = @as(f32, @floatFromInt(src[src_idx])) / 255.0;
                    dst[dst_idx] = (pixel - mean[c]) / std_dev[c];
                }
            }
        }

        return dst;
    }

    /// Convert ARGB (Cairo format) to RGB
    pub fn argbToRgb(
        allocator: std.mem.Allocator,
        argb: []const u8,
        width: u32,
        height: u32,
        stride: u32,
    ) ![]u8 {
        const rgb_size = width * height * 3;
        var rgb = try allocator.alloc(u8, rgb_size);
        errdefer allocator.free(rgb);

        for (0..height) |y| {
            for (0..width) |x| {
                const src_idx = y * stride + x * 4;
                const dst_idx = (y * width + x) * 3;

                // ARGB format (big-endian): A R G B
                // We want RGB
                rgb[dst_idx + 0] = argb[src_idx + 1]; // R
                rgb[dst_idx + 1] = argb[src_idx + 2]; // G
                rgb[dst_idx + 2] = argb[src_idx + 3]; // B
            }
        }

        return rgb;
    }

    /// Full preprocessing pipeline for Nougat
    pub fn preprocessForNougat(
        allocator: std.mem.Allocator,
        image_data: []const u8,
        width: u32,
        height: u32,
        stride: u32,
    ) !struct { data: []f32, shape: []const i64 } {
        // Convert ARGB to RGB
        const rgb = try argbToRgb(allocator, image_data, width, height, stride);
        defer allocator.free(rgb);

        // Resize to Nougat dimensions
        const resized = try resize(allocator, rgb, width, height, NOUGAT_WIDTH, NOUGAT_HEIGHT, 3);
        defer allocator.free(resized);

        // Normalize to tensor
        const tensor_data = try normalizeToTensor(allocator, resized, NOUGAT_HEIGHT, NOUGAT_WIDTH, &NOUGAT_MEAN, &NOUGAT_STD);

        const shape = try allocator.dupe(i64, &.{ 1, 3, NOUGAT_HEIGHT, NOUGAT_WIDTH });

        return .{ .data = tensor_data, .shape = shape };
    }
};

/// Simple PNG loader (simplified - for production use zigimg)
pub const PngLoader = struct {
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !struct { data: []u8, width: u32, height: u32 } {
        // For now, we'll shell out to Python/PIL to load PNG and output raw bytes
        // This is a temporary solution until zigimg is properly integrated

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{
                "python3", "-c",
                try std.fmt.allocPrint(allocator, "import sys; from PIL import Image; img = Image.open('{s}').convert('RGB'); " ++
                    "sys.stdout.buffer.write(img.tobytes()); print(f'\\n{width},{height}', end='', file=sys.stderr)", .{path}),
            },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.ImageLoadError;
        }

        // Parse dimensions from stderr
        var dims_iter = std.mem.splitScalar(u8, std.mem.trim(u8, result.stderr, "\n"), ',');
        const width = try std.fmt.parseUnsigned(u32, dims_iter.next() orelse return error.ParseError, 10);
        const height = try std.fmt.parseUnsigned(u32, dims_iter.next() orelse return error.ParseError, 10);

        // Copy image data
        const data = try allocator.dupe(u8, result.stdout);

        return .{ .data = data, .width = width, .height = height };
    }
};
