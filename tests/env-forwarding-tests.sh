#!/bin/bash
# Regression tests: manifest goproxy/gosumdb values must reach xportal
# intact (no word splitting, no glob expansion, no shell interpretation)
# and container-environment values must take precedence over the manifest.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ENTRY="${SCRIPT_DIR}/../build-portal.sh"
TEMP_DIR=$(mktemp -d)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_test() {
    echo -e "${YELLOW}Testing:${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

print_success() {
    echo -e "${GREEN}✓ PASSED${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_failure() {
    echo -e "${RED}✗ FAILED${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Stub xportal: records the values it receives to the report file.
# The report uses explicit delimiters so exact values can be asserted.
make_stub_xportal() {
    local report="$1"
    mkdir -p "${TEMP_DIR}/bin"
    cat > "${TEMP_DIR}/bin/xportal" <<EOF
#!/bin/sh
{
    echo "GOPROXY<<[\${GOPROXY}]>>"
    echo "GOSUMDB<<[\${GOSUMDB}]>>"
} > "$report"
exit 0
EOF
    chmod +x "${TEMP_DIR}/bin/xportal"
}

write_manifest() {
    local goproxy="$1"
    local gosumdb="$2"
    cat > "${TEMP_DIR}/portal-plugins.yaml" <<EOF
plugins:
  - module: go.lumeweb.com/portal-plugin-core
    version: latest
goproxy: "$goproxy"
gosumdb: "$gosumdb"
EOF
}

run_build() {
    (
        cd "$TEMP_DIR"
        export PATH="${TEMP_DIR}/bin:${PATH}"
        export OUTPUT_DIR="${TEMP_DIR}/dist"
        export PLUGIN_MANIFEST="${TEMP_DIR}/portal-plugins.yaml"
        sh "${BUILDER_ENTRY}" >/dev/null 2>&1
    )
}

get_reported() {
    sed -n "s/.*$1<<\[\(.*\)\]>>.*/\1/p" "${TEMP_DIR}/xportal-report.txt" | tail -1
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=========================================="
echo "Env Forwarding Regression Tests"
echo "=========================================="
echo ""

# --- Test 1: whitespace and glob metacharacters survive intact ---
# A broken forwarding path would split on the space and expand the glob
# (`*` would try to match the manifest directory), corrupting the value
# that reaches the go toolchain.
print_test "manifest goproxy/gosumdb with spaces and glob chars reach xportal intact"
make_stub_xportal "${TEMP_DIR}/xportal-report.txt"
rm -f "${TEMP_DIR}/xportal-report.txt"
write_manifest "off https://proxy/*evil,direct" "sum.golang.org+033de0ae+Ac4 (custom)"
if run_build; then
    reported_proxy=$(get_reported GOPROXY)
    reported_sumdb=$(get_reported GOSUMDB)
    if [ "$reported_proxy" = "off https://proxy/*evil,direct" ] && \
       [ "$reported_sumdb" = "sum.golang.org+033de0ae+Ac4 (custom)" ]; then
        print_success "manifest values passed through intact"
    else
        print_failure "values corrupted in transit"
        echo "  expected GOPROXY: off https://proxy/*evil,direct"
        echo "  actual GOPROXY:   $reported_proxy"
        echo "  expected GOSUMDB: sum.golang.org+033de0ae+Ac4 (custom)"
        echo "  actual GOSUMDB:   $reported_sumdb"
    fi
else
    print_failure "build_portal failed before running xportal"
fi

# --- Test 2: container environment takes precedence over manifest ---
print_test "container GOPROXY/GOSUMDB override manifest values"
make_stub_xportal "${TEMP_DIR}/xportal-report.txt"
rm -f "${TEMP_DIR}/xportal-report.txt"
write_manifest "https://proxy.go.lumeweb.com,direct" "off"
if (cd "$TEMP_DIR" && PATH="${TEMP_DIR}/bin:${PATH}" OUTPUT_DIR="${TEMP_DIR}/dist" \
    PLUGIN_MANIFEST="${TEMP_DIR}/portal-plugins.yaml" \
    GOPROXY="direct" GOSUMDB="sum.golang.org" sh "${BUILDER_ENTRY}" >/dev/null 2>&1); then
    reported_proxy=$(get_reported GOPROXY)
    reported_sumdb=$(get_reported GOSUMDB)
    if [ "$reported_proxy" = "direct" ] && [ "$reported_sumdb" = "sum.golang.org" ]; then
        print_success "container environment takes precedence"
    else
        print_failure "manifest overrode container environment"
        echo "  expected GOPROXY: direct"
        echo "  actual GOPROXY:   $reported_proxy"
        echo "  expected GOSUMDB: sum.golang.org"
        echo "  actual GOSUMDB:   $reported_sumdb"
    fi
else
    print_failure "build_portal failed before running xportal"
fi

# --- Test 3: no manifest value means no override of container env ---
print_test "empty manifest fields leave container environment untouched"
make_stub_xportal "${TEMP_DIR}/xportal-report.txt"
rm -f "${TEMP_DIR}/xportal-report.txt"
cat > "${TEMP_DIR}/portal-plugins.yaml" <<'EOF'
plugins:
  - module: go.lumeweb.com/portal-plugin-core
    version: latest
EOF
if (cd "$TEMP_DIR" && PATH="${TEMP_DIR}/bin:${PATH}" OUTPUT_DIR="${TEMP_DIR}/dist" \
    PLUGIN_MANIFEST="${TEMP_DIR}/portal-plugins.yaml" \
    GOPROXY="direct" sh "${BUILDER_ENTRY}" >/dev/null 2>&1); then
    reported_proxy=$(get_reported GOPROXY)
    if [ "$reported_proxy" = "direct" ]; then
        print_success "container env not clobbered by empty manifest fields"
    else
        print_failure "container env was modified: GOPROXY=$reported_proxy"
    fi
else
    print_failure "build_portal failed before running xportal"
fi

echo ""
echo "--- Summary ---"
echo "Tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
