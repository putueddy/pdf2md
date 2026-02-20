.PHONY: all build test clean run install model help onnx-coreml info

ZIG = zig
BUILD_DIR = zig-out
BIN = $(BUILD_DIR)/bin/pdf2md
MODEL_DIR = models/nougat-base

# ONNX Runtime path (can be overridden)
ONNXRUNTIME_DIR ?= /opt/homebrew/opt/onnxruntime

all: build

help:
	@echo "PDF2MD - PDF to Markdown Converter"
	@echo ""
	@echo "Available targets:"
	@echo "  make build              - Build the project"
	@echo "  make build-coreml       - Build with CoreML-enabled ONNX"
	@echo "  make onnx-coreml        - Build ONNX Runtime with CoreML"
	@echo "  make quantize           - Quantize models to INT8 (4x smaller)"
	@echo "  make test               - Run tests"
	@echo "  make run FILE=x         - Run with file"
	@echo "  make model              - Download AI model"
	@echo "  make clean              - Clean build artifacts"
	@echo "  make install            - Install binary to /usr/local/bin"
	@echo "  make check              - Check code formatting"
	@echo "  make fmt                - Format code"
	@echo "  make info               - Show build configuration"
	@echo ""
	@echo "Environment variables:"
	@echo "  ONNXRUNTIME_DIR=/path   - Use custom ONNX Runtime"

build:
	@echo "Compiling C wrapper..."
	@if [ -f "$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session/onnxruntime_c_api.h" ]; then \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -O3 -I$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session; \
	else \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -O3 -I$(ONNXRUNTIME_DIR)/include; \
	fi
	$(ZIG) build -Doptimize=ReleaseFast -Donnx-path=$(ONNXRUNTIME_DIR)

debug:
	@echo "Compiling C wrapper (debug)..."
	@if [ -f "$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session/onnxruntime_c_api.h" ]; then \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -g -I$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session; \
	else \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -g -I$(ONNXRUNTIME_DIR)/include; \
	fi
	$(ZIG) build -Doptimize=Debug -Donnx-path=$(ONNXRUNTIME_DIR)

build-coreml:
	@echo "Building with CoreML-enabled ONNX Runtime..."
	$(MAKE) build ONNXRUNTIME_DIR=.deps/onnxruntime

onnx-coreml:
	@echo "Building ONNX Runtime with CoreML support..."
	./scripts/build-onnx-coreml.sh
	@echo ""
	@echo "Now run: make build-coreml"

info:
	@echo "Build Configuration:"
	@echo "  ONNXRUNTIME_DIR: $(ONNXRUNTIME_DIR)"
	@echo ""
	@echo "To use CoreML GPU acceleration:"
	@echo "  1. make onnx-coreml    # Build ONNX with CoreML (~30-60 min)"
	@echo "  2. make build-coreml   # Build pdf2md with custom ONNX"

test:
	@echo "Compiling C wrapper for tests..."
	@if [ -f "$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session/onnxruntime_c_api.h" ]; then \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -O3 -I$(ONNXRUNTIME_DIR)/include/onnxruntime/core/session; \
	else \
		gcc -c src/ml/ort_wrapper.c -o src/ml/ort_wrapper.o -O3 -I$(ONNXRUNTIME_DIR)/include; \
	fi
	$(ZIG) build test -Donnx-path=$(ONNXRUNTIME_DIR)

run: build
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make run FILE=document.pdf"; \
		exit 1; \
	fi
	$(BIN) $(FILE)

model:
	./scripts/download-model.sh

quantize:
	@echo "Quantizing ONNX models to INT8..."
	./scripts/quantize-int8.sh

clean:
	rm -rf zig-cache zig-out .tmp

install: build
	sudo cp $(BIN) /usr/local/bin/
	@echo "Installed to /usr/local/bin/pdf2md"

check:
	$(ZIG) fmt --check src/

fmt:
	$(ZIG) fmt src/

# Development helpers
dev:
	$(ZIG) build run -- document.pdf

watch:
	find src -name "*.zig" | entr -r $(ZIG) build run -- document.pdf