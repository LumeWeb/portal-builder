# Portal Builder Base Image
# Build environment for compiling LumeWeb Portal with custom plugins via docker buildx
# Use as a base image in your Dockerfile: FROM ghcr.io/lumeweb/portal-builder:latest

FROM golang:1.27-alpine3.23

# Build arguments for yq version and checksum - override with --build-arg
ARG YQ_VERSION=v4.52.2
ARG YQ_SHA256=a74bd266990339e0c48a2103534aef692abf99f19390d12c2b0ce6830385c459

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    musl-dev \
    libwebp-dev \
    ca-certificates \
    tzdata \
    python3 \
    jq \
    curl \
    wget \
    unzip \
    bash

# Alpine 3.23's distro nodejs is 24.18.1, which satisfies tsdown's
# ^22.18.0 || ^24.11.0 || >=26.0.0 engine requirement. nodejs-current is avoided
# because the npm distro package hard-depends on nodejs and nodejs-current
# bundles no npm (only corepack).
# Pinned so a base-image drift to a lower Node version fails loudly here.
RUN apk add --no-cache nodejs=24.18.1-r0 npm

# Fail fast if a future base-image change drops Node outside the range
# tsdown accepts; without this, the drift surfaces as a pnpm build error.
RUN node -e "const [M,m]=process.versions.node.split('.').slice(0,2).map(Number);const ok=(M===22&&m>=18)||(M===24&&m>=11)||M>=26;if(!ok){console.error('Node '+process.version+' outside tsdown engine range');process.exit(1)}"

# Install pnpm for frontend asset builds
RUN npm install -g pnpm@10

# Install yq (YAML parser)
# Version pinned for reproducible builds; checksum verified for security
RUN curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 && \
    echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - && \
    chmod +x /usr/local/bin/yq

# Install xportal
RUN go install go.lumeweb.com/xportal/xcmd/xportal@latest

# Pre-populate Go module cache for common dependencies
# This significantly speeds up builds in child images by avoiding re-downloads
# Set explicit Go module cache path
ENV GOMODCACHE=/go/pkg/mod

# Create a temporary workspace for downloading modules
WORKDIR /tmp/cache-warmup

# Download Portal core dependencies (develop version)
# This creates go.mod and populates the module cache
RUN go mod init cache-warmup && \
    go get go.lumeweb.com/portal@develop && \
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
