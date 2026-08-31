#!/bin/sh
set -e

# Portal Builder Entry Point
# Builds LumeWeb Portal with custom plugins using xportal

# Default values
PLUGIN_MANIFEST="${PLUGIN_MANIFEST:-portal-plugins.yaml}"
OUTPUT_DIR="${OUTPUT_DIR:-/dist}"
PORTAL_VERSION="${PORTAL_VERSION:-latest}"
SCHEMA_PATH="${SCHEMA_PATH:-/usr/local/share/portal-builder/schema.json}"

# Function to validate YAML against schema
validate_yaml() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        echo "Error: Plugin manifest not found at $PLUGIN_MANIFEST"
        exit 1
    fi

    if [ ! -f "$SCHEMA_PATH" ]; then
        echo "Warning: Schema not found at $SCHEMA_PATH, skipping validation"
        return 0
    fi

    # Check for check-jsonschema in common locations (uv installs to ~/.local/bin)
    if ! command -v check-jsonschema >/dev/null 2>&1; then
        if [ -f "$HOME/.local/bin/check-jsonschema" ]; then
            export PATH="$HOME/.local/bin:$PATH"
        else
            echo "Warning: check-jsonschema not installed, skipping validation"
            return 0
        fi
    fi

    echo "Validating $PLUGIN_MANIFEST against schema..."
    if ! check-jsonschema --schemafile "$SCHEMA_PATH" "$PLUGIN_MANIFEST"; then
        echo "Error: Validation failed for $PLUGIN_MANIFEST"
        exit 1
    fi
    echo "Validation passed"
}

# Function to parse portal version from YAML
parse_portal_version() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        return
    fi

    # Use yq to extract portalVersion if present
    if ! command -v yq >/dev/null 2>&1; then
        return
    fi

    yq eval '.portalVersion // ""' "$PLUGIN_MANIFEST" 2>/dev/null || true
}

# Function to parse plugins from YAML
parse_yaml_plugins() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        echo "Error: Plugin manifest not found at $PLUGIN_MANIFEST"
        exit 1
    fi

    # Use yq to extract plugins
    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: yq is required but not installed"
        exit 1
    fi

    # Parse plugins array and format as --with module@version
    yq eval '.plugins[] | "--with " + .module + "@" + .version' "$PLUGIN_MANIFEST" 2>/dev/null || true
}

# Function to parse replacements from YAML
parse_yaml_replacements() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        return
    fi

    # Use yq to extract replacements
    if ! command -v yq >/dev/null 2>&1; then
        return
    fi

    # Parse replacements array and format as --replace old=new
    yq eval '.replacements[] | "--replace " + .old + "=" + .new' "$PLUGIN_MANIFEST" 2>/dev/null || true
}

# Function to parse build tags from YAML
parse_yaml_build_tags() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        return
    fi

    # Use yq to extract buildTags
    if ! command -v yq >/dev/null 2>&1; then
        return
    fi

    # Join build tags into a space-separated list
    yq eval '.buildTags // [] | join(" ")' "$PLUGIN_MANIFEST" 2>/dev/null || true
}

# Function to run setup script from YAML manifest
run_setup() {
    if [ ! -f "$PLUGIN_MANIFEST" ]; then
        return
    fi

    if ! command -v yq >/dev/null 2>&1; then
        return
    fi

    setup_script=$(yq eval '.setup // ""' "$PLUGIN_MANIFEST" 2>/dev/null)
    if [ -n "$setup_script" ]; then
        echo "Running setup from manifest..."
        echo "$setup_script" | bash || { echo "Error: Setup script failed" >&2; exit 1; }
        echo "Setup complete"
    fi
}

# Function to parse plugins from ENV var (space or comma separated)
parse_env_plugins() {
    if [ -z "$PLUGINS" ]; then
        return
    fi

    # Convert comma-separated to space-separated
    plugins=$(echo "$PLUGINS" | tr ',' ' ')
    
    for plugin in $plugins; do
        # Check if plugin already includes @version
        if echo "$plugin" | grep -q '@'; then
            echo "--with $plugin"
        else
            echo "--with ${plugin}@latest"
        fi
    done
}

# Function to parse replacements from ENV var (comma separated, format: old=new)
parse_env_replacements() {
    if [ -z "$REPLACEMENTS" ]; then
        return
    fi

    # Convert comma-separated to newline-separated
    replacements=$(echo "$REPLACEMENTS" | tr ',' '\n')
    
    for replacement in $replacements; do
        echo "--replace $replacement"
    done
}

