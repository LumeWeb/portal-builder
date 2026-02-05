# Testing Portal Builder

This guide demonstrates how to test the portal-builder base image.

## Unit Tests

### Schema Validation Tests

Run the schema validation unit tests:

```bash
cd tests
chmod +x schema-validation-tests.sh
./schema-validation-tests.sh
```

The test script validates:
- Valid semantic versions (with/without `v` prefix, prerelease tags)
- Special keywords (`latest`, `develop`)
- Git hashes (short: 7-40 chars, full: 40 chars)
- Mixed version types
- Invalid inputs (too short/long hashes, invalid characters, missing fields)

See `tests/README.md` for more details.

## Build the Portal Builder Base Image

```bash
docker build -t portal-builder .
```

## Test with Custom Dockerfile

Create your own Dockerfile to build a custom portal:

```dockerfile
FROM ghcr.io/lumeweb/portal-builder:latest AS builder

# Copy your plugin manifest
COPY portal-plugins.yaml .

# Optional: Set portal version
ARG PORTAL_VERSION=develop
ENV PORTAL_VERSION=${PORTAL_VERSION}

# Build the portal
RUN build-portal

# Create runtime image
FROM alpine:latest
COPY --from=builder /dist/portal /usr/local/bin/portal
CMD ["portal"]
```

Build your custom portal:

```bash
docker build -t my-portal .
```

Run the built portal:

```bash
docker run -p 8080:8080 my-portal
```

## Test with Git Hash

```bash
# Build with short hash
docker build --build-arg PORTAL_VERSION=84c073f -t my-portal-hash .
```

## Validation Testing

### Validate Manifest Locally

```bash
pip install check-jsonschema
check-jsonschema --schemafile schema.json portal-plugins.yaml
```

### Validate Example Manifests

```bash
# Validate git hash example
check-jsonschema --schemafile schema.json tests/portal-plugins.git-hash.example.yaml
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

## CI Testing

The project includes GitHub Actions workflows that run automatically on push and pull requests:

- `.github/workflows/ci.yml` - Runs schema validation tests, JSON schema validation, and ShellCheck

See `.github/workflows/ci.yml` for details.
