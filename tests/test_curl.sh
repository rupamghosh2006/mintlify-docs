#!/usr/bin/env bash
# ============================================================
# HydraDB cURL Test Suite
# Tests every documented REST endpoint against the live API.
# Usage:  HYDRADB_API_KEY="sk_live_..." bash tests/test_curl.sh
# Output: tests/results_curl.log
# ============================================================

set -euo pipefail

BASE="https://api.hydradb.com"
KEY="${HYDRADB_API_KEY:?Set HYDRADB_API_KEY before running}"
TENANT="hydradb-qa-$(date +%s)"   # unique per run
SUB="qa_user_001"
LOG="tests/results_curl.log"
PASS=0; FAIL=0; WARN=0

mkdir -p tests
> "$LOG"

# ── helpers ────────────────────────────────────────────────
ts()   { date '+%H:%M:%S'; }
hdr()  { echo; echo "━━━ $* ━━━" | tee -a "$LOG"; }
ok()   { echo "  ✅ PASS  $*" | tee -a "$LOG"; ((PASS++)); }
fail() { echo "  ❌ FAIL  $*" | tee -a "$LOG"; ((FAIL++)); }
warn() { echo "  ⚠️  WARN  $*" | tee -a "$LOG"; ((WARN++)); }

run() {
  # run <label> <expected_status> <curl_args...>
  local label="$1" expected="$2"; shift 2
  local resp http_code body
  resp=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -H "Authorization: Bearer $KEY" "$@" 2>&1)
  http_code=$(echo "$resp" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
  body=$(echo "$resp" | sed '/HTTP_STATUS:/d')

  echo "  → $label (expected $expected, got $http_code)" | tee -a "$LOG"
  echo "    $body" | tee -a "$LOG"

  if [[ "$http_code" == "$expected" ]]; then
    ok "$label"
  elif [[ "$http_code" == "429" ]]; then
    warn "$label — rate limited (429); sleeping 5s"
    sleep 5
  else
    fail "$label — expected HTTP $expected, got $http_code"
    echo "    BODY: $body" | tee -a "$LOG"
  fi
}

sleep_if_needed() { sleep "${1:-1}"; }

# ════════════════════════════════════════════════════════════
echo "HydraDB cURL Test Suite — $(ts)" | tee "$LOG"
echo "Tenant: $TENANT" | tee -a "$LOG"
echo "Base:   $BASE" | tee -a "$LOG"

# ── 1. List tenant IDs ──────────────────────────────────────
hdr "1. GET /tenants/tenant_ids"
run "List tenant IDs" "200" \
  "$BASE/tenants/tenant_ids"

# ── 2. Create tenant ────────────────────────────────────────
hdr "2. POST /tenants/create"
run "Create tenant" "200" \
  -X POST "$BASE/tenants/create" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"tenant_metadata_schema\": [
      { \"name\": \"category\", \"data_type\": \"VARCHAR\", \"max_length\": 256, \"enable_match\": true }
    ]
  }"

# ── 3. Re-create same tenant → expect 409 ──────────────────
hdr "3. POST /tenants/create — duplicate (expect 409)"
run "Create duplicate tenant" "409" \
  -X POST "$BASE/tenants/create" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT\"}"

# ── 4. Infra status — poll until ready ─────────────────────
hdr "4. GET /tenants/infra/status (poll)"
echo "  Polling infra status (max 60s)..." | tee -a "$LOG"
for i in $(seq 1 12); do
  resp=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -H "Authorization: Bearer $KEY" \
    "$BASE/tenants/infra/status?tenant_id=$TENANT")
  http_code=$(echo "$resp" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
  body=$(echo "$resp" | sed '/HTTP_STATUS:/d')
  echo "  Poll $i: HTTP $http_code | $body" | tee -a "$LOG"
  graph=$(echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('infra',{}).get('graph_status','?'))" 2>/dev/null || echo "?")
  vs=$(echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); vs=d.get('infra',{}).get('vectorstore_status',[]); print(all(vs))" 2>/dev/null || echo "?")
  if [[ "$graph" == "True" && "$vs" == "True" ]]; then
    ok "Infra ready after ${i} polls"
    break
  fi
  sleep 5
done

# ── 5. Monitor tenant ────────────────────────────────────────
hdr "5. GET /tenants/monitor"
run "Monitor tenant" "200" \
  "$BASE/tenants/monitor?tenant_id=$TENANT"

# ── 6. List sub-tenant IDs ───────────────────────────────────
hdr "6. GET /tenants/sub_tenant_ids"
run "List sub-tenant IDs" "200" \
  "$BASE/tenants/sub_tenant_ids?tenant_id=$TENANT"

# ── 7. Add memory — plain text ──────────────────────────────
hdr "7. POST /memories/add_memory — plain text"
ADD_MEM_RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer $KEY" \
  -X POST "$BASE/memories/add_memory" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"memories\": [{
      \"text\": \"User prefers detailed technical explanations and dark mode\",
      \"infer\": true,
      \"user_name\": \"Alex\",
      \"metadata\": { \"team\": \"engineering\" },
      \"additional_metadata\": { \"source\": \"onboarding\" }
    }]
  }")
