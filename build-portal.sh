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
    
    # Build xportal command with portal version
    if [ -n "$plugin_args" ]; then
        echo "Building with plugins..."
        # shellcheck disable=SC2086
        if [ "$OUTPUT_DIR" != "." ]; then
            PORTAL_VERSION="$PORTAL_VERSION" xportal build --output "$OUTPUT_DIR/portal" $plugin_args
        else
            PORTAL_VERSION="$PORTAL_VERSION" xportal build $plugin_args
        fi
    else
        echo "Building without plugins..."
        if [ "$OUTPUT_DIR" != "." ]; then
            PORTAL_VERSION="$PORTAL_VERSION" xportal build --output "$OUTPUT_DIR/portal"
        else
            PORTAL_VERSION="$PORTAL_VERSION" xportal build
        fi
    fi
    
    echo "Build complete: $OUTPUT_DIR/portal"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run build
build_portal
