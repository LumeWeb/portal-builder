# Portal Builder Tests

This directory contains test scripts and test data for the portal-builder.

## Schema Validation Tests

The `schema-validation-tests.sh` script validates the schema with various valid and invalid manifest configurations.

### Running the Tests

```bash
# Make the test script executable (first time only)
chmod +x schema-validation-tests.sh

# Run the tests
./schema-validation-tests.sh
```

### Test Coverage

The test suite validates:
- Valid semantic versions (with/without `v` prefix, prerelease tags)
- Special keywords (`latest`, `develop`)
- Git hashes (short: 7-40 chars, full: 40 chars)
- Mixed version types
- Invalid inputs (too short/long hashes, invalid characters, missing fields)

### Requirements

The tests require `check-jsonschema` to be installed:

```bash
pip install check-jsonschema
```
