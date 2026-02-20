# PDF2MD 📄➡️📝

Convert scanned PDF documents to Markdown using AI (Pure Zig + ONNX Runtime + Nougat)

## Features

- 🖼️ **Scanned PDF Support** - Works with image-based PDFs (no text layer needed)
- 🧠 **AI-Powered** - Uses Facebook's Nougat model for accurate OCR
- ⚡ **Fast** - Pure Zig implementation with ONNX Runtime for ML inference
- 📊 **Preserves Structure** - Maintains headings, tables, and formatting
- 🔧 **Local Processing** - No cloud API required, runs entirely offline
- 📄 **Page Selection** - Process specific pages or ranges

## Prerequisites

### System Dependencies

**macOS:**
```bash
brew install poppler onnxruntime
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y libpoppler-glib-dev onnxruntime
```

**Arch Linux:**
```bash
sudo pacman -S poppler-glib onnxruntime
```

### Zig Version

Requires Zig 0.13.0 or later:
```bash
# Install via Homebrew (macOS)
brew install zig

# Or download from https://ziglang.org/download/
```

## Installation

### 1. Clone Repository

```bash
git clone <repository>
cd pdf2md
```

### 2. Build

```bash
# Compile C wrapper and Zig binary
cd src/ml
gcc -c -I/opt/homebrew/Cellar/onnxruntime/1.24.2/include ort_wrapper.c -o ort_wrapper.o
cd ../..

zig build-exe src/pdf2md.zig src/ml/ort_wrapper.o \
  -femit-bin=pdf2md \
  -L/opt/homebrew/lib \
  -lonnxruntime \
  -O ReleaseFast
```

### 3. Download Model

```bash
./scripts/export-nougat.sh
```

Models will be saved to `models/nougat-onnx/` directory (~1.4GB).

## Usage

### Basic Usage

```bash
# Convert entire PDF
./pdf2md document.pdf output.md

# Process specific page
./pdf2md document.pdf output.md --page 5

# Process multiple pages
./pdf2md document.pdf output.md --pages 1,3,5

# Process page range
./pdf2md document.pdf output.md --pages 1-10

# Append to existing file
./pdf2md document.pdf output.md --append --page 11
```

### CLI Options

```
pdf2md - Convert scanned PDFs to Markdown using AI

Usage: pdf2md <pdf-file> [output.md] [options]

Options:
  --max-tokens N      Maximum tokens per page (default: 512)
  --dpi N            DPI for PDF rendering (default: 200)
  --page N           Process only page N
  --pages N,M,...    Process specific pages (comma-separated)
  --pages N-M        Process page range N to M (inclusive)
  --append           Append to output file instead of overwriting

Examples:
  ./pdf2md doc.pdf output.md                    # All pages
  ./pdf2md doc.pdf output.md --page 5           # Page 5 only
  ./pdf2md doc.pdf output.md --pages 1,3,5      # Pages 1, 3, 5
  ./pdf2md doc.pdf output.md --pages 1-5        # Pages 1-5
  ./pdf2md doc.pdf output.md --append --page 6  # Append page 6
```

## Project Structure

```
pdf2md/
├── pdf2md                    # Binary (379 KB)
├── build.zig                 # Zig build configuration
├── src/
│   ├── pdf2md.zig           # Main entry point
│   ├── ml/
│   │   ├── nougat_engine.zig       # Core inference engine
│   │   ├── onnx_runtime_c_wrapper.zig  # ONNX C bindings
│   │   ├── tokenizer.zig           # BPE tokenizer (50K vocab)
│   │   └── ort_wrapper.c           # C wrapper for ONNX Runtime
│   └── image/
│       └── ml_preprocess.zig       # Image preprocessing
├── models/
│   └── nougat-onnx/          # Model files (~1.4GB)
│       ├── encoder_model.onnx
│       ├── decoder_model.onnx
│       └── tokenizer.json
├── scripts/
│   ├── export-nougat.sh      # Model export script
│   ├── download-model.sh
│   ├── validate-model.zig    # Debug helper
│   └── test-pdf-pipeline.zig # Debug helper
├── README.md
├── ARCHITECTURE.md
└── QUICKSTART.md
```

## How It Works

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│  Scanned    │───▶│  PDF → Image │───▶│   ONNX/Nougat│───▶│   Markdown   │
│    PDF      │    │  (Poppler)   │    │   Inference  │    │   Output     │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
      │                   │                   │                  │
      │              200 DPI               896×672 RGB      Clean formatting
      │               rendering            Encoder-Decoder
                                          Vision Transformer
```

1. **PDF Parser** (Poppler): Renders PDF pages to PNG images
2. **Image Preprocessing**: Resizes to 896×672, normalizes pixels
3. **ONNX Inference**: Encoder → visual features → Decoder → token IDs
4. **Tokenizer**: Decodes token IDs to text using BPE vocabulary
5. **Markdown Output**: Formatted with page separators

## Performance

| Pages | DPI | Time | Memory |
|-------|-----|------|--------|
| 1 | 200 | ~5s | 2GB |
| 10 | 200 | ~60s | 2.5GB |
| 12 | 200 | ~75s | 3GB |

*On Apple M3 with 16GB RAM*

## Architecture

Pure Zig implementation with minimal dependencies:
- **Zig 0.13+**: Core application logic
- **ONNX Runtime C API**: ML inference (via C wrapper)
- **Poppler**: PDF to image conversion
- **50K BPE Tokenizer**: Custom Zig implementation

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design.

## Troubleshooting

### "pdftoppm not found"
```bash
# macOS
brew install poppler

# Ubuntu
sudo apt-get install poppler-utils
```

### "libonnxruntime not found"
```bash
# macOS
brew install onnxruntime

# Or set library path
export DYLD_LIBRARY_PATH=/opt/homebrew/lib:$DYLD_LIBRARY_PATH
```

### "Model files not found"
```bash
./scripts/export-nougat.sh
```

### Out of Memory
```bash
# Reduce token limit
./pdf2md doc.pdf out.md --max-tokens 100

# Or process specific pages
./pdf2md doc.pdf out.md --page 1
```

## Development

### Build Debug Version
```bash
zig build-exe src/pdf2md.zig src/ml/ort_wrapper.o \
  -femit-bin=pdf2md-debug \
  -L/opt/homebrew/lib \
  -lonnxruntime
```

### Clean Build
```bash
rm -f pdf2md src/ml/ort_wrapper.o
# Rebuild as above
```

## Roadmap

- [ ] GPU acceleration (CUDA/Metal)
- [ ] Batch processing multiple files
- [ ] Table reconstruction improvement
- [ ] Formula (LaTeX) preservation
- [ ] Multi-column layout support
- [ ] Docker container
- [ ] Windows support

## License

MIT License - See LICENSE file

## Acknowledgments

- [Facebook Research Nougat](https://github.com/facebookresearch/nougat) - The OCR model
- [ONNX Runtime](https://onnxruntime.ai/) - Cross-platform ML inference
- [Poppler](https://poppler.freedesktop.org/) - PDF rendering
- Zig Programming Language - Systems programming done right
