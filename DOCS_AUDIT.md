# Mintlify Docs Audit: Errors & Production-Grade Improvements

This document summarizes errors found and recommended improvements for production-grade documentation.

---

## ✅ Implemented Fixes (Latest Pass)

All of the following were applied:

- **docs.json**: Added `delete-memory` to Memories group; added `core-concepts` and `continuity-assurance` to Get Started.
- **core-concepts.mdx**: Renamed title to "Memory Model" to avoid duplicate with concepts; fixed CardGroup links to `/essentials/memories`, `/api-reference/endpoint/add-knowledge-memories`, `/api-reference/endpoint/add-hive-memories`.
- **essentials/memories.mdx**: Replaced broken links to Generate/Retrieve User Memory and Verify Processing with current endpoints (Add Memory, Smart/Keyword recall) and copy.
- **api-reference/delete-memory.mdx**: OpenAPI path and curl use `delete_memory`; Note/Info updated to reference Add Memory only (no archived List/Generate).
- **api-reference/endpoint/add-memories.mdx**: Verify Processing section updated with inline note and example curl kept for ingestion flows.
- **essentials/context-graph.mdx**: Links updated to add-knowledge-memories, smart, keyword.
- **api-reference/endpoint/add-knowledge-memories.mdx**: Removed broken file-formats link; clarified supported formats in copy; fixed Warning wording.
- **continuity-assurance.mdx**: support@useCortex.com → founders@hydradb.com.
- **quickstart.mdx**: Step 0 (create tenant) added; paths updated to `/tenants/create`, `/ingestion/upload-document`, `/ingestion/verify-processing`; Optional Extensions use `/delete/delete-sources`, `/list/list-sources` and link to Smart/Keyword recall.

---

## ✅ Errors Fixed in Earlier Pass

| Location | Issue | Fix |
|----------|--------|-----|
| `api-reference/endpoint/add-memories.mdx` | Typo: "memmory" | Changed to "memory" |
| `essentials/metadata.mdx` | Typo: "upto" | Changed to "up to" |
| `api-reference/delete-memory.mdx` | Curl: missing backslash after first `-H`, inconsistent `--header` | Used `-H` with proper line continuation |

---

## 🔴 Errors & Inconsistencies (Require Your Decision)

### 1. Quickstart uses outdated / wrong API paths

**File:** `quickstart.mdx`

Quickstart documents endpoints that don’t match the current API reference or OpenAPI:

| Quickstart says | OpenAPI / current API |
|-----------------|------------------------|
| `POST /upload/upload_document` | `POST /ingestion/upload-document` |
| `POST /upload/scrape_webpage` | Not in current OpenAPI (in archive) |
| `POST /upload/verify_processing` | `POST /ingestion/verify-processing` |
| Legacy answer-generation search path | Use `POST /recall/full_recall` for retrieval, then generate answers in the app layer |
| `POST /upload/batch_upload` | In archive only |
| `/delete_source`, `/list/sources` | Current API uses `/delete/delete-sources`, `/list/list-sources` |

**Recommendation:** Rewrite Quickstart to use current tenant + ingestion + recall flow (e.g. create tenant → add memories / add embeddings → smart or keyword recall) and align all paths with `api-reference/openapi.json`.

---

### 2. Broken or outdated internal links

| Source | Link | Problem |
|--------|------|---------|
| `essentials/memories.mdx` | Generate User Memory | Page is in `archive/`; not in nav → 404 or hidden |
| `essentials/memories.mdx` | Retrieve User Memory | Same (archived) |
| `essentials/memories.mdx` | [Delete Memory](/api-reference/endpoint/delete-memory) | Delete Memory lives at `/api-reference/delete-memory` (no `endpoint/`) |
| `essentials/memories.mdx` | [Verify Processing](/api-reference/endpoint/verify-processing) | Archived |
| `api-reference/endpoint/add-memories.mdx` | [Verify Processing](/api-reference/endpoint/verify-processing) | Archived |
| `api-reference/delete-memory.mdx` | List User Memories | Archived |
| `api-reference/delete-memory.mdx` | Add User Memory | No such slug; current is `add-memories` |
| `essentials/context-graph.mdx` | Knowledge Ingestion | No current `upload-document` in API reference (in archive) |
| `essentials/context-graph.mdx` | Legacy search and answer-generation links | Current endpoint list uses recall pages instead |
| `api-reference/endpoint/add-knowledge-memories.mdx` | Supported File Formats | No `essentials/file-formats` page in repo |
| `archive/.../upload-document.mdx` | Supported File Formats | Same missing page |

**Recommendation:**  
- Point all “current” docs to existing, in-nav pages only (e.g. Delete Memory → `/api-reference/delete-memory`, Add Memory → `/api-reference/endpoint/add-memories`).  
- For archived endpoints (Generate/Retrieve User Memory, Verify Processing, List User Memories), either restore and add to nav or replace links with a short “legacy/archived APIs” note and point to current alternatives.  
- Add `/essentials/file-formats` or remove/rewrite references to it.