# Helper function to run xportal with common environment variables
run_xportal() {
    PORTAL_VERSION="$PORTAL_VERSION" \
    XPORTAL_GO_BUILD_FLAGS_EXTRA="$XPORTAL_GO_BUILD_FLAGS_EXTRA" \
    xportal build "$@"
}

# Main build function
build_portal() {
    # Check if portal version is specified in YAML (ENV takes precedence)
    yaml_portal_version=$(parse_portal_version)
    if [ -n "$yaml_portal_version" ] && [ "$PORTAL_VERSION" = "latest" ]; then
        PORTAL_VERSION="$yaml_portal_version"
    fi
    
    echo "Building Portal..."
    echo "Portal Version: $PORTAL_VERSION"
    
    # Collect plugin args from both sources
    plugin_args=""
    # Collect replacement args from both sources
    replacement_args=""
    
    # Validate YAML manifest if it exists
    if [ -f "$PLUGIN_MANIFEST" ]; then
        validate_yaml
        echo "Loading plugins from $PLUGIN_MANIFEST"
        yaml_plugins=$(parse_yaml_plugins)
        if [ -n "$yaml_plugins" ]; then
            plugin_args="$yaml_plugins"
            echo "Plugins from YAML:"
            echo "$yaml_plugins" | sed 's/--with /  - /'
        fi
        yaml_replacements=$(parse_yaml_replacements)
        if [ -n "$yaml_replacements" ]; then
            replacement_args="$yaml_replacements"
            echo "Replacements from YAML:"
            echo "$yaml_replacements" | sed 's/--replace /  - /'
        fi
    fi
    
    # Parse ENV var if set
    if [ -n "$PLUGINS" ]; then
        echo "Loading plugins from PLUGINS env var"
        env_plugins=$(parse_env_plugins)
        if [ -n "$env_plugins" ]; then
            if [ -n "$plugin_args" ]; then
                plugin_args="$plugin_args $env_plugins"
            else
                plugin_args="$env_plugins"
            fi
            echo "Plugins from ENV:"
            echo "$env_plugins" | sed 's/--with /  - /'
        fi
    fi

    # Parse REPLACEMENTS env var if set
    if [ -n "$REPLACEMENTS" ]; then
        echo "Loading replacements from REPLACEMENTS env var"
        env_replacements=$(parse_env_replacements)
        if [ -n "$env_replacements" ]; then
            if [ -n "$replacement_args" ]; then
                replacement_args="$replacement_args $env_replacements"
            else
                replacement_args="$env_replacements"
            fi
            echo "Replacements from ENV:"
            echo "$env_replacements" | sed 's/--replace /  - /'
        fi
    fi

    # Parse build tags from YAML and forward them to the go build via
    # XPORTAL_GO_BUILD_FLAGS_EXTRA, which preserves the default nobadger/trimpath flags.
    if [ -f "$PLUGIN_MANIFEST" ]; then
        build_tags=$(parse_yaml_build_tags)
        if [ -n "$build_tags" ]; then
            echo "Build tags: $build_tags"
            XPORTAL_GO_BUILD_FLAGS_EXTRA="-tags \"$build_tags\""
        fi
    fi
    
    # Run xportal with common environment variables
    # shellcheck disable=SC2086
    if [ "$OUTPUT_DIR" != "." ]; then
        run_xportal --output "$OUTPUT_DIR/portal" $plugin_args $replacement_args
    else
        run_xportal $plugin_args $replacement_args
    fi
    
    echo "Build complete: $OUTPUT_DIR/portal"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run setup from manifest (if present)
run_setup

# Retry only on transient sum.golang.org 500 errors with backoff aligned to propagation delay
log=$(mktemp)
trap 'rm -f "$log"' EXIT
for i in 1 2 3 4 5; do
    if [ "$i" != "1" ] && [ "$OUTPUT_DIR" != "." ]; then
        rm -rf "$OUTPUT_DIR/portal"
    fi
    if build_portal > "$log" 2>&1; then
        cat "$log"
        break
    fi
    if grep -qiE 'sum\.golang\.org/.*: 500 Internal Server Error|checksum database.*internal server error' "$log" >/dev/null 2>&1; then
        if [ "$i" = "5" ]; then
            cat "$log"
            echo "All build attempts failed"
            exit 1
        fi
        wait=$((120 * i))
        echo "Transient sum.golang.org error on attempt $i, retrying in ${wait}s..."
        sleep "$wait"
    else
        cat "$log"
        echo "Build attempt $i failed with a non-transient error"
        exit 1
    fi
done
