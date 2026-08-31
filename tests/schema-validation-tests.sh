#!/bin/bash
# Unit test script for schema validation
# Tests various valid and invalid manifest configurations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../schema.json"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Print test header
print_test() {
    echo -e "${YELLOW}Testing:${NC} $1"
    ((TESTS_RUN++)) || true
}

# Print success
print_success() {
    echo -e "${GREEN}✓ PASSED${NC}: $1"
    ((TESTS_PASSED++)) || true
}

# Print failure
print_failure() {
    echo -e "${RED}✗ FAILED${NC}: $1"
    ((TESTS_FAILED++)) || true
}

# Check if check-jsonschema is available
check_tool() {
    if ! command -v check-jsonschema &> /dev/null; then
        echo -e "${RED}Error: check-jsonschema not found${NC}"
        echo "Install with: pip install check-jsonschema"
        exit 1
    fi
}

# Test valid manifest
test_valid_manifest() {
    local name="$1"
    local content="$2"
    
    print_test "Valid: $name"
    
    local test_file="${TEMP_DIR}/${name}.yaml"
    echo "$content" > "$test_file"
    
    if check-jsonschema --schemafile "$SCHEMA_FILE" "$test_file" &> /dev/null; then
        print_success "$name"
        return 0
    else
        print_failure "$name"
        cat "$test_file"
        check-jsonschema --schemafile "$SCHEMA_FILE" "$test_file" 2>&1 || true
        return 1
    fi
}

# Test invalid manifest
test_invalid_manifest() {
    local name="$1"
    local content="$2"
    
    print_test "Invalid (should fail): $name"
    
    local test_file="${TEMP_DIR}/${name}.yaml"
    echo "$content" > "$test_file"
    
    if ! check-jsonschema --schemafile "$SCHEMA_FILE" "$test_file" &> /dev/null; then
        print_success "$name (correctly rejected)"
        return 0
    else
        print_failure "$name (should have been rejected)"
        cat "$test_file"
        return 1
    fi
}

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=========================================="
echo "Schema Validation Unit Tests"
echo "=========================================="
echo ""

check_tool

echo "--- Valid Manifests ---"

# Test semantic versions
test_valid_manifest "semantic version with v prefix" '{
  "portalVersion": "v1.0.0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "v1.2.3"}
  ]
}'

test_valid_manifest "semantic version without v prefix" '{
  "portalVersion": "1.0.0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "1.2.3"}
  ]
}'

test_valid_manifest "semantic version with prerelease" '{
  "portalVersion": "v2.0.0-beta.1",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "v2.0.0-alpha.1"}
  ]
}'

# Test special keywords
test_valid_manifest "latest version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ]
}'

test_valid_manifest "develop version" '{
  "portalVersion": "develop",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "develop"}
  ]
}'

# Test short git hashes (7 characters minimum)
test_valid_manifest "short git hash 7 chars" '{
  "portalVersion": "84c073f",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "bfc88b3"}
  ]
}'

test_valid_manifest "short git hash 8 chars" '{
  "portalVersion": "84c073f1",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "bfc88b3c"}
  ]
}'

# Test full git hashes (40 characters)
test_valid_manifest "full git hash" '{
  "portalVersion": "84c073f181430439ca4dd539064480748cd654a0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "bfc88b3c061bd7c29c03fd8bdba7a93af1e5dd1e"}
  ]
}'

# Test mixed versions
test_valid_manifest "mixed semantic and git hash" '{
  "portalVersion": "v1.0.0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073f"},
    {"module": "go.lumeweb.com/portal-plugin-dashboard", "version": "v2.0.0"}
  ]
}'

test_valid_manifest "portal git hash with plugin semantic" '{
  "portalVersion": "84c073f",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "v1.0.0"}
  ]
}'

# Test without portalVersion (optional field)
test_valid_manifest "no portalVersion" '{
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ]
}'

# Test multiple plugins with different version types
test_valid_manifest "multiple plugins mixed versions" '{
  "portalVersion": "v1.0.0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"},
    {"module": "go.lumeweb.com/portal-plugin-dashboard", "version": "develop"},
    {"module": "go.lumeweb.com/portal-plugin-auth", "version": "616e498"},
    {"module": "go.lumeweb.com/portal-plugin-storage", "version": "v2.0.0-beta.1"}
  ]
}'

