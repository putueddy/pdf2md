#include <onnxruntime/onnxruntime_c_api.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static const OrtApi* g_api = NULL;

// External declaration for CoreML EP (available when ONNX is built with CoreML)
// Define USE_COREML to enable CoreML support, or leave undefined for CPU-only builds
#ifdef USE_COREML
#ifdef __APPLE__
extern OrtStatus* OrtSessionOptionsAppendExecutionProvider_CoreML(OrtSessionOptions* options, uint32_t coreml_flags);
#endif
#endif

// GPU Provider type
typedef enum {
    GPU_NONE,
    GPU_CUDA,
    GPU_METAL,
    GPU_COREML_AVAILABLE,  // CoreML EP compiled but not enabled
    GPU_COREML_ACTIVE      // CoreML EP active
} GpuProviderType;

static GpuProviderType g_gpu_provider = GPU_NONE;
static char g_gpu_info[256] = "CPU";

// Forward declarations
OrtSession* ort_create_session_with_gpu(OrtEnv* env, const char* model_path, int use_gpu);

int ort_init() {
    const OrtApiBase* base = OrtGetApiBase();
    if (!base) return -1;
    g_api = base->GetApi(ORT_API_VERSION);
    return g_api ? 0 : -1;
}

// Check for CUDA availability
static int check_cuda_available() {
    #ifdef _WIN32
        return 0;
    #else
        FILE* fp = popen("which nvidia-smi 2>/dev/null", "r");
        if (fp) {
            char buffer[256];
            if (fgets(buffer, sizeof(buffer), fp) != NULL) {
                pclose(fp);
                return 1;
            }
            pclose(fp);
        }
        return 0;
    #endif
}

// Check for Apple Silicon (Metal capable)
static int check_apple_silicon() {
    #ifdef __APPLE__
        FILE* fp = popen("sysctl -n machdep.cpu.brand_string 2>/dev/null", "r");
        if (fp) {
            char buffer[256];
            if (fgets(buffer, sizeof(buffer), fp) != NULL) {
                pclose(fp);
                if (strstr(buffer, "Apple") != NULL) {
                    return 1;
                }
            } else {
                pclose(fp);
            }
        }
    #endif
    return 0;
}

// Check if CoreML EP is available in this ONNX build
static int check_coreml_available() {
    #ifdef __APPLE__
        // Check if CoreML symbols are available at runtime
        // The OrtSessionOptionsAppendExecutionProvider_CoreML function
        // is only available when ONNX is built with CoreML support
        return 1;  // Assume available on Apple Silicon, will fail gracefully if not
    #endif
    return 0;
}

// Auto-detect best GPU provider
static GpuProviderType detect_gpu_provider() {
    if (check_cuda_available()) {
        snprintf(g_gpu_info, sizeof(g_gpu_info), "CUDA");
        return GPU_CUDA;
    }
    
    #ifdef __APPLE__
        if (check_apple_silicon()) {
            if (check_coreml_available()) {
                snprintf(g_gpu_info, sizeof(g_gpu_info), "CoreML (Metal)");
                return GPU_COREML_AVAILABLE;
            } else {
                snprintf(g_gpu_info, sizeof(g_gpu_info), "Apple Silicon detected but CoreML not compiled (rebuild ONNX with CoreML EP)");
                return GPU_METAL;
            }
        }
    #endif
    
    snprintf(g_gpu_info, sizeof(g_gpu_info), "CPU");
    return GPU_NONE;
}

// Add CUDA EP to session options
static int add_cuda_ep(OrtSessionOptions* options) {
    #ifdef USE_CUDA
        OrtCUDAProviderOptions cuda_options;
        memset(&cuda_options, 0, sizeof(cuda_options));
        cuda_options.device_id = 0;
        cuda_options.cudnn_conv_algo_search = OrtCudnnConvAlgoSearchHeuristic;
        cuda_options.gpu_mem_limit = SIZE_MAX;
        cuda_options.arena_extend_strategy = 0;
        cuda_options.do_copy_in_default_stream = 1;
        cuda_options.has_user_compute_stream = 0;
        cuda_options.default_memory_arena_cfg = NULL;

        OrtStatus* status = g_api->SessionOptionsAppendExecutionProvider_CUDA(options, &cuda_options);
        if (status) {
            g_api->ReleaseStatus(status);
            return -1;
        }
        return 0;
    #else
        (void)options;
        return -1;
    #endif
}

