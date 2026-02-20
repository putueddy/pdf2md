# Quick Start Guide

## 🚀 Get Running in 5 Minutes

### 1. Install Dependencies (macOS)

```bash
brew install zig poppler onnxruntime
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y zig poppler-utils onnxruntime
```

**Arch Linux:**
```bash
sudo pacman -S zig poppler onnxruntime
```

### 2. Clone and Build

```bash
git clone <repository>
cd pdf2md

# Build
./scripts/build.sh
# OR manually:
cd src/ml
gcc -c -I/opt/homebrew/Cellar/onnxruntime/1.24.2/include ort_wrapper.c -o ort_wrapper.o
cd ../..
zig build-exe src/pdf2md.zig src/ml/ort_wrapper.o \
  -femit-bin=pdf2md -L/opt/homebrew/lib -lonnxruntime -O ReleaseFast
```

### 3. Download Model (~1.4GB)

```bash
./scripts/export-nougat.sh
```

This downloads Facebook's Nougat model and converts it to ONNX format.

### 4. Convert Your First PDF

```bash
# Convert entire document
./pdf2md your-document.pdf output.md

# Or test with a single page (faster)
./pdf2md your-document.pdf output.md --page 1 --max-tokens 100
```

---

## 🛠️ Common Usage Patterns

### Process Specific Pages

```bash
# Single page
./pdf2md doc.pdf out.md --page 5

# Multiple pages
./pdf2md doc.pdf out.md --pages 1,3,5,10

# Page range
./pdf2md doc.pdf out.md --pages 1-10

# Combine multiple ranges
./pdf2md doc.pdf part1.md --pages 1-5
./pdf2md doc.pdf part1.md --pages 6-10 --append
```

### Quality vs Speed

```bash
# High quality (slower, more accurate)
./pdf2md doc.pdf out.md --dpi 300 --max-tokens 512

# Fast preview (lower quality)
./pdf2md doc.pdf out.md --dpi 150 --max-tokens 100

# Default (good balance)
./pdf2md doc.pdf out.md  # 200 DPI, 512 tokens
```

### Batch Processing

```bash
# Process multiple files
for pdf in *.pdf; do
    ./pdf2md "$pdf" "${pdf%.pdf}.md"
done

# Process with progress
for pdf in *.pdf; do
    echo "Processing: $pdf"
    ./pdf2md "$pdf" "${pdf%.pdf}.md" --page 1  # Quick test first page
    echo "Done: ${pdf%.pdf}.md"
done
```

---

## 🐳 Docker (Future)

```bash
# Build image (when Dockerfile is ready)
docker build -t pdf2md .

# Run conversion
docker run -v $(pwd):/workspace pdf2md document.pdf output.md
```

---

## 📋 Troubleshooting

### "pdftoppm: command not found"
```bash
# macOS
brew install poppler

# Ubuntu/Debian
sudo apt-get install poppler-utils
```

### "libonnxruntime.dylib not found"
```bash
# macOS - set library path
export DYLD_LIBRARY_PATH=/opt/homebrew/lib:$DYLD_LIBRARY_PATH

# Or install via brew
brew install onnxruntime
```

### "Model files not found"
```bash
# Download models
./scripts/export-nougat.sh

# Verify models exist
ls -lh models/nougat-onnx/
# Should show: encoder_model.onnx, decoder_model.onnx, tokenizer.json
```

### "Out of memory"
```bash
# Reduce memory usage
./pdf2md doc.pdf out.md --max-tokens 100  # Fewer tokens per page
./pdf2md doc.pdf out.md --page 1          # One page at a time
./pdf2md doc.pdf out.md --dpi 150         # Lower resolution
```

### Build fails
```bash
# Clean and rebuild
rm -f pdf2md src/ml/ort_wrapper.o
./scripts/build.sh

# Or manually with debug info
zig build-exe src/pdf2md.zig src/ml/ort_wrapper.o \
  -femit-bin=pdf2md-debug -L/opt/homebrew/lib -lonnxruntime
```

### PDF is encrypted
```bash
# Decrypt first (requires qpdf)
qpdf --decrypt encrypted.pdf decrypted.pdf
./pdf2md decrypted.pdf output.md
```

---

## 📝 Performance Tips

### For Speed
```bash
# Process single page for testing
./pdf2md doc.pdf test.md --page 1 --max-tokens 50

# Lower DPI
./pdf2md doc.pdf out.md --dpi 150
```

### For Quality
```bash
# Higher DPI
./pdf2md doc.pdf out.md --dpi 300

# More tokens per page
./pdf2md doc.pdf out.md --max-tokens 1024
```

### For Large Documents
```bash
# Process in chunks
./pdf2md big.pdf part1.md --pages 1-50
./pdf2md big.pdf part2.md --pages 51-100
./pdf2md big.pdf part3.md --pages 101-150
# Then combine
cat part1.md part2.md part3.md > full.md
```

---

## 🔍 Verification

Test your installation:

```bash
# Check binary works
./pdf2md --help

# Quick test (if you have test.pdf)
./pdf2md test.pdf test-output.md --page 1 --max-tokens 50
cat test-output.md
```

---

## 🎯 Next Steps

1. **Read the full docs**: [README.md](README.md) for complete usage
2. **Understand the architecture**: [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
3. **Customize for your needs**: Edit `src/pdf2md.zig` to add features

---

## 💡 Pro Tips

- Use `--pages` to process only the pages you need
- Use `--append` to build up output incrementally
- Test with `--max-tokens 50` before processing full documents
- Check output quality on page 1 first: `./pdf2md doc.pdf p1.md --page 1`
- For scanned documents with tables, use `--max-tokens 512` for better accuracy
