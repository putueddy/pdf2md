#!/bin/bash

# Build ONNX Runtime with CoreML support for Apple Silicon (M1/M2/M3/M4)
# This enables GPU acceleration on macOS

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$REPO_ROOT/.deps/onnxruntime-build"
INSTALL_DIR="$REPO_ROOT/.deps/onnxruntime"

echo "=============================================="
echo "Building ONNX Runtime with CoreML for Apple Silicon"
echo "=============================================="

# Check for Apple Silicon
if [[ $(uname -m) != "arm64" ]]; then
    echo "Warning: This is not an ARM64 Mac. CoreML build is for Apple Silicon only."
    echo "Current architecture: $(uname -m)"
fi

# Check for Xcode command line tools
if ! xcode-select -p &> /dev/null; then
    echo "Error: Xcode Command Line Tools not found"
    echo "Install with: xcode-select --install"
    exit 1
fi

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

# Check/install Eigen
if ! brew list eigen &> /dev/null; then
    echo "Installing Eigen via Homebrew..."
    brew install eigen
fi

# Clone ONNX Runtime if not exists
if [ ! -d "$BUILD_DIR/onnxruntime" ]; then
    echo ""
    echo "Cloning ONNX Runtime repository..."
    cd "$BUILD_DIR"
    git clone --recursive https://github.com/microsoft/onnxruntime.git
    cd onnxruntime
    # Checkout a stable version
    git checkout v1.20.1
    git submodule update --init --recursive
else
    echo ""
    echo "ONNX Runtime already cloned, updating..."
    cd "$BUILD_DIR/onnxruntime"
    git fetch
    git checkout v1.20.1
    git submodule update --init --recursive
fi

cd "$BUILD_DIR/onnxruntime"

echo ""
echo "=============================================="
echo "Building ONNX Runtime (this may take 30-60 min)"
echo "=============================================="

# Clean previous build
rm -rf build/MacOS/Release

# Temporarily hide Homebrew cmake files to avoid conflicts
echo ""
echo "Temporarily moving conflicting Homebrew cmake files..."
BREW_CMAKE_DIR="/opt/homebrew/lib/cmake"
if [ -d "$BREW_CMAKE_DIR" ]; then
    mv "$BREW_CMAKE_DIR" "$BREW_CMAKE_DIR.bak"
    mkdir -p "$BREW_CMAKE_DIR"
    trap "rm -rf '$BREW_CMAKE_DIR' && mv '$BREW_CMAKE_DIR.bak' '$BREW_CMAKE_DIR'" EXIT
fi

# Check if Eigen is installed via Homebrew
EIGEN_PATH=""
if brew list eigen &>/dev/null; then
    EIGEN_PATH=$(brew --prefix eigen)/include/eigen3
    echo "Found Homebrew Eigen at: $EIGEN_PATH"
fi

# Build with CoreML support
if [ -n "$EIGEN_PATH" ]; then
    # Use pre-installed Eigen
    ./build.sh \
        --config Release \
        --use_coreml \
        --build_shared_lib \
        --parallel \
        --skip_tests \
        --cmake_extra_defines "CMAKE_OSX_ARCHITECTURES=arm64" \
        --cmake_extra_defines "onnxruntime_BUILD_UNIT_TESTS=OFF" \
        --cmake_extra_defines "CMAKE_POLICY_VERSION_MINIMUM=3.5" \
        --cmake_extra_defines "onnxruntime_USE_PREINSTALLED_EIGEN=ON" \
        --cmake_extra_defines "eigen_SOURCE_PATH=$EIGEN_PATH"
else
    # Let it download Eigen (may fail due to hash mismatch)
    ./build.sh \
        --config Release \
        --use_coreml \
        --build_shared_lib \
        --parallel \
        --skip_tests \
        --cmake_extra_defines "CMAKE_OSX_ARCHITECTURES=arm64" \
        --cmake_extra_defines "onnxruntime_BUILD_UNIT_TESTS=OFF" \
        --cmake_extra_defines "CMAKE_POLICY_VERSION_MINIMUM=3.5"
fi

echo ""
echo "=============================================="
echo "Installing to $INSTALL_DIR"
echo "=============================================="

# Copy built libraries
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/include"

cp build/MacOS/Release/libonnxruntime*.dylib "$INSTALL_DIR/lib/" 2>/dev/null || true
cp build/MacOS/Release/libonnxruntime*.a "$INSTALL_DIR/lib/" 2>/dev/null || true

# Copy headers
# Create the expected directory structure
mkdir -p "$INSTALL_DIR/include/onnxruntime"
cp -r onnxruntime/core/session/*.h "$INSTALL_DIR/include/onnxruntime/" 2>/dev/null || true
# Also copy the entire onnxruntime directory structure for completeness
cp -r include/onnxruntime "$INSTALL_DIR/include/" 2>/dev/null || true

# Create symlinks for easier access
cd "$INSTALL_DIR/lib"
if [ -f "libonnxruntime.1.20.1.dylib" ]; then
    ln -sf libonnxruntime.1.20.1.dylib libonnxruntime.dylib
fi

echo ""
echo "=============================================="
echo "Build Complete!"
echo "=============================================="
echo ""
echo "ONNX Runtime with CoreML installed to:"
echo "  $INSTALL_DIR"
echo ""
echo "To use with pdf2md:"
echo "  export ONNXRUNTIME_DIR=$INSTALL_DIR"
echo "  make clean && make"
echo ""
echo "Or directly:"
echo "  zig build-exe src/pdf2md.zig src/ml/ort_wrapper.o \\"
echo "    -lonnxruntime -O ReleaseFast \\"
echo "    -L$INSTALL_DIR/lib \\"
echo "    -I$INSTALL_DIR/include \\"
echo "    --name pdf2md"
echo ""

# Check the built library
if [ -f "$INSTALL_DIR/lib/libonnxruntime.dylib" ]; then
    echo "Verifying CoreML support..."
    if nm "$INSTALL_DIR/lib/libonnxruntime.dylib" 2>/dev/null | grep -q "CoreML"; then
        echo "✅ CoreML symbols found in library!"
    else
        echo "⚠️  CoreML symbols not detected (may still work)"
    fi
fi
