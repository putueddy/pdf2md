# Architecture Overview

## System Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    pdf2md - Pure Zig PDF OCR                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │     CLI      │────▶│  PDF Parser  │────▶│  Preprocess  │            │
│  │  (pdf2md)    │     │  (Poppler)   │     │   (Image)    │            │
│  └──────────────┘     └──────────────┘     └──────┬───────┘            │
│         │                                         │                     │
│         │                                         ▼                     │
│         │                              ┌──────────────┐                │
│         │                              │    ONNX      │                │
│         │                              │   Runtime    │                │
│         │                              └──────┬───────┘                │
│         │                                     │                         │
│         │                                     ▼                         │
│         │                              ┌──────────────┐                │
│         │                              │   Nougat     │                │
│         │                              │Encoder-Decoder│               │
│         │                              └──────┬───────┘                │
│         │                                     │                         │
│         │                                     ▼                         │
│         │                              ┌──────────────┐                │
│         │                              │  Tokenizer   │                │
│         │                              │  (BPE/50K)   │                │
│         │                              └──────┬───────┘                │
│         │                                     │                         │
│         └─────────────────────────────────────▶                         │
│                                               ▼                         │
│                                        ┌──────────────┐                │
│                                        │  output.md   │                │
│                                        └──────────────┘                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Hierarchy

```
src/
├── pdf2md.zig                  # Entry point, CLI parsing, orchestration
├── ml/
│   ├── nougat_engine.zig       # Main inference engine
│   │   ├── Encoder session management
│   │   ├── Decoder autoregressive generation
│   │   └── Token accumulation
│   ├── onnx_runtime_c_wrapper.zig  # Zig bindings for ONNX C API
│   │   ├── Environment initialization
│   │   ├── Session management
│   │   ├── Tensor operations
│   │   └── Inference execution
│   ├── tokenizer.zig           # HuggingFace BPE tokenizer
│   │   ├── JSON vocabulary loading (50K tokens)
│   │   ├── ByteLevel BPE decoding
│   │   └── Token ID → text conversion
│   └── ort_wrapper.c           # C wrapper for ONNX Runtime
│       ├── API initialization
│       ├── Session creation
│       ├── Tensor creation
│       └── Run inference
└── image/
    └── ml_preprocess.zig       # Image preprocessing for ML
        ├── ARGB → RGB conversion
        ├── Bilinear resize to 896×672
        └── ImageNet normalization
```

## Data Flow

```
1. INPUT: scanned.pdf
   │
   ▼
2. CLI Parsing (pdf2md.zig)
   ├── Parse arguments (--page, --pages, --append, etc.)
   ├── Validate inputs
   └── Setup page filter
   │
   ▼
3. PDF to Image (Poppler/pdftoppm)
   ├── Spawn pdftoppm process
   ├── Convert at 200 DPI
   └── Generate PNG files (page-01.png, page-02.png, ...)
   │
   ▼
4. Page Filtering
   ├── Collect all page files
   ├── Sort by page number
   └── Filter based on --page/--pages arguments
   │
   ▼
5. Image Preprocessing (ml_preprocess.zig)
   ├── Load PNG via Python/PIL (temporary)
   ├── Convert ARGB to RGB
   ├── Bilinear resize: original → 896×672
   ├── Normalize: (pixel/255 - mean) / std
   └── Create tensor [1, 3, 896, 672]
   │
   ▼
6. ONNX Inference (nougat_engine.zig)
   │
   ├── 6a. Encoder Forward Pass
   │   ├── Create input tensor
   │   ├── Run encoder model
   │   └── Get encoder_hidden_states
   │
   ├── 6b. Autoregressive Decoding (loop)
   │   ├── Prepare decoder input (token IDs)
   │   ├── Run decoder model
   │   ├── Get logits
   │   ├── Argmax → next token ID
   │   ├── Append to token list
   │   └── Repeat until EOS or max_tokens
   │
   ▼
7. Token Decoding (tokenizer.zig)
   ├── Load tokenizer.json (50K vocab)
   ├── For each token ID:
   │   ├── Lookup token string
   │   ├── Handle ByteLevel encoding (Ġ = space)
   │   └── Append to result
   └── Return decoded text
   │
   ▼
8. Markdown Output (pdf2md.zig)
   ├── Write "## Page N" header
   ├── Write decoded text
   ├── Write separator "---"
   └── Append to output file
   │
   ▼
9. Cleanup
   ├── Delete temp PNG files
   ├── Release ONNX resources
   └── Close output file
```

## Key Design Decisions

### 1. **Pure Zig + ONNX Runtime C API**
- No complex ML framework dependencies
- Direct control over memory and inference
- Cross-platform ONNX model support
- Minimal runtime overhead

### 2. **External Process for PDF**
- Use `pdftoppm` (Poppler) via std.ChildProcess
- Avoid complex PDF parsing libraries
- Battle-tested, handles all PDF variants
- Parallelizable (future enhancement)

### 3. **Custom BPE Tokenizer**
- Parse HuggingFace tokenizer.json directly
- No Python/Transformers dependency for inference
- ~50K vocabulary, ByteLevel BPE encoding
- Handles Indonesian and English text

