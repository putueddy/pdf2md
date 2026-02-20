#include <onnxruntime/onnxruntime_c_api.h>
#include <stdlib.h>

static const OrtApi* g_api = NULL;

int ort_init() {
    const OrtApiBase* base = OrtGetApiBase();
    if (!base) return -1;
    g_api = base->GetApi(ORT_API_VERSION);
    return g_api ? 0 : -1;
}

OrtEnv* ort_create_env(int log_level, const char* log_id) {
    OrtEnv* env = NULL;
    OrtStatus* status = g_api->CreateEnv(log_level, log_id, &env);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    return env;
}

void ort_release_env(OrtEnv* env) {
    if (env) g_api->ReleaseEnv(env);
}

OrtSession* ort_create_session(OrtEnv* env, const char* model_path) {
    OrtSessionOptions* options = NULL;
    OrtStatus* status = g_api->CreateSessionOptions(&options);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    
    g_api->SetIntraOpNumThreads(options, 4);
    g_api->SetInterOpNumThreads(options, 4);
    g_api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    
    OrtSession* session = NULL;
    status = g_api->CreateSession(env, model_path, options, &session);
    g_api->ReleaseSessionOptions(options);
    
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    return session;
}

void ort_release_session(OrtSession* session) {
    if (session) g_api->ReleaseSession(session);
}

OrtMemoryInfo* ort_create_cpu_memory_info() {
    OrtMemoryInfo* info = NULL;
    OrtStatus* status = g_api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &info);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    return info;
}

void ort_release_memory_info(OrtMemoryInfo* info) {
    if (info) g_api->ReleaseMemoryInfo(info);
}

OrtValue* ort_create_tensor(OrtMemoryInfo* info, float* data, size_t data_len, int64_t* shape, size_t shape_len) {
    OrtValue* value = NULL;
    OrtStatus* status = g_api->CreateTensorWithDataAsOrtValue(
        info, data, data_len * sizeof(float), shape, shape_len, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &value);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    return value;
}

OrtValue* ort_create_tensor_int64(OrtMemoryInfo* info, int64_t* data, size_t data_len, int64_t* shape, size_t shape_len) {
    OrtValue* value = NULL;
    OrtStatus* status = g_api->CreateTensorWithDataAsOrtValue(
        info, data, data_len * sizeof(int64_t), shape, shape_len, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &value);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    return value;
}

void ort_release_value(OrtValue* value) {
    if (value) g_api->ReleaseValue(value);
}

int ort_run_session(OrtSession* session, 
                    const char** input_names, 
                    OrtValue** inputs, 
                    size_t input_count,
                    const char** output_names, 
                    OrtValue** outputs, 
                    size_t output_count) {
    OrtStatus* status = g_api->Run(session, NULL, 
                                    (const char* const*)input_names, 
                                    (const OrtValue* const*)inputs, 
                                    input_count, 
                                    (const char* const*)output_names, 
                                    output_count, 
                                    outputs);
    if (status) {
        g_api->ReleaseStatus(status);
        return -1;
    }
    return 0;
}

float* ort_get_tensor_data(OrtValue* value, int64_t* out_count) {
    OrtTensorTypeAndShapeInfo* info = NULL;
    OrtStatus* status = g_api->GetTensorTypeAndShape(value, &info);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    
    g_api->GetTensorShapeElementCount(info, out_count);
    g_api->ReleaseTensorTypeAndShapeInfo(info);
    
    void* data = NULL;
    status = g_api->GetTensorMutableData(value, &data);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    
    return (float*)data;
}
