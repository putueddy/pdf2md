# Multi-stage build for pdf2md
FROM ubuntu:24.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    xz-utils \
    build-essential \
    libpoppler-glib-dev \
    libcairo2-dev \
    pkg-config \
    python3 \
    python3-pip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
ENV ZIG_VERSION=0.13.0
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz | tar xJ \
    && mv zig-linux-x86_64-${ZIG_VERSION} /opt/zig \
    && ln -s /opt/zig/zig /usr/local/bin/zig

# Set working directory
WORKDIR /app

# Copy source code
COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY scripts/ ./scripts/
COPY Makefile ./

# Build the application
RUN zig build -Doptimize=ReleaseFast

# Download model (optional - can be mounted at runtime)
# RUN ./scripts/download-model.sh

# Runtime stage
FROM ubuntu:24.04 AS runtime

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libpoppler-glib8 \
    libcairo2 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 pdf2md

# Copy binary
COPY --from=builder /app/zig-out/bin/pdf2md /usr/local/bin/

# Copy model (optional - prefer mount)
# COPY --from=builder /app/models /models

# Set up working directory
WORKDIR /workspace
RUN chown pdf2md:pdf2md /workspace

USER pdf2md

# Entry point
ENTRYPOINT ["pdf2md"]
CMD ["--help"]