### 4. **Modular Inference Engine**
- Encoder-decoder architecture separate from pipeline
- Easy to swap models (Nougat, Donut, etc.)
- Clear error propagation
- Testable components

### 5. **Page-Level Processing**
- Each page processed independently
- Memory efficient (one page at a time)
- Flexible page selection (--page, --pages)
- Append mode for incremental processing

## Memory Management

```
┌────────────────────────────────────────┐
│  GPA (General Purpose Allocator)       │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │  Per-Page Arena                  │  │
│  │  ┌────────┐ ┌────────┐          │  │
│  │  │Image   │ │Tensor  │          │  │
│  │  │Data    │ │Data    │          │  │
│  │  └────────┘ └────────┘          │  │
│  │       ↓          ↓               │  │
│  │  ┌──────────────────┐           │  │
│  │  │  ONNX Session    │           │  │
│  │  │  - Encoder       │           │  │
│  │  │  - Decoder       │           │  │
│  │  └──────────────────┘           │  │
│  │       ↓                          │  │
│  │  ┌────────┐ ┌────────┐          │  │
│  │  │Tokens  │ │Output  │          │  │
│  │  │(i64[]) │ │String  │          │  │
│  │  └────────┘ └────────┘          │  │
│  └──────────────────────────────────┘  │
│                                        │
│  Persistent:                           │
│  ┌──────────────────────────────────┐  │
│  │  Tokenizer vocab (50K strings)   │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘

Page Lifecycle:
1. Load PNG image → allocate image buffer
2. Preprocess → allocate tensor
3. Encoder → allocate encoder output
4. Decoder loop → allocate token array
5. Tokenize → allocate output string
6. Write to file
7. Free all page allocations
8. Next page...
```

## Component Details

### ONNX Runtime Wrapper (C)

```c
// Simplified API exposed to Zig
int ort_init();
OrtEnv* ort_create_env(int log_level, const char* log_id);
OrtSession* ort_create_session(OrtEnv* env, const char* model_path);
OrtValue* ort_create_tensor(OrtMemoryInfo* info, float* data, ...);
int ort_run_session(OrtSession* session, const char** inputs, ...);
float* ort_get_tensor_data(OrtValue* value, int64_t* count);
```

### Zig Bindings

```zig
pub const Session = struct {
    env: *Environment,
    session: *OrtSession,
    memory_info: *OrtMemoryInfo,
    
    pub fn init(env: *Environment, model_path: []const u8) !Session;
    pub fn run(self: *Session, inputs: []const Value, ...) ![]Value;
};

pub const Value = struct {
    value: *OrtValue,
    
    pub fn fromTensor(session: *Session, data: []f32, shape: []const i64) !Value;
    pub fn getTensorData(self: *Value) ![]f32;
};
```

### Tokenizer

```zig
pub const SimpleTokenizer = struct {
    vocab: [][]u8,  // 50K token strings indexed by ID
    
    pub fn initFromFile(allocator: Allocator, path: []const u8) !SimpleTokenizer;
    pub fn decode(self: *SimpleTokenizer, token_ids: []const i64) ![]const u8;
};

// ByteLevel BPE handling:
// Ġ (0xC4 0xA0) → space prefix
// Regular bytes → direct characters
```

## Performance Considerations

| Optimization | Impact | Status |
|-------------|--------|--------|
| ReleaseFast build | 5-10x faster | ✅ Enabled |
| ONNX Graph Optimization | 1.5x faster | ✅ Level 99 |
| 4-thread intra-op | Parallel encoding | ✅ Enabled |
| Per-page processing | Memory efficient | ✅ Implemented |
| GPU (CUDA/Metal) | 10x faster | 🚧 Future |
| INT8 quantization | 2x smaller | 🚧 ONNX opt |
| Parallel page processing | Linear scaling | 🚧 Thread pool |

## Extension Points

```zig
// Easy to add new models
pub const ModelType = enum {
    nougat_base,
    nougat_small,
    donut,
    layoutlmv3,
};

// Alternative backends
pub const Backend = enum {
    onnx_cpu,      // Current
    onnx_cuda,     // Future
    onnx_metal,    // Future (Apple Silicon)
};

// Page selection strategies
pub const PageFilter = union(enum) {
    all,
    single: u32,
    list: []const u32,
    range: struct { start: u32, end: u32 },
};
```

## Build Process

```
1. Compile C wrapper
   gcc -c ort_wrapper.c -o ort_wrapper.o
   
2. Compile Zig + link
   zig build-exe src/pdf2md.zig ort_wrapper.o \
     -lonnxruntime -O ReleaseFast
   
3. Result: pdf2md (379 KB binary)
```

## Dependencies

| Component | Dependency | Purpose |
|-----------|-----------|---------|
| PDF Parsing | Poppler (pdftoppm) | PDF → PNG |
| ML Runtime | ONNX Runtime 1.24+ | Model inference |
| Tokenization | Custom Zig | BPE decoding |
| Image Loading | Python/PIL (temp) | PNG → bytes |
| Build | Zig 0.13+ | Compilation |

Total runtime deps: `poppler`, `onnxruntime` (~20MB installed)
