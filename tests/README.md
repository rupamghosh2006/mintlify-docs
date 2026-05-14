# HydraDB Test Suite

Three test runners - one per protocol. Each creates its own uniquely-named tenant, runs every documented endpoint/method, and writes a log file. Run them in order.

## Prerequisites

```bash
# Python SDK
pip install hydradb-sdk

# TypeScript SDK
npm install @hydradb/sdk ts-node typescript @types/node
```

## Run all three

```bash
export HYDRA_DB_API_KEY="sk_live_..."

# 1. cURL (REST layer - most comprehensive)
bash tests/test_curl.sh

# 2. Python SDK
python3 tests/test_python.py

# 3. TypeScript SDK
npx ts-node tests/test_typescript.ts
```

## Output files

| File | Contents |
|---|---|
| `tests/results_curl.log` | cURL results - every HTTP status code and response body |
| `tests/results_python.log` | Python SDK results - method return values and errors |
| `tests/results_typescript.log` | TypeScript SDK results - method return values and errors |

## What's tested

### cURL
- All 17 REST endpoints
- Happy paths + edge cases (duplicate tenant, missing fields, invalid IDs, no auth, wrong auth)
- Polling patterns (infra status, verify processing)

### Python & TypeScript SDKs
- Every method in the PyPI/npm SDK method reference table
- All parameter variants (`mode`, `operator`, `alpha`, `recency_bias`, `graph_context`, etc.)
- Error cases (empty arrays, invalid IDs, re-deletion)
- Method name correctness (`client.upload.add_memory`, `client.upload.delete_memory`, etc.)

## Notes

- Rate limits (429) are logged as ⚠️ warnings, not failures
- Each run creates a fresh `hydradb-{qa,py,ts}-{timestamp}` tenant and deletes it at the end
- If a test early in the flow fails (e.g. tenant creation), downstream tests that depend on it are skipped with a warning