// Add Metal/CoreML EP to session options
static int add_coreml_ep(OrtSessionOptions* options) {
    #if defined(__APPLE__) && defined(USE_COREML)
        // CoreML provider with all optimizations enabled
        // Note: This requires ONNX Runtime built with CoreML support
        OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CoreML(options, 0);
        if (status) {
            const char* msg = g_api->GetErrorMessage(status);
            snprintf(g_gpu_info, sizeof(g_gpu_info), "CoreML error: %s", msg);
            g_api->ReleaseStatus(status);
            return -1;
        }
        snprintf(g_gpu_info, sizeof(g_gpu_info), "CoreML (Metal/GPU)");
        return 0;
    #else
        (void)options;
        snprintf(g_gpu_info, sizeof(g_gpu_info), "CoreML not available (Apple platforms only)");
        return -1;
    #endif
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
    return ort_create_session_with_gpu(env, model_path, 1);
}

OrtSession* ort_create_session_with_gpu(OrtEnv* env, const char* model_path, int use_gpu) {
    OrtSessionOptions* options = NULL;
    OrtStatus* status = g_api->CreateSessionOptions(&options);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    
    // Graph optimizations - always enabled for best performance
    status = g_api->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    if (status) {
        g_api->ReleaseStatus(status);
        g_api->ReleaseSessionOptions(options);
        return NULL;
    }
    
    // Try GPU if requested
    int gpu_enabled = 0;
    if (use_gpu) {
        g_gpu_provider = detect_gpu_provider();
        
        if (g_gpu_provider == GPU_CUDA) {
            if (add_cuda_ep(options) == 0) {
                gpu_enabled = 1;
            } else {
                g_gpu_provider = GPU_NONE;
                snprintf(g_gpu_info, sizeof(g_gpu_info), "CUDA available but EP failed to load");
            }
        } else if (g_gpu_provider == GPU_COREML_AVAILABLE || g_gpu_provider == GPU_METAL) {
            if (add_coreml_ep(options) == 0) {
                gpu_enabled = 1;
                g_gpu_provider = GPU_COREML_ACTIVE;
            } else {
                // CoreML not available, fall back to CPU but keep info
                g_gpu_provider = GPU_METAL;
                snprintf(g_gpu_info, sizeof(g_gpu_info), "Apple Silicon detected - CoreML not available in ONNX build");
            }
        }
    }
    
    // If GPU not available or failed, use CPU with threading
    if (!gpu_enabled) {
        g_api->SetIntraOpNumThreads(options, 4);
        g_api->SetInterOpNumThreads(options, 4);
        if (g_gpu_provider == GPU_NONE) {
            snprintf(g_gpu_info, sizeof(g_gpu_info), "CPU (4 threads)");
        }
    }
    
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

// Get GPU provider info
int ort_get_gpu_provider() {
    return (int)g_gpu_provider;
}

const char* ort_get_gpu_provider_name() {
    return g_gpu_info;
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

// Create GPU memory info if available
OrtMemoryInfo* ort_create_gpu_memory_info() {
    if (g_gpu_provider == GPU_NONE || g_gpu_provider == GPU_METAL) {
        return ort_create_cpu_memory_info();
    }
    
    OrtMemoryInfo* info = NULL;
    const char* device_type = (g_gpu_provider == GPU_CUDA) ? "Cuda" : "Cpu";
    OrtStatus* status = g_api->CreateMemoryInfo(
        device_type,
        OrtArenaAllocator,
        0,
        OrtMemTypeDefault,
        &info
    );
    
    if (status) {
        g_api->ReleaseStatus(status);
        return ort_create_cpu_memory_info();
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
    
    size_t count = 0;
    status = g_api->GetTensorShapeElementCount(info, &count);
    g_api->ReleaseTensorTypeAndShapeInfo(info);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    *out_count = (int64_t)count;
    
    void* data = NULL;
    status = g_api->GetTensorMutableData(value, &data);
    if (status) {
        g_api->ReleaseStatus(status);
        return NULL;
    }
    
    return (float*)data;
}

// Synchronize GPU operations (for CUDA)
void ort_synchronize() {
    // Placeholder for CUDA stream synchronization if needed
    // In most cases, ONNX Runtime handles this automatically
}
