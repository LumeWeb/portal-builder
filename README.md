# Portal Builder Docker Image

Base image for compiling LumeWeb Portal with custom plugins via xportal. Designed for use with docker buildx multi-stage builds.

## Features

- **Base image pattern**: Extend in your own Dockerfile for custom builds
- **Pre-configured build environment**: Based on `golang:1.25-alpine`
- **xportal binary**: Pre-installed for building Portal
- **yq YAML parser**: For parsing plugin manifests
- **JSON schema validation**: Built-in validation for plugin manifests
- **Flexible configuration**: Supports both YAML manifests and environment variables
- **Custom Portal versions**: Build any Portal version via `PORTAL_VERSION`
- **Go module cache**: Pre-populated with Portal core dependencies for faster builds

## Go Module Cache

The portal-builder image includes a pre-populated Go module cache at `/go/pkg/mod` to significantly speed up builds in child images.

### How It Works

- The image pre-downloads the Portal core module (`go.lumeweb.com/portal@develop`) during the build process
- When child images run `build-portal`, xportal uses the cached modules instead of downloading them
- The `GOMODCACHE` environment variable is set to `/go/pkg/mod` to ensure consistent cache location

### Benefits

- **Faster builds**: Cached modules are available instantly, reducing download time
- **Reduced network usage**: Dependencies are only downloaded once when building the base image
- **Consistent builds**: All child images use the same cached dependencies

### Limitations

- The cache includes only the Portal core module at `latest` version
- Custom plugins not in the cache will still be downloaded during builds
- Different Portal versions (e.g., `develop`, specific tags) may require additional downloads

### Customizing the Cache

If you need to cache additional modules or specific versions, you can extend the builder image:

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder

# Cache specific plugin dependencies
WORKDIR /tmp/plugin-cache
RUN go mod init plugin-cache && \
    go get go.lumeweb.com/portal-plugin-dashboard@latest && \
    go mod download && \
    rm -rf /tmp/plugin-cache

COPY portal-plugins.yaml .
RUN build-portal
```

## Quick Start

### Build Your Custom Portal

Create a `Dockerfile`:

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder

COPY portal-plugins.yaml .
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

Create a `portal-plugins.yaml`:

```yaml
plugins:
  - module: go.lumeweb.com/portal-plugin-dashboard
    version: latest
  - module: go.lumeweb.com/portal-plugin-core
    version: latest
```

Build your image:

```bash
docker build -t my-portal .
```

## Usage Pattern

### Multi-Stage Build (Recommended)

```dockerfile
# Build stage
FROM ghcr.io/lumeweb/portal-builder:latest AS builder

# Copy configuration
COPY portal-plugins.yaml .

# Optional: Set portal version via ARG/ENV
ARG PORTAL_VERSION=latest
ENV PORTAL_VERSION=${PORTAL_VERSION}

# Build portal
RUN build-portal

# Runtime stage
FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

### Build with Specific Portal Version

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ARG PORTAL_VERSION=develop
ENV PORTAL_VERSION=${PORTAL_VERSION}
COPY portal-plugins.yaml .
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

Build:
```bash
docker build --build-arg PORTAL_VERSION=develop -t my-portal .
```

### Build with Git Hash

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ARG PORTAL_VERSION=a1b2c3d
ENV PORTAL_VERSION=${PORTAL_VERSION}
COPY portal-plugins.yaml .
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

Build:
```bash
docker build --build-arg PORTAL_VERSION=a1b2c3d -t my-portal .
```

Or use full hash:
```bash
docker build --build-arg PORTAL_VERSION=a1b2c3d4e5f6789012345678901234567890abcd -t my-portal .
```

### Build with Plugins from ENV

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ARG PLUGINS
ENV PLUGINS=${PLUGINS}
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

Build:
```bash
docker build --build-arg PLUGINS="go.lumeweb.com/portal-plugin-core@develop" -t my-portal .
```

## Configuration

### Method 1: YAML Manifest (Recommended)

Create `portal-plugins.yaml`:

```yaml
portalVersion: develop  # Optional: Portal core version (supports semantic version, latest, develop, or git hash)
plugins:
  - module: go.lumeweb.com/portal-plugin-dashboard
    version: latest
  - module: go.lumeweb.com/portal-plugin-core
    version: latest
```

Or with git hashes:

```yaml
portalVersion: a1b2c3d
plugins:
  - module: go.lumeweb.com/portal-plugin-dashboard
    version: a1b2c3d
  - module: go.lumeweb.com/portal-plugin-core
    version: a1b2c3d4e5f6789012345678901234567890abcd
```