http_code=$(echo "$ADD_MEM_RESP" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
body=$(echo "$ADD_MEM_RESP" | sed '/HTTP_STATUS:/d')
echo "  → Add memory (expected 200, got $http_code)" | tee -a "$LOG"
echo "    $body" | tee -a "$LOG"
MEM_SOURCE_ID=$(echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['source_id'])" 2>/dev/null || echo "")
echo "  source_id captured: $MEM_SOURCE_ID" | tee -a "$LOG"
[[ "$http_code" == "200" ]] && ok "Add memory — plain text" || fail "Add memory — plain text"

# ── 8. Add memory — conversation pairs ─────────────────────
hdr "8. POST /memories/add_memory — conversation pairs"
run "Add memory — conv pairs" "200" \
  -X POST "$BASE/memories/add_memory" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"memories\": [{
      \"user_assistant_pairs\": [
        { \"user\": \"I work mostly at night\", \"assistant\": \"Got it, I'll remember that.\" },
        { \"user\": \"And I prefer concise answers\", \"assistant\": \"Understood.\" }
      ],
      \"infer\": true,
      \"user_name\": \"Alex\"
    }]
  }"

# ── 9. Add memory — missing tenant_id (expect 400/422) ─────
hdr "9. POST /memories/add_memory — missing tenant_id (expect 4xx)"
run "Add memory — no tenant_id" "422" \
  -X POST "$BASE/memories/add_memory" \
  -H "Content-Type: application/json" \
  -d "{\"memories\": [{\"text\": \"test\"}]}"

# ── 10. Add memory — empty memories array (expect 4xx) ──────
hdr "10. POST /memories/add_memory — empty memories (expect 4xx)"
run "Add memory — empty array" "422" \
  -X POST "$BASE/memories/add_memory" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT\", \"memories\": []}"

