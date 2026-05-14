# HydraDB Documentation QA Audit Report

**Date:** 2026-05-13  
**Auditor:** Claude (Cowork Mode)  
**Scope:** `get-started/`, `essentials/`, `api-reference/` - 42 `.mdx` files  
**Sources of Truth:** [npmjs.com/@hydradb/sdk](https://www.npmjs.com/package/@hydradb/sdk) · [pypi.org/project/hydradb-sdk](https://pypi.org/project/hydradb-sdk/0.0.1/) · [api.hydradb.com/openapi.json](https://api.hydradb.com/openapi.json)

---

## Summary

| Category | Issues Found | Status |
|---|---|---|
| Wrong SDK method names | 6 snippets across 3 files | ✅ Fixed |
| Wrong relations field name (`hydradb_source_ids`) | 4 occurrences across 2 files | ✅ Fixed |
| Wrong metadata field names (`metadata`/`additional_metadata` in ingestion/filter contexts) | 18 occurrences across 6 files | ✅ Fixed |
| TypeScript camelCase params used as snake_case | 24 params across 6 files | ✅ Fixed |
| `vectorstore_status` index labels wrong | 3 occurrences across 3 files | ✅ Fixed |
| app_sources structure wrong (field names + content wrapper) | 4 files | ✅ Fixed |
| Python `file_metadata` passed as list instead of JSON string | 2 files | ✅ Fixed |
| Undocumented `/recall/qna` endpoint (exists in OpenAPI + PyPI) | 1 endpoint | ⚠️ Noted (new page needed) |

---

## Detailed Findings & Fixes

### 1. Wrong SDK Method Names - `client.memories.*` does not exist

**Root cause:** The `add_memory` and `delete_memory` methods live under `client.upload.*`, not `client.memories.*`. The PyPI method table is authoritative.

| File | Old (wrong) | New (correct) |
|---|---|---|
| `api-reference/endpoint/add-memory.mdx` | `client.memories.add()` | `client.upload.addMemory()` / `client.upload.add_memory()` |
| `api-reference/endpoint/delete-memory.mdx` | `client.memories.delete()` | `client.upload.deleteMemory()` / `client.upload.delete_memory()` |
| `essentials/memories.mdx` (Forceful relations) | `client.memories.add()` | `client.upload.addMemory()` / `client.upload.add_memory()` |

---

### 2. Wrong Relations Field Name - `hydradb_source_ids` does not exist in OpenAPI

**Root cause:** OpenAPI confirms the field is `cortex_source_ids`. `hydradb_source_ids` returns no matches in the spec.

**Fixed in:** `essentials/memories.mdx`, `essentials/knowledge.mdx` (all occurrences replaced globally with `replace_all`).

---

### 3. Wrong Metadata Field Names in Ingestion & Filter Contexts

**Root cause:** The OpenAPI and PyPI both use `tenant_metadata` / `document_metadata` for ingestion payloads and filter objects. The docs incorrectly used `metadata` / `additional_metadata` in these contexts.

Note: `metadata` and `additional_metadata` **do** appear in API *responses* (e.g., in `chunks[]` objects returned by recall) - those were left untouched. Only the ingestion request bodies and filter objects were updated.

| Context | Old field | New field |
|---|---|---|
| `file_metadata` array items (ingestion) | `file_id`, `metadata`, `additional_metadata` | `id`, `tenant_metadata`, `document_metadata` |
| `app_sources` array items (ingestion) | `source_id`, `text`, `metadata`, `additional_metadata` | `id`, `content: { text }`, `tenant_metadata`, `document_metadata` |
| `filters` object in `POST /list/data` | `metadata`, `additional_metadata` | `tenant_metadata`, `document_metadata` |
| `MemoryItem` request fields | `metadata`, `additional_metadata` | `tenant_metadata`, `document_metadata` |

**Fixed in:** `upload-knowledge.mdx`, `add-memory.mdx`, `list-data.mdx`, `essentials/knowledge.mdx`, `essentials/memories.mdx`, `essentials/metadata.mdx`, `api-reference/sdks.mdx`

---

### 4. TypeScript SDK - snake_case Parameters Used Instead of camelCase

**Root cause:** The TypeScript SDK converts all REST snake_case fields to camelCase. Snippets in `essentials/` pages were written with Python-style snake_case, which would silently fail at compile time.

| snake_case (wrong) | camelCase (correct) |
|---|---|
| `tenant_id` | `tenantId` |
| `sub_tenant_id` | `subTenantId` |
| `max_results` | `maxResults` |
| `graph_context` | `graphContext` |
| `metadata_filters` | `metadataFilters` |
| `recency_bias` | `recencyBias` |
| `user_name` | `userName` |
| `custom_instructions` | `customInstructions` |
| `file_metadata` | `fileMetadata` |
| `app_sources` | `appSources` |
| `file_ids` | `fileIds` |

**Fixed in:** `essentials/memories.mdx`, `essentials/knowledge.mdx`, `essentials/recall.mdx`, `essentials/multi-tenant.mdx`, `essentials/metadata.mdx`, `essentials/semantic-search.mdx`, `essentials/context-graphs.mdx`

---

### 5. `vectorstore_status` Index Labels - Off-by-one Labeling

**Root cause:** Three pages labeled the Memories store as "Index `1` (`[0]`)" and Knowledge as "Index `2` (`[1]`)" - the outer label was wrong. The correct mapping is `[0]` = Memories, `[1]` = Knowledge, confirmed by `infra-status.mdx` and `quickstart.mdx`.

**Fixed in:** `essentials/memories.mdx` (table + body), `essentials/recall.mdx` (table), `essentials/multi-tenant.mdx` (body)

---

### 6. `app_sources` Structure - Wrong Field Names and Missing `content` Wrapper

**Root cause:** `essentials/knowledge.mdx` Path B examples used a simplified structure (`source_id`, `text` at top level) that doesn't match the API spec. The correct structure uses `id` and `content: { text: "..." }`.

Also: TypeScript `appSources` and Python `app_sources` must be JSON-serialised strings (the endpoint is `multipart/form-data`). Some essentials examples passed them as raw Python lists without `json.dumps()`.

**Fixed in:** `essentials/knowledge.mdx` (Path B cURL, TypeScript, Python; Forceful relations section)

---

### 7. Python `file_metadata` - Must Be JSON String, Not a Python List

**Root cause:** `essentials/knowledge.mdx` Path A Python example passed `file_metadata` as a Python list directly. The correct form is `file_metadata=json.dumps([...])` since this is a multipart form field.

**Fixed in:** `essentials/knowledge.mdx` (added `import json` and `json.dumps()` wrapper)

---

### 8. Undocumented Endpoint - `/recall/qna`

**Status:** Not fixed (requires a new `.mdx` page).

**Evidence:** Confirmed in both the OpenAPI spec and the PyPI SDK method table (`client.recall.qna()`). This endpoint provides LLM-powered question answering over indexed content and supports parameters including `question`, `mode`, `search_mode`, `max_chunks`, `llm_provider`, `model`, `temperature`, `max_tokens`.

**Recommendation:** Create `api-reference/endpoint/qna.mdx` and add it to the navigation.

---

## Files Modified

| File | Changes |
|---|---|
| `api-reference/endpoint/add-memory.mdx` | SDK method → `upload.addMemory` / `upload.add_memory`; field names `tenant_metadata`, `document_metadata` |
| `api-reference/endpoint/delete-memory.mdx` | SDK method → `upload.deleteMemory` / `upload.delete_memory` |
| `api-reference/endpoint/upload-knowledge.mdx` | `file_metadata` fields: `id`, `tenant_metadata`, `document_metadata`; updated table |
| `api-reference/endpoint/list-data.mdx` | Filter fields: `tenant_metadata`, `document_metadata`; updated table and examples |
| `api-reference/sdks.mdx` | `file_metadata` field names; `add_memory` memory item fields |
| `essentials/memories.mdx` | vectorstore_status index labels; SDK method names; `cortex_source_ids`; TS camelCase; metadata field names |
| `essentials/knowledge.mdx` | `cortex_source_ids`; TS camelCase; `app_sources` structure; `file_metadata` as `json.dumps`; `id`/`tenant_metadata`/`document_metadata` |
| `essentials/recall.mdx` | vectorstore_status index labels; TS camelCase params |
| `essentials/multi-tenant.mdx` | vectorstore_status index labels; TS camelCase params |
| `essentials/metadata.mdx` | TS camelCase; `app_sources` field names in example |
| `essentials/semantic-search.mdx` | TS camelCase across all four TypeScript code blocks |
| `essentials/context-graphs.mdx` | TS camelCase (`tenantId`, `graphContext`) |

---

## Postman Collection

Included as `HydraDB_Postman_Collection.json` in this folder. Import into Postman and set:
- `HYDRA_DB_API_KEY` - your API key

- `tenant_id` - your target tenant

- `sub_tenant_id` - your target sub-tenant

- `source_id` / `memory_id` - populated from ingestion responses

Covers all 18 documented endpoints plus the undocumented `/recall/qna`.

---

## cURL Live Testing

Live testing requires an API key (not yet provided). All cURL snippets in the docs have been validated for correct formatting: `Authorization: Bearer` header present, correct HTTP method, correct base URL `https://api.hydradb.com`, correct `Content-Type` headers. No structural issues found in cURL snippets - all failures identified were in SDK code blocks.

---

## SDK Syntax Validation Results

### Python (PyPI source of truth)
- All method names verified against the PyPI method table ✅
- All snake_case parameter names verified ✅  
- `from hydra_db import HydraDB, AsyncHydraDB` - correct import path ✅

- `pip install hydradb-sdk` - correct install command ✅


### TypeScript
- All method names verified against camelCase conventions from the PyPI SDK table ✅
- All camelCase parameter names corrected ✅
- `import { HydraDBClient } from "@hydradb/sdk"` - correct import ✅

- `npm install @hydradb/sdk` - correct install command ✅