# Test boundary git hash lengths
test_valid_manifest "git hash exactly 7 chars" '{
  "portalVersion": "84c073f",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073f"}
  ]
}'

test_valid_manifest "git hash exactly 40 chars" '{
  "portalVersion": "84c073f181430439ca4dd539064480748cd654a0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073f181430439ca4dd539064480748cd654a0"}
  ]
}'

# Test multiple plugins with git hash
test_valid_manifest "multiple plugins with git hashes" '{
  "portalVersion": "84c073f",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073f"},
    {"module": "go.lumeweb.com/portal-plugin-dashboard", "version": "bfc88b3"},
    {"module": "go.lumeweb.com/portal-plugin-storage", "version": "616e498"}
  ]
}'

# Test build tags
test_valid_manifest "single build tag" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": ["foobar"]
}'

test_valid_manifest "multiple build tags" '{
  "portalVersion": "develop",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": ["foo", "bar", "feature_x"]
}'

test_valid_manifest "empty buildTags array" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": []
}'

# Test excludes
test_valid_manifest "single exclude" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "v1.2.0"}
  ]
}'

test_valid_manifest "multiple excludes" '{
  "portalVersion": "develop",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "v1.2.0"},
    {"module": "go.lumeweb.com/baz/qux", "version": "v2.0.0-beta.1"},
    {"module": "github.com/abc/def", "version": "1.2.3"}
  ]
}'

test_valid_manifest "empty excludes array" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": []
}'

echo ""
echo "--- Invalid Manifests ---"

# Test invalid git hashes (too short)
test_invalid_manifest "git hash too short (6 chars)" '{
  "portalVersion": "84c073",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073"}
  ]
}'

test_invalid_manifest "git hash too short (5 chars)" '{
  "portalVersion": "84c07",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c07"}
  ]
}'

# Test invalid git hashes (too long)
test_invalid_manifest "git hash too long (41 chars)" '{
  "portalVersion": "84c073f181430439ca4dd539064480748cd654a01",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84c073f181430439ca4dd539064480748cd654a01"}
  ]
}'

# Test invalid characters in git hash
test_invalid_manifest "git hash with invalid chars" '{
  "portalVersion": "g1b2c3d",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "g1b2c3d"}
  ]
}'

test_invalid_manifest "git hash with uppercase" '{
  "portalVersion": "84C073F",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "84C073F"}
  ]
}'

# Test invalid semantic versions
test_invalid_manifest "invalid semantic version" '{
  "portalVersion": "1.0",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "1.0"}
  ]
}'

test_invalid_manifest "invalid version string" '{
  "portalVersion": "invalid",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "invalid"}
  ]
}'

# Test missing required fields
test_invalid_manifest "missing module" '{
  "portalVersion": "latest",
  "plugins": [
    {"version": "latest"}
  ]
}'

test_invalid_manifest "missing version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core"}
  ]
}'

test_invalid_manifest "missing plugins array" '{
  "portalVersion": "latest"
}'

# Test invalid module names
test_invalid_manifest "invalid module name with space" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal plugin", "version": "latest"}
  ]
}'

# Test invalid build tags
test_invalid_manifest "build tag with space" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": ["bad tag"]
}'

test_invalid_manifest "build tag not a string" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": [123]
}'

test_invalid_manifest "buildTags not an array" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "buildTags": "foo"
}'

# Test invalid excludes
test_invalid_manifest "exclude missing version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar"}
  ]
}'

test_invalid_manifest "exclude missing module" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"version": "v1.2.0"}
  ]
}'

test_invalid_manifest "exclude extra property" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "v1.2.0", "extra": "x"}
  ]
}'

test_invalid_manifest "exclude module with space" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo bar", "version": "v1.2.0"}
  ]
}'

test_invalid_manifest "exclude invalid version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "not-a-version"}
  ]
}'

test_invalid_manifest "excludes not an array" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": "github.com/foo/bar@v1.2.0"
}'

test_invalid_manifest "exclude git hash version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "a1b2c3d"}
  ]
}'

test_invalid_manifest "exclude non-semver version" '{
  "portalVersion": "latest",
  "plugins": [
    {"module": "go.lumeweb.com/portal-plugin-core", "version": "latest"}
  ],
  "excludes": [
    {"module": "github.com/foo/bar", "version": "latest"}
  ]
}'

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
