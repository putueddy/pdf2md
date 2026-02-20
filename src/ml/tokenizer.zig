const std = @import("std");

/// Simple token ID to text converter for HuggingFace tokenizer.json format
pub const SimpleTokenizer = struct {
    allocator: std.mem.Allocator,
    vocab: [][]u8,

    pub fn initFromFile(allocator: std.mem.Allocator, path: []const u8) !SimpleTokenizer {
        // Load tokenizer.json
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 50 * 1024 * 1024);
        defer allocator.free(content);

        // Parse JSON using the new API
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value;

        if (root != .object) return error.InvalidTokenizer;

        const model = root.object.get("model") orelse return error.MissingModel;
        if (model != .object) return error.InvalidModel;

        const vocab = model.object.get("vocab") orelse return error.MissingVocab;
        if (vocab != .object) return error.InvalidVocab;

        // Find max token ID to allocate array
        var max_id: usize = 0;
        var vocab_iter = vocab.object.iterator();
        while (vocab_iter.next()) |entry| {
            const token_id = @as(usize, @intCast(entry.value_ptr.*.integer));
            if (token_id > max_id) max_id = token_id;
        }

        // Create vocab array indexed by ID
        const vocab_size = max_id + 1;
        var vocab_array = try allocator.alloc([]u8, vocab_size);
        errdefer allocator.free(vocab_array);

        // Initialize with empty strings
        for (vocab_array) |*item| {
            item.* = "";
        }

        vocab_iter.reset();
        while (vocab_iter.next()) |entry| {
            const token_str = entry.key_ptr.*;
            const token_id = @as(usize, @intCast(entry.value_ptr.*.integer));

            if (token_id < vocab_size) {
                vocab_array[token_id] = try allocator.dupe(u8, token_str);
            }
        }

        std.log.info("Loaded tokenizer: {d} tokens", .{vocab.object.count()});

        return SimpleTokenizer{
            .allocator = allocator,
            .vocab = vocab_array,
        };
    }

    pub fn deinit(self: *SimpleTokenizer) void {
        for (self.vocab) |token| {
            if (token.len > 0) {
                self.allocator.free(token);
            }
        }
        self.allocator.free(self.vocab);
    }

    /// Basic decode - concatenates tokens with ByteLevel decoding
    pub fn decode(self: *SimpleTokenizer, token_ids: []const i64) ![]const u8 {
        // Estimate max size (average 10 bytes per token)
        var result: []u8 = try self.allocator.alloc(u8, token_ids.len * 10);
        errdefer self.allocator.free(result);
        var result_len: usize = 0;

        var prev_was_word: bool = false;

        for (token_ids) |id| {
            if (id < 0 or id >= self.vocab.len) continue;

            const token = self.vocab[@intCast(id)];

            // Skip special tokens
            if (token.len >= 2 and token[0] == '<' and token[token.len - 1] == '>') {
                continue;
            }

            // ByteLevel BPE decoding
            // Ġ represents space at beginning of token (UTF-8: 0xC4 0xA0)
            if (token.len >= 2 and token[0] == 0xC4 and token[1] == 0xA0) {
                if (prev_was_word and result_len > 0) {
                    result[result_len] = ' ';
                    result_len += 1;
                }
                // Copy rest of token after Ġ
                if (token.len > 2) {
                    @memcpy(result[result_len .. result_len + token.len - 2], token[2..]);
                    result_len += token.len - 2;
                }
                prev_was_word = true;
            } else if (token.len == 2 and token[0] == 0xC4 and token[1] == 0x8A) {
                // Ċ = newline
                result[result_len] = '\n';
                result_len += 1;
                prev_was_word = false;
            } else if (token.len == 2 and token[0] == 0xC4 and token[1] == 0x89) {
                // ĉ = tab
                result[result_len] = '\t';
                result_len += 1;
                prev_was_word = false;
            } else {
                @memcpy(result[result_len .. result_len + token.len], token);
                result_len += token.len;
                prev_was_word = true;
            }
        }

        // Realloc to actual size
        return self.allocator.realloc(result, result_len);
    }
};
