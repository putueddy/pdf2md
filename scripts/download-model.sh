#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}📥 Downloading Nougat Model...${NC}"

# Create models directory
mkdir -p models/nougat-base

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 not found. Please install Python 3.8+${NC}"
    exit 1
fi

# Install required packages
echo -e "${YELLOW}📦 Installing Python dependencies...${NC}"
pip3 install -q transformers onnx onnxruntime optimum[exporters] pillow

# Download and convert model
echo -e "${YELLOW}🔄 Converting Nougat model to ONNX...${NC}"
python3 scripts/convert_model.py

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Model downloaded successfully!${NC}"
    echo -e "${GREEN}📁 Location: models/nougat-base/${NC}"
    ls -lh models/nougat-base/
else
    echo -e "${RED}❌ Model download failed${NC}"
    exit 1
fi
