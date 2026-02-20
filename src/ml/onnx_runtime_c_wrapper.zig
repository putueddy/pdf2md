const std = @import("std");

// Opaque handle types
pub const OrtEnv = opaque {};
pub const OrtSession = opaque {};
pub const OrtValue = opaque {};
pub const OrtMemoryInfo = opaque {};

// C wrapper extern declarations
extern fn ort_init() c_int;
extern fn ort_create_env(log_level: c_int, log_id: [*c]const u8) ?*OrtEnv;
extern fn ort_release_env(env: ?*OrtEnv) void;
extern fn ort_create_session(env: ?*OrtEnv, model_path: [*c]const u8) ?*OrtSession;
extern fn ort_release_session(session: ?*OrtSession) void;
extern fn ort_create_cpu_memory_info() ?*OrtMemoryInfo;
extern fn ort_release_memory_info(info: ?*OrtMemoryInfo) void;
extern fn ort_create_tensor(info: ?*OrtMemoryInfo, data: [*c]f32, data_len: usize, shape: [*c]i64, shape_len: usize) ?*OrtValue;
extern fn ort_create_tensor_int64(info: ?*OrtMemoryInfo, data: [*c]i64, data_len: usize, shape: [*c]i64, shape_len: usize) ?*OrtValue;
extern fn ort_release_value(value: ?*OrtValue) void;
extern fn ort_run_session(session: ?*OrtSession, input_names: [*c]const [*c]const u8, inputs: [*c]?*OrtValue, input_count: usize, output_names: [*c]const [*c]const u8, outputs: [*c]?*OrtValue, output_count: usize) c_int;
extern fn ort_get_tensor_data(value: ?*OrtValue, out_count: [*c]i64) [*c]f32;

pub const OnnxError = error{
    ApiInitFailed,
    EnvCreateFailed,
    SessionCreateFailed,
    RunFailed,
    TensorCreateFailed,
};

pub const Environment = struct {
    env: *OrtEnv,

    pub fn init(log_level: c_int) !Environment {
        if (ort_init() != 0) return error.ApiInitFailed;
        const env = ort_create_env(log_level, "pdf2md") orelse return error.EnvCreateFailed;
        return Environment{ .env = env };
    }

    pub fn deinit(self: *Environment) void {
        ort_release_env(self.env);
    }
};

pub const Session = struct {
    env: *Environment,
    session: *OrtSession,
    memory_info: *OrtMemoryInfo,

    pub fn init(env: *Environment, model_path: []const u8) !Session {
        const allocator = std.heap.page_allocator;
        const path_z = try allocator.dupeZ(u8, model_path);
        defer allocator.free(path_z);

        const session = ort_create_session(env.env, path_z.ptr) orelse return error.SessionCreateFailed;
        const memory_info = ort_create_cpu_memory_info() orelse return error.SessionCreateFailed;

        return Session{
            .env = env,
            .session = session,
            .memory_info = memory_info,
        };
    }

    pub fn deinit(self: *Session) void {
        ort_release_memory_info(self.memory_info);
        ort_release_session(self.session);
    }

    pub fn run(
        self: *Session,
        input_names: []const []const u8,
        inputs: []const Value,
        output_names: []const []const u8,
        allocator: std.mem.Allocator,
    ) ![]Value {
        const in_names = try allocator.alloc([*c]const u8, input_names.len);
        defer allocator.free(in_names);
        for (input_names, 0..) |name, i| {
            in_names[i] = name.ptr;
        }

        const in_values = try allocator.alloc(?*OrtValue, inputs.len);
        defer allocator.free(in_values);
        for (inputs, 0..) |input, i| {
            in_values[i] = input.value;
        }

        const out_names = try allocator.alloc([*c]const u8, output_names.len);
        defer allocator.free(out_names);
        for (output_names, 0..) |name, i| {
            out_names[i] = name.ptr;
        }

        const out_values = try allocator.alloc(?*OrtValue, output_names.len);
        defer allocator.free(out_values);
        @memset(out_values, null);

        const result = ort_run_session(
            self.session,
            in_names.ptr,
            in_values.ptr,
            input_names.len,
            out_names.ptr,
            out_values.ptr,
            output_names.len,
        );

        if (result != 0) return error.RunFailed;

        var results = try allocator.alloc(Value, output_names.len);
        errdefer allocator.free(results);

        for (out_values, 0..) |val, i| {
            if (val == null) return error.RunFailed;
            results[i] = Value{ .value = val.? };
        }

        return results;
    }
};

pub const Value = struct {
    value: *OrtValue,

    pub fn fromTensor(
        session: *Session,
        data: []f32,
        shape: []const i64,
    ) !Value {
        const value = ort_create_tensor(
            session.memory_info,
            data.ptr,
            data.len,
            @constCast(shape.ptr),
            shape.len,
        ) orelse return error.TensorCreateFailed;
        return Value{ .value = value };
    }

    pub fn fromTensorInt64(
        session: *Session,
        data: []i64,
        shape: []const i64,
    ) !Value {
        const value = ort_create_tensor_int64(
            session.memory_info,
            @constCast(data.ptr),
            data.len,
            @constCast(shape.ptr),
            shape.len,
        ) orelse return error.TensorCreateFailed;
        return Value{ .value = value };
    }

    pub fn deinit(self: *Value) void {
        ort_release_value(self.value);
    }

    pub fn getTensorData(self: *Value, allocator: std.mem.Allocator) ![]f32 {
        _ = allocator;
        var count: i64 = 0;
        const data = ort_get_tensor_data(self.value, &count);
        if (data == null) return error.RunFailed;
        return data[0..@intCast(count)];
    }
};

pub fn initialize() !void {
    if (ort_init() != 0) return error.ApiInitFailed;
}
