const std = @import("std");

// Opaque handle types
pub const OrtEnv = opaque {};
pub const OrtSession = opaque {};
pub const OrtValue = opaque {};
pub const OrtMemoryInfo = opaque {};

// GPU Provider enum
pub const GpuProvider = enum(c_int) {
    none = 0,
    cuda = 1,
    metal = 2,
    coreml_available = 3,
    coreml_active = 4,
};

// C wrapper extern declarations
extern fn ort_init() c_int;
extern fn ort_create_env(log_level: c_int, log_id: [*c]const u8) ?*OrtEnv;
extern fn ort_release_env(env: ?*OrtEnv) void;
extern fn ort_create_session(env: ?*OrtEnv, model_path: [*c]const u8) ?*OrtSession;
extern fn ort_create_session_with_gpu(env: ?*OrtEnv, model_path: [*c]const u8, use_gpu: c_int) ?*OrtSession;
extern fn ort_release_session(session: ?*OrtSession) void;
extern fn ort_create_cpu_memory_info() ?*OrtMemoryInfo;
extern fn ort_create_gpu_memory_info() ?*OrtMemoryInfo;
extern fn ort_release_memory_info(info: ?*OrtMemoryInfo) void;
extern fn ort_create_tensor(info: ?*OrtMemoryInfo, data: [*c]f32, data_len: usize, shape: [*c]i64, shape_len: usize) ?*OrtValue;
extern fn ort_create_tensor_int64(info: ?*OrtMemoryInfo, data: [*c]i64, data_len: usize, shape: [*c]i64, shape_len: usize) ?*OrtValue;
extern fn ort_release_value(value: ?*OrtValue) void;
extern fn ort_run_session(session: ?*OrtSession, input_names: [*c]const [*c]const u8, inputs: [*c]?*OrtValue, input_count: usize, output_names: [*c]const [*c]const u8, outputs: [*c]?*OrtValue, output_count: usize) c_int;
extern fn ort_get_tensor_data(value: ?*OrtValue, out_count: [*c]i64) [*c]f32;
extern fn ort_get_gpu_provider() c_int;
extern fn ort_get_gpu_provider_name() [*c]const u8;
extern fn ort_synchronize() void;

pub const OnnxError = error{
    ApiInitFailed,
    EnvCreateFailed,
    SessionCreateFailed,
    RunFailed,
    TensorCreateFailed,
    GpuNotAvailable,
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
    use_gpu: bool,

    pub fn init(env: *Environment, model_path: []const u8) !Session {
        return initWithGpu(env, model_path, true);
    }

    pub fn initWithGpu(env: *Environment, model_path: []const u8, use_gpu: bool) !Session {
        const allocator = std.heap.page_allocator;
        const path_z = try allocator.dupeZ(u8, model_path);
        defer allocator.free(path_z);

        const session = if (use_gpu)
            ort_create_session_with_gpu(env.env, path_z.ptr, 1)
        else
            ort_create_session(env.env, path_z.ptr);

        const session_ptr = session orelse return error.SessionCreateFailed;

        // Try GPU memory info first if GPU is enabled
        var memory_info = ort_create_gpu_memory_info();
        if (memory_info == null) {
            memory_info = ort_create_cpu_memory_info();
        }
        const mem_info_ptr = memory_info orelse return error.SessionCreateFailed;

        // Check if GPU is actually being used
        const gpu_provider = @as(GpuProvider, @enumFromInt(ort_get_gpu_provider()));
        const actually_using_gpu = use_gpu and gpu_provider != .none;

        return Session{
            .env = env,
            .session = session_ptr,
            .memory_info = mem_info_ptr,
            .use_gpu = actually_using_gpu,
        };
    }

    pub fn deinit(self: *Session) void {
        ort_release_memory_info(self.memory_info);
        ort_release_session(self.session);
    }

    pub fn synchronize(self: *Session) void {
        if (self.use_gpu) {
            ort_synchronize();
        }
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

pub fn getGpuProvider() GpuProvider {
    return @as(GpuProvider, @enumFromInt(ort_get_gpu_provider()));
}

pub fn getGpuProviderName() []const u8 {
    const name_ptr = ort_get_gpu_provider_name();
    if (name_ptr == null) return "Unknown";
    const len = std.mem.len(name_ptr);
    return name_ptr[0..len];
}

pub fn isGpuAvailable() bool {
    return getGpuProvider() != .none;
}

pub fn printGpuInfo() void {
    const provider = getGpuProvider();
    const name = getGpuProviderName();
    std.debug.print("GPU Provider: {s} (code: {d})\n", .{ name, @intFromEnum(provider) });
}
