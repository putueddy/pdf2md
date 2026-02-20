const std = @import("std");
const onnx = @import("onnx_runtime_c_wrapper.zig");
const preprocess = @import("../image/ml_preprocess.zig");
const tokenizer = @import("tokenizer.zig");

/// Pure Zig Nougat inference engine with proper tokenization
pub const NougatEngine = struct {
    allocator: std.mem.Allocator,
    env: onnx.Environment,
    encoder: onnx.Session,
    decoder: onnx.Session,
    tok: tokenizer.SimpleTokenizer,
    max_tokens: usize,

    const BOS_TOKEN: i64 = 0;
    const EOS_TOKEN: i64 = 2;

    pub fn init(allocator: std.mem.Allocator, encoder_path: []const u8, decoder_path: []const u8, tokenizer_path: []const u8, max_tokens: usize) !NougatEngine {
        try onnx.initialize();

        var env = try onnx.Environment.init(2); // WARNING level
        errdefer env.deinit();

        var enc = try onnx.Session.init(&env, encoder_path);
        errdefer enc.deinit();

        var dec = try onnx.Session.init(&env, decoder_path);
        errdefer dec.deinit();

        // Load tokenizer
        var tok = try tokenizer.SimpleTokenizer.initFromFile(allocator, tokenizer_path);
        errdefer tok.deinit();

        return NougatEngine{
            .allocator = allocator,
            .env = env,
            .encoder = enc,
            .decoder = dec,
            .tok = tok,
            .max_tokens = max_tokens,
        };
    }

    pub fn deinit(self: *NougatEngine) void {
        self.tok.deinit();
        self.encoder.deinit();
        self.decoder.deinit();
        self.env.deinit();
    }

    pub fn processImage(self: *NougatEngine, image_path: []const u8) ![]const u8 {
        // Load and preprocess image
        const image_data = try self.loadImageData(image_path);
        defer self.allocator.free(image_data.data);

        const tensor = try preprocess.ImagePreprocessor.preprocessForNougat(
            self.allocator,
            image_data.data,
            image_data.width,
            image_data.height,
            image_data.width * 4,
        );
        defer {
            self.allocator.free(tensor.data);
            self.allocator.free(tensor.shape);
        }

        // Run encoder
        var encoder_input = try onnx.Value.fromTensor(
            &self.encoder,
            tensor.data,
            tensor.shape,
        );
        defer encoder_input.deinit();

        const encoder_outputs = try self.encoder.run(
            &.{"pixel_values"},
            &.{encoder_input},
            &.{"last_hidden_state"},
            self.allocator,
        );
        defer {
            for (encoder_outputs) |*output| {
                output.deinit();
            }
            self.allocator.free(encoder_outputs);
        }

        // Autoregressive decoding
        var tokens = try self.allocator.alloc(i64, self.max_tokens);
        defer self.allocator.free(tokens);
        var tokens_len: usize = 0;
        tokens[tokens_len] = BOS_TOKEN;
        tokens_len += 1;

        for (0..self.max_tokens) |_| {
            if (tokens_len >= self.max_tokens) break;

            const decoder_input_data = tokens[0..tokens_len];
            const decoder_input_shape = try self.allocator.dupe(i64, &.{ 1, @intCast(tokens_len) });
            defer self.allocator.free(decoder_input_shape);

            var decoder_input = try onnx.Value.fromTensorInt64(
                &self.decoder,
                decoder_input_data,
                decoder_input_shape,
            );
            defer decoder_input.deinit();

            const decoder_outputs = try self.decoder.run(
                &.{ "input_ids", "encoder_hidden_states" },
                &.{ decoder_input, encoder_outputs[0] },
                &.{"logits"},
                self.allocator,
            );
            defer {
                for (decoder_outputs) |*output| {
                    output.deinit();
                }
                self.allocator.free(decoder_outputs);
            }

            const logits = try decoder_outputs[0].getTensorData(self.allocator);
            const vocab_size = logits.len / tokens_len;
            const last_logits = logits[(tokens_len - 1) * vocab_size .. tokens_len * vocab_size];

            const next_token = argmax(last_logits);

            if (next_token == EOS_TOKEN) break;

            tokens[tokens_len] = next_token;
            tokens_len += 1;
        }

        // Decode tokens to text using proper tokenizer
        return try self.tok.decode(tokens[0..tokens_len]);
    }

    fn argmax(data: []const f32) i64 {
        var max_idx: usize = 0;
        var max_val = data[0];
        for (data, 0..) |val, i| {
            if (val > max_val) {
                max_val = val;
                max_idx = i;
            }
        }
        return @intCast(max_idx);
    }

    fn loadImageData(self: *NougatEngine, path: []const u8) !struct { data: []u8, width: u32, height: u32 } {
        const temp_path = ".tmp/img.bin";
        try std.fs.cwd().makePath(".tmp");

        const script = try std.fmt.allocPrint(self.allocator, "from PIL import Image; " ++
            "img = Image.open('{s}').convert('RGBA'); " ++
            "open('{s}', 'wb').write(img.tobytes()); " ++
            "print(f'{{img.width}},{{img.height}}')", .{ path, temp_path });
        defer self.allocator.free(script);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "python3", "-c", script },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.ImageLoadError;
        }

        const dims_str = std.mem.trim(u8, result.stdout, " \n");
        var dims_iter = std.mem.splitScalar(u8, dims_str, ',');

        const width = try std.fmt.parseUnsigned(u32, dims_iter.next() orelse return error.ParseError, 10);
        const height = try std.fmt.parseUnsigned(u32, dims_iter.next() orelse return error.ParseError, 10);

        const file = try std.fs.cwd().openFile(temp_path, .{});
        defer file.close();

        const stat = try file.stat();
        const data = try file.readToEndAlloc(self.allocator, @intCast(stat.size));

        std.fs.cwd().deleteFile(temp_path) catch {};

        return .{ .data = data, .width = width, .height = height };
    }
};