---

### 3. Duplicate page titles and orphan pages

| File | Title in frontmatter | In `docs.json` nav? |
|------|---------------------|----------------------|
| `concepts.mdx` | "Core Concepts" | Yes (Get Started) |
| `core-concepts.mdx` | "Core Concepts" | No |

So two pages share the same title and `core-concepts.mdx` is an orphan. It also uses SDK-style examples (e.g. `hydradb.userMemory.store`) that may not match the current REST-first API.

**Recommendation:** Either merge content into one “Core Concepts” page and remove the other, or rename and add `core-concepts` to nav with a distinct title (e.g. “Memory model (detailed)”).

---

### 4. Orphan pages (not in navigation)

- `core-concepts.mdx` – not in `docs.json`
- `continuity-assurance.mdx` – not in `docs.json`
- `api-reference/delete-memory.mdx` – not in `docs.json` (Memories group only has add-memories, add-knowledge-memories, add-hive-memories)

**Recommendation:** Add these to `docs.json` under the right groups, or move to an “Archive” section so they’re still reachable but clearly secondary.

---

### 5. Delete Memory: path and OpenAPI alignment

- **OpenAPI:** `DELETE /memories/delete_memory` (underscore).
- **delete-memory.mdx:** `openapi: 'DELETE /memories/delete-memory'` (hyphen); curl in doc uses `delete-memory`.

**Recommendation:** Confirm the live path with the backend (hyphen vs underscore), then make OpenAPI, frontmatter, and curl examples consistent.

---

### 6. Inconsistent contact / support emails

- Index: `founders@hydradb.com`
- Nav: `founders@hydradb.com` (Support)
- continuity-assurance: `support@useCortex.com` (different domain and casing)

**Recommendation:** Standardize on one support/contact address and domain (e.g. `hydradb.com`) across all docs and nav.

---

### 7. create-tenant.mdx: curl example missing auth

The “API Request” curl in `api-reference/endpoint/create-tenant.mdx` does not include an `Authorization: Bearer <token>` header, while the text says all endpoints require it.

**Recommendation:** Add `-H 'Authorization: Bearer <token>'` to the curl example.

---

## 🟡 Production-grade improvements

### Navigation and IA

- Add **delete-memory** to the API Reference → Memories group so it’s discoverable.
- Add **continuity-assurance** (e.g. under “Company” or “Policies”) if you want it public.
- Resolve **concepts** vs **core-concepts**: one canonical “Core Concepts” and no duplicate titles.
- Consider a **“Legacy / archived APIs”** section that links to archive endpoints and points to current equivalents.

### Quickstart and onboarding

- Align Quickstart with **current** API: tenant creation → memories/embeddings → recall (Smart/Keyword).
- Optionally add a **“Before you start”** (API key, base URL, tool (e.g. curl/Postman)) and a **“Next steps”** (link to API reference and essentials).

### API reference consistency

- Ensure every documented path matches **one** source of truth (e.g. `openapi.json`); fix hyphen vs underscore and method where needed.
- Add **Authorization** to every curl example that calls a protected endpoint.
- Optionally add **rate limits** and **error code** sections where relevant (and link to `error-responses.mdx`).

### Cross-links and maintenance

- Replace all links to archived-only endpoints with either current endpoints or an explicit “archived” note.
- Fix **Delete Memory** link to `/api-reference/delete-memory` (no `endpoint/`).
- Create **Supported File Formats** at `/essentials/file-formats` or remove references.

### Content and UX

- **core-concepts.mdx**: Align code samples with the current API (REST + SDK if both are supported).
- **SDK docs** (`api-reference/sdks.mdx`): Update method examples (e.g. `client.upload.uploadText()` and `POST /upload/upload_text`) to match current OpenAPI and product naming.
- Add **version or “Last updated”** in frontmatter or footer for high-traffic pages.
- Consider **search** (Mintlify search) and a **short “Overview”** at the top of long pages.

### Operational

- Add a **link check** (e.g. in CI) for internal and external links.
- Optionally add **redirects** for old URLs (e.g. `/api-reference/endpoint/delete-memory` → `/api-reference/delete-memory`) in Mintlify config.

---

## Summary

| Category | Count |
|----------|--------|
| Fixed in this pass | 3 (typos + curl) |
| Broken/outdated links | 10+ |
| Orphan / duplicate title pages | 4 |
| Path/OpenAPI/contact inconsistencies | 4 |
| Production improvements | 6 areas |

Recommended order: (1) fix Quickstart and broken links, (2) fix nav and orphan pages, (3) align paths and OpenAPI, (4) then apply the rest of the production-grade improvements.