### Method 2: Environment Variables

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ENV PORTAL_VERSION=develop
ENV PLUGINS="go.lumeweb.com/portal-plugin-dashboard@latest,go.lumeweb.com/portal-plugin-core@latest"
RUN build-portal
```

### Method 3: Hybrid (Both YAML and ENV)

Both sources can be used together - plugins from both will be combined.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORTAL_VERSION` | Portal core version to build | `latest` |
| `PLUGINS` | Comma or space-separated plugin list (format: `module@version`) | - |
| `PLUGIN_MANIFEST` | Path to YAML plugin manifest | `portal-plugins.yaml` |
| `OUTPUT_DIR` | Output directory for compiled binary | `/dist` |
| `SCHEMA_PATH` | Path to JSON schema for validation | `/usr/local/share/portal-builder/schema.json` |

## Schema Reference

### portal-plugins.yaml

```yaml
portalVersion: develop  # Optional: Portal core version (supports semantic version, latest, develop, or git hash)
plugins:
  - module: go.lumeweb.com/portal-plugin-example  # Go module path (required)
    version: latest                                 # Version (supports semantic version, latest, develop, or git hash)
```

### JSON Schema

The manifest is validated against the built-in schema. The schema enforces:

- `module`: Go module path (alphanumeric, dots, slashes, hyphens, underscores)
- `version`: Semantic version, `latest`, `develop`, or git hash (e.g., `v1.0.0`, `1.2.3`, `latest`, `v2.0.0-beta.1`, `a1b2c3d`, `a1b2c3d4e5f6789012345678901234567890abcd`)
- `portalVersion`: Portal core version (optional, supports `latest`, `develop`, semantic versions, or git hashes)

### Custom Schema

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
COPY custom-schema.json /usr/local/share/portal-builder/schema.json
COPY portal-plugins.yaml .
RUN build-portal
```

## Buildx Multi-Platform

Build for multiple platforms:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t my-portal:latest \
  --push \
  .
```

## Advanced Examples

### Minimal Portal (No Plugins)

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

### Development Build

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ENV PORTAL_VERSION=develop
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

### Production Build with Specific Versions

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder
ARG PORTAL_VERSION=latest
ENV PORTAL_VERSION=${PORTAL_VERSION}
COPY portal-plugins.yaml .
RUN build-portal

FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

## Notes

- Plugin versions support semantic versioning (e.g., `v1.2.3`), `latest`, `develop`, or git hashes
- The `@latest` version can be omitted (e.g., `go.lumeweb.com/plugin@latest` = `go.lumeweb.com/plugin`)
- All plugins are built into a single Portal binary
- The build process requires internet access to download Go modules
- The image includes a non-root user setup following security best practices
- Go module cache is pre-populated, but custom plugins may still need downloads

## Git Hash Versioning

When using git hashes for `portalVersion` or plugin versions, the following validation rules apply:

### Format Requirements

- **Minimum length**: 7 characters
- **Maximum length**: 40 characters
- **Character set**: Only lowercase hexadecimal characters (`0-9`, `a-f`)
- **Case sensitivity**: Must be lowercase (uppercase hashes will be rejected)

### Valid Examples

```yaml
# Short hash (7 characters)
portalVersion: 84c073f

# Medium hash (8 characters)
version: bfc88b3c

# Full hash (40 characters)
version: 84c073f181430439ca4dd539064480748cd654a0
```

### Invalid Examples

The following formats will be rejected by schema validation:

- Too short: `84c073` (6 characters)
- Too long: `84c073f181430439ca4dd539064480748cd654a01` (41 characters)
- Uppercase: `84C073F` (must be lowercase)
- Invalid characters: `g1b2c3d` (contains 'g' which is not a valid hex character)
- Mixed case: `A1b2C3d` (must be all lowercase)

### Best Practices

- Use exact git commit hashes from your repository
- Short hashes (7-8 characters) are sufficient for most use cases
- Full hashes (40 characters) provide complete uniqueness
- Always verify hashes are lowercase before using them in manifests

## Publishing the Image

Build and push to GHCR:

```bash
docker build -t ghcr.io/lumeweb/portal-builder:latest .
docker push ghcr.io/lumeweb/portal-builder:latest
```

## Local Development

Test changes locally:

```bash
# Build the builder image
docker build -t portal-builder .

# Test with example
docker build -f Dockerfile.example -t my-portal .

# Run the built portal
docker run -p 8080:8080 my-portal
```
