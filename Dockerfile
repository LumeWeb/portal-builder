# Portal Builder Base Image
# Build environment for compiling LumeWeb Portal with custom plugins via docker buildx
# Use as a base image in your Dockerfile: FROM ghcr.io/lumeweb/portal-builder:latest

FROM golang:1.25-alpine

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    musl-dev \
    libwebp-dev \
    ca-certificates \
    tzdata \
    python3

# Install yq (YAML parser)
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq

# Install xportal
RUN GOPROXY=direct go install go.lumeweb.com/xportal/cmd/xportal@latest

# Pre-populate Go module cache for common dependencies
# This significantly speeds up builds in child images by avoiding re-downloads
# Set explicit Go module cache path
ENV GOMODCACHE=/go/pkg/mod

# Create a temporary workspace for downloading modules
WORKDIR /tmp/cache-warmup

# Download Portal core dependencies (develop version)
# This creates go.mod and populates the module cache
RUN go mod init cache-warmup && \
    GOPROXY=direct go get go.lumeweb.com/portal@develop && \
    go mod download go.lumeweb.com/portal@develop && \
    # Clean up temporary files
    rm -rf /tmp/cache-warmup

# Return to standard working directory
WORKDIR /workspace

# Install check-jsonschema for YAML validation using uv
# Create venv and install (only needed during build, discarded in final image)
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir check-jsonschema && \
    ln -s /opt/venv/bin/check-jsonschema /usr/local/bin/check-jsonschema

# Copy build script and schema
COPY build-portal.sh /usr/local/bin/build-portal
COPY schema.json /usr/local/share/portal-builder/schema.json
RUN chmod +x /usr/local/bin/build-portal

# Set default environment variables
ENV PLUGIN_MANIFEST=portal-plugins.yaml
ENV SCHEMA_PATH=/usr/local/share/portal-builder/schema.json
ENV OUTPUT_DIR=/dist
ENV PATH="/root/.local/bin:${PATH}"

# Set working directory
WORKDIR /workspace

# No ENTRYPOINT - this is a base image for buildx
# Users will RUN build-portal in their Dockerfiles
