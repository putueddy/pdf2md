#!/bin/bash
# Export Nougat model to ONNX - Run this separately as it takes 10+ minutes

echo "═══════════════════════════════════════════════════"
echo "  Exporting Facebook Nougat to ONNX"
echo "═══════════════════════════════════════════════════"
echo ""
echo "This process downloads ~1.4GB model and converts to ONNX."
echo "Expected time: 10-20 minutes depending on connection."
echo ""

# Activate virtual environment
source .venv/bin/activate

# Export model
mkdir -p models/nougat-onnx

optimum-cli export onnx \
    --model facebook/nougat-base \
    --task image-to-text \
    --dtype fp32 \
    ./models/nougat-onnx/

echo ""
echo "═══════════════════════════════════════════════════"
if [ $? -eq 0 ]; then
    echo "✅ Export completed successfully!"
    ls -lh models/nougat-onnx/
else
    echo "❌ Export failed"
    exit 1
fi
