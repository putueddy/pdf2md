#!/bin/bash
# Quantize ONNX models to INT8 for 4x smaller size and faster inference
# Note: This requires the ONNX models to be already exported

set -e

echo "═══════════════════════════════════════════════════"
echo "  Quantizing ONNX Models to INT8"
echo "═══════════════════════════════════════════════════"
echo ""
echo "This will:"
echo "  - Convert encoder/decoder to INT8 precision"
echo "  - Reduce model size by ~75% (4x smaller)"
echo "  - Potentially improve inference speed on CPU"
echo "  - Maintain ~99% accuracy"
echo ""

# Check if models exist
if [ ! -d "models/nougat-onnx" ]; then
    echo "❌ Error: ONNX models not found at models/nougat-onnx/"
    echo "   Run: ./scripts/export-nougat.sh first"
    exit 1
fi

# Check for required Python packages
echo "Checking dependencies..."
python3 -c "import onnxruntime; import onnx" 2>/dev/null || {
    echo "Installing required packages..."
    pip install onnx onnxruntime onnxruntime-tools
}

# Create quantized models directory
mkdir -p models/nougat-onnx-int8

echo ""
echo "Quantizing encoder model..."
python3 << 'EOF'
import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType
import os

# Quantize encoder
encoder_input = "models/nougat-onnx/encoder_model.onnx"
encoder_output = "models/nougat-onnx-int8/encoder_model.onnx"

if os.path.exists(encoder_input):
    print(f"  Input:  {encoder_input}")
    print(f"  Output: {encoder_output}")
    
    # Dynamic quantization to INT8
    quantize_dynamic(
        model_input=encoder_input,
        model_output=encoder_output,
        weight_type=QuantType.QInt8  # Signed INT8
    )
    
    # Get file sizes
    input_size = os.path.getsize(encoder_input) / (1024 * 1024)
    output_size = os.path.getsize(encoder_output) / (1024 * 1024)
    reduction = (1 - output_size / input_size) * 100
    
    print(f"  Size:   {input_size:.1f}MB → {output_size:.1f}MB ({reduction:.1f}% reduction)")
    print("  ✅ Encoder quantized successfully")
else:
    print(f"  ❌ Encoder model not found: {encoder_input}")
    exit(1)
EOF

echo ""
echo "Quantizing decoder model..."
python3 << 'EOF'
import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType
import os

# Quantize decoder
decoder_input = "models/nougat-onnx/decoder_model.onnx"
decoder_output = "models/nougat-onnx-int8/decoder_model.onnx"

if os.path.exists(decoder_input):
    print(f"  Input:  {decoder_input}")
    print(f"  Output: {decoder_output}")
    
    # Dynamic quantization to INT8
    quantize_dynamic(
        model_input=decoder_input,
        model_output=decoder_output,
        weight_type=QuantType.QInt8  # Signed INT8
    )
    
    # Get file sizes
    input_size = os.path.getsize(decoder_input) / (1024 * 1024)
    output_size = os.path.getsize(decoder_output) / (1024 * 1024)
    reduction = (1 - output_size / input_size) * 100
    
    print(f"  Size:   {input_size:.1f}MB → {output_size:.1f}MB ({reduction:.1f}% reduction)")
    print("  ✅ Decoder quantized successfully")
else:
    print(f"  ❌ Decoder model not found: {decoder_input}")
    exit(1)
EOF

# Copy tokenizer and other files
echo ""
echo "Copying tokenizer files..."
cp models/nougat-onnx/*.json models/nougat-onnx-int8/ 2>/dev/null || true
cp models/nougat-onnx/*.txt models/nougat-onnx-int8/ 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Quantization Complete!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Quantized models location: models/nougat-onnx-int8/"
echo ""
echo "To use INT8 models:"
echo "  ./pdf2md input.pdf output.md --models models/nougat-onnx-int8"
echo ""
echo "Size comparison:"
ls -lh models/nougat-onnx/*.onnx models/nougat-onnx-int8/*.onnx 2>/dev/null | grep -E "(encoder|decoder)" || true