# ── 11. Upload knowledge — app_knowledge ────────────────────
# Each item in app_knowledge requires tenant_id and sub_tenant_id inside the JSON.
# app_sources is the deprecated alias — use app_knowledge.
hdr "11. POST /ingestion/upload_knowledge — app_knowledge"
UPLOAD_RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer $KEY" \
  -X POST "$BASE/ingestion/upload_knowledge" \
  -F "tenant_id=$TENANT" \
  -F "app_knowledge=[{\"tenant_id\":\"$TENANT\",\"sub_tenant_id\":\"$SUB\",\"id\":\"qa_doc_001\",\"title\":\"QA Test Doc\",\"type\":\"internal\",\"content\":{\"text\":\"HydraDB pricing tiers: Starter at 29 per month, Pro at 79 per month, Enterprise at 199 per month.\"},\"metadata\":{\"category\":\"pricing\"},\"additional_metadata\":{\"author\":\"QA Bot\"}}]")
http_code=$(echo "$UPLOAD_RESP" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
body=$(echo "$UPLOAD_RESP" | sed '/HTTP_STATUS:/d')
echo "  → Upload knowledge (expected 200, got $http_code)" | tee -a "$LOG"
echo "    $body" | tee -a "$LOG"
KNOW_SOURCE_ID=$(echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['source_id'])" 2>/dev/null || echo "")
echo "  source_id captured: $KNOW_SOURCE_ID" | tee -a "$LOG"
[[ "$http_code" == "200" ]] && ok "Upload knowledge — app source" || fail "Upload knowledge — app source"

# ── 12. Upload knowledge — no content (expect 4xx) ─────────
hdr "12. POST /ingestion/upload_knowledge — no files/app_sources (expect 4xx)"
run "Upload knowledge — empty body" "422" \
  -X POST "$BASE/ingestion/upload_knowledge" \
  -F "tenant_id=$TENANT"

# ── 13. Verify processing ────────────────────────────────────
hdr "13. POST /ingestion/verify_processing (poll)"
sleep_if_needed 3
if [[ -n "$KNOW_SOURCE_ID" ]]; then
  for i in $(seq 1 10); do
    resp=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
      -H "Authorization: Bearer $KEY" \
      -X POST "$BASE/ingestion/verify_processing?file_ids=$KNOW_SOURCE_ID&tenant_id=$TENANT")
    http_code=$(echo "$resp" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
    body=$(echo "$resp" | sed '/HTTP_STATUS:/d')
    status=$(echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['statuses'][0]['indexing_status'])" 2>/dev/null || echo "?")
    echo "  Poll $i: HTTP $http_code | status=$status" | tee -a "$LOG"
    if [[ "$status" == "completed" || "$status" == "graph_creation" ]]; then
      ok "Verify processing — source_id=$KNOW_SOURCE_ID (status=$status)"
      break
    elif [[ "$status" == "errored" ]]; then
      fail "Verify processing — errored"
      break
    fi
    sleep 5
  done
else
  warn "Verify processing — skipped (no source_id from upload step)"
fi

# ── 14. Recall — full_recall ────────────────────────────────
hdr "14. POST /recall/full_recall"
sleep_if_needed 2
run "Full recall — fast mode" "200" \
  -X POST "$BASE/recall/full_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"What are the pricing tiers?\",
    \"max_results\": 3,
    \"mode\": \"fast\"
  }"

run "Full recall — thinking mode + graph_context" "200" \
  -X POST "$BASE/recall/full_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"pricing\",
    \"max_results\": 3,
    \"mode\": \"thinking\",
    \"graph_context\": true
  }"

run "Full recall — metadata_filters" "200" \
  -X POST "$BASE/recall/full_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"pricing\",
    \"metadata_filters\": { \"category\": \"pricing\" }
  }"

# ── 15. Recall — recall_preferences ─────────────────────────
hdr "15. POST /recall/recall_preferences"
run "Recall preferences — fast mode" "200" \
  -X POST "$BASE/recall/recall_preferences" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"query\": \"display and UI preferences\",
    \"max_results\": 3,
    \"mode\": \"fast\"
  }"

run "Recall preferences — thinking mode" "200" \
  -X POST "$BASE/recall/recall_preferences" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"query\": \"answer style preferences\",
    \"max_results\": 3,
    \"mode\": \"thinking\"
  }"

# ── 16. Boolean recall ───────────────────────────────────────
hdr "16. POST /recall/boolean_recall"
run "Boolean recall — OR operator" "200" \
  -X POST "$BASE/recall/boolean_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"pricing tiers\",
    \"operator\": \"or\",
    \"max_results\": 5,
    \"search_mode\": \"sources\"
  }"

run "Boolean recall — AND operator" "200" \
  -X POST "$BASE/recall/boolean_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"pricing tiers\",
    \"operator\": \"and\",
    \"max_results\": 5
  }"

run "Boolean recall — phrase operator" "200" \
  -X POST "$BASE/recall/boolean_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"query\": \"pricing tiers\",
    \"operator\": \"phrase\",
    \"max_results\": 5
  }"

run "Boolean recall — memories search_mode" "200" \
  -X POST "$BASE/recall/boolean_recall" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"query\": \"dark mode\",
    \"operator\": \"and\",
    \"search_mode\": \"memories\"
  }"

# ── 17. List data ────────────────────────────────────────────
hdr "17. POST /list/data"
run "List data — knowledge" "200" \
  -X POST "$BASE/list/data" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"kind\": \"knowledge\",
    \"page\": 1,
    \"page_size\": 25
  }"

run "List data — memories" "200" \
  -X POST "$BASE/list/data" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"sub_tenant_id\": \"$SUB\",
    \"kind\": \"memories\",
    \"page\": 1,
    \"page_size\": 25
  }"

run "List data — with metadata filter" "200" \
  -X POST "$BASE/list/data" \
  -H "Content-Type: application/json" \
  -d "{
    \"tenant_id\": \"$TENANT\",
    \"kind\": \"knowledge\",
    \"filters\": { \"metadata\": { \"category\": \"pricing\" } }
  }"

