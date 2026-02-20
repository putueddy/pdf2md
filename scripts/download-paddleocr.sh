#!/bin/bash
# Download PaddleOCR ONNX models from Hugging Face
# PaddleOCR is 10x smaller than Nougat with better accuracy

set -e

echo "═══════════════════════════════════════════════════"
echo "  Downloading PaddleOCR ONNX Models"
echo "═══════════════════════════════════════════════════"
echo ""
echo "PaddleOCR PP-OCRv5 advantages:"
echo "  - 10x smaller than Nougat (~110MB vs 1.3GB)"
echo "  - Better accuracy on printed text"
echo "  - 48+ languages supported"
echo "  - Production-ready, actively maintained"
echo ""

# Check for huggingface-cli
if ! command -v huggingface-cli &> /dev/null; then
    echo "Installing huggingface-hub..."
    pip install huggingface-hub
fi

# Create models directory
mkdir -p models/paddleocr-onnx

echo "Downloading English PaddleOCR models..."
echo ""

# Detection model (finds text regions)
echo "1. Downloading detection model (finds text regions)..."
huggingface-cli download monkt/paddleocr-onnx \
    --include "detection/v5/det.onnx" \
    --local-dir models/paddleocr-onnx \
    --local-dir-use-symlinks False

# Recognition model (reads text)
echo ""
echo "2. Downloading recognition model (reads text)..."
huggingface-cli download monkt/paddleocr-onnx \
    --include "recognition/en/en_PP-OCRv4_rec.onnx" \
    --local-dir models/paddleocr-onnx \
    --local-dir-use-symlinks False

# Character dictionary
echo ""
echo "3. Downloading character dictionary..."
huggingface-cli download monkt/paddleocr-onnx \
    --include "recognition/en/dict.txt" \
    --local-dir models/paddleocr-onnx \
    --local-dir-use-symlinks False

# Organize files
echo ""
echo "Organizing model files..."
mkdir -p models/paddleocr-onnx/det models/paddleocr-onnx/rec

if [ -f "models/paddleocr-onnx/detection/v5/det.onnx" ]; then
    mv models/paddleocr-onnx/detection/v5/det.onnx models/paddleocr-onnx/det/
fi

if [ -f "models/paddleocr-onnx/recognition/en/en_PP-OCRv4_rec.onnx" ]; then
    mv models/paddleocr-onnx/recognition/en/en_PP-OCRv4_rec.onnx models/paddleocr-onnx/rec/
fi

if [ -f "models/paddleocr-onnx/recognition/en/dict.txt" ]; then
    mv models/paddleocr-onnx/recognition/en/dict.txt models/paddleocr-onnx/rec/
fi

# Clean up empty directories
rm -rf models/paddleocr-onnx/detection models/paddleocr-onnx/recognition

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Download Complete!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Model files:"
ls -lh models/paddleocr-onnx/det/*.onnx models/paddleocr-onnx/rec/*.onnx 2>/dev/null || true
echo ""
echo "Character dictionary:"
ls -lh models/paddleocr-onnx/rec/dict.txt 2>/dev/null || true
echo ""
echo "To use PaddleOCR:"
echo "  ./pdf2md document.pdf output.md --ocr paddleocr"
echo ""

# Calculate total size
total_size=$(du -sh models/paddleocr-onnx 2>/dev/null | cut -f1)
echo "Total model size: $total_size"
