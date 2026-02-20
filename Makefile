.PHONY: all build test clean run install model help

ZIG = zig
BUILD_DIR = zig-out
BIN = $(BUILD_DIR)/bin/pdf2md
MODEL_DIR = models/nougat-base

all: build

help:
	@echo "PDF2MD - PDF to Markdown Converter"
	@echo ""
	@echo "Available targets:"
	@echo "  make build       - Build the project"
	@echo "  make test        - Run tests"
	@echo "  make run FILE=x  - Run with file"
	@echo "  make model       - Download AI model"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make install     - Install binary to /usr/local/bin"
	@echo "  make check       - Check code formatting"
	@echo "  make fmt         - Format code"

build:
	$(ZIG) build -Doptimize=ReleaseFast

debug:
	$(ZIG) build -Doptimize=Debug

test:
	$(ZIG) build test

run: build
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make run FILE=document.pdf"; \
		exit 1; \
	fi
	$(BIN) $(FILE)

model:
	./scripts/download-model.sh

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