# ── 18. Fetch content ────────────────────────────────────────
hdr "18. POST /fetch/content"
if [[ -n "$KNOW_SOURCE_ID" ]]; then
  run "Fetch content — url mode" "200" \
    -X POST "$BASE/fetch/content" \
    -H "Content-Type: application/json" \
    -d "{
      \"tenant_id\": \"$TENANT\",
      \"source_id\": \"$KNOW_SOURCE_ID\",
      \"mode\": \"url\"
    }"

  run "Fetch content — content mode" "200" \
    -X POST "$BASE/fetch/content" \
    -H "Content-Type: application/json" \
    -d "{
      \"tenant_id\": \"$TENANT\",
      \"source_id\": \"$KNOW_SOURCE_ID\",
      \"mode\": \"content\"
    }"

  run "Fetch content — invalid source_id (expect 404)" "404" \
    -X POST "$BASE/fetch/content" \
    -H "Content-Type: application/json" \
    -d "{
      \"tenant_id\": \"$TENANT\",
      \"source_id\": \"nonexistent_source_id_xyz\",
      \"mode\": \"url\"
    }"
else
  warn "Fetch content — skipped (no source_id from upload step)"
fi

# ── 19. Graph relations ──────────────────────────────────────
hdr "19. GET /list/graph_relations_by_id"
if [[ -n "$KNOW_SOURCE_ID" ]]; then
  run "Graph relations — knowledge source" "200" \
    "$BASE/list/graph_relations_by_id?source_id=$KNOW_SOURCE_ID&tenant_id=$TENANT&limit=50"
else
  warn "Graph relations — skipped (no source_id)"
fi

# ── 20. Delete knowledge ─────────────────────────────────────
hdr "20. POST /knowledge/delete_knowledge"
if [[ -n "$KNOW_SOURCE_ID" ]]; then
  run "Delete knowledge" "200" \
    -X POST "$BASE/knowledge/delete_knowledge" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT\", \"ids\": [\"$KNOW_SOURCE_ID\"]}"

  run "Delete knowledge — already deleted (expect 200 with deleted:false)" "200" \
    -X POST "$BASE/knowledge/delete_knowledge" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT\", \"ids\": [\"$KNOW_SOURCE_ID\"]}"
else
  warn "Delete knowledge — skipped (no source_id)"
fi

# ── 21. Delete memory ────────────────────────────────────────
hdr "21. DELETE /memories/delete_memory"
if [[ -n "$MEM_SOURCE_ID" ]]; then
  run "Delete memory" "200" \
    -X DELETE "$BASE/memories/delete_memory?tenant_id=$TENANT&memory_id=$MEM_SOURCE_ID&sub_tenant_id=$SUB"

  # API is idempotent — re-deletion returns 200, not 404
  run "Delete memory — re-deletion (idempotent, expect 200)" "200" \
    -X DELETE "$BASE/memories/delete_memory?tenant_id=$TENANT&memory_id=$MEM_SOURCE_ID"
else
  warn "Delete memory — skipped (no memory_id)"
fi

# ── 22. Auth errors ──────────────────────────────────────────
hdr "22. Auth edge cases"
resp=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "$BASE/tenants/tenant_ids")
http_code=$(echo "$resp" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
[[ "$http_code" == "401" ]] && ok "No auth header → 401" || fail "No auth header → expected 401, got $http_code"

resp=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer invalid_key_xyz" \
  "$BASE/tenants/tenant_ids")
http_code=$(echo "$resp" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
[[ "$http_code" == "401" ]] && ok "Invalid key → 401" || fail "Invalid key → expected 401, got $http_code"

# ── 23. Tenant not found ─────────────────────────────────────
hdr "23. Tenant not found (expect 404)"
run "Recall on missing tenant" "404" \
  -X POST "$BASE/recall/full_recall" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"nonexistent_tenant_xyz\", \"query\": \"test\"}"

# ── 24. Tear down ────────────────────────────────────────────
hdr "24. DELETE /tenants/delete"
run "Delete tenant" "200" \
  -X DELETE "$BASE/tenants/delete?tenant_id=$TENANT"

# ════════════════════════════════════════════════════════════
echo | tee -a "$LOG"
echo "════════════════════════════════" | tee -a "$LOG"
echo "RESULTS: ✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings" | tee -a "$LOG"
echo "Full log: $LOG" | tee -a "$LOG"
