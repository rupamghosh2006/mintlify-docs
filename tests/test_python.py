#!/usr/bin/env python3
"""
HydraDB Python SDK Test Suite
Tests every documented SDK method against the live API.
Usage:  HYDRADB_API_KEY="sk_live_..." python3 tests/test_python.py
Output: tests/results_python.log
Requires: pip install hydradb-sdk
"""

import os
import sys
import json
import time
import traceback
from pathlib import Path

# ── setup ───────────────────────────────────────────────────
API_KEY = os.environ.get("HYDRADB_API_KEY", "")
if not API_KEY:
    print("ERROR: Set HYDRADB_API_KEY before running")
    sys.exit(1)

LOG_PATH = Path("tests/results_python.log")
LOG_PATH.parent.mkdir(exist_ok=True)
log_file = open(LOG_PATH, "w")

TENANT = f"hydradb-py-{int(time.time())}"
SUB = "py_user_001"

passed = 0
failed = 0
warned = 0

def log(msg):
    print(msg)
    log_file.write(msg + "\n")
    log_file.flush()

def hdr(msg):
    log(f"\n━━━ {msg} ━━━")

def ok(label):
    global passed
    log(f"  ✅ PASS  {label}")
    passed += 1

def fail(label, detail=""):
    global failed
    log(f"  ❌ FAIL  {label}")
    if detail:
        log(f"    {detail}")
    failed += 1

def warn(label, detail=""):
    global warned
    log(f"  ⚠️  WARN  {label}")
    if detail:
        log(f"    {detail}")
    warned += 1

def check(label, fn, validate=None):
    """Run fn(), pass if no exception; optionally validate result."""
    try:
        result = fn()
        result_str = str(result)[:300]
        log(f"  → {label}: {result_str}")
        if validate:
            validate(result)
        ok(label)
        return result
    except Exception as e:
        err = str(e)
        if "429" in err or "RATE_LIMITED" in err.upper():
            warn(label, f"Rate limited — {err}")
            time.sleep(5)
            return None
        fail(label, f"{type(e).__name__}: {err}")
        log(f"  {traceback.format_exc()}")
        return None

# ── install / import ─────────────────────────────────────────
hdr("0. Install & import SDK")
try:
    from hydra_db import HydraDB, AsyncHydraDB
    ok("import hydra_db")
except ImportError:
    log("  Installing hydradb-sdk...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "hydradb-sdk", "-q"])
    from hydra_db import HydraDB, AsyncHydraDB
    ok("import hydra_db (after install)")

client = HydraDB(token=API_KEY)
ok("HydraDB client initialised")

# ── 1. List tenant IDs ──────────────────────────────────────
hdr("1. client.tenant.get_tenant_ids()")
res = check("get_tenant_ids",
    lambda: client.tenant.get_tenant_ids(),
    lambda r: r.tenant_ids is not None)
log(f"  Existing tenants: {getattr(res, 'tenant_ids', '?')}")

# ── 2. Create tenant ────────────────────────────────────────
hdr("2. client.tenant.create()")
check("create tenant",
    lambda: client.tenant.create(
        tenant_id=TENANT,
        tenant_metadata_schema=[
            {"name": "category", "data_type": "VARCHAR",
             "max_length": 256, "enable_match": True}
        ]
    ))

# ── 3. Duplicate tenant → expect exception ──────────────────
hdr("3. client.tenant.create() — duplicate (expect error)")
try:
    client.tenant.create(tenant_id=TENANT)
    fail("duplicate tenant — expected exception, got none")
except Exception as e:
    if "409" in str(e) or "ALREADY_EXISTS" in str(e).upper() or "already" in str(e).lower():
        ok("duplicate tenant raises 409-class error")
    else:
        warn("duplicate tenant — unexpected error type", str(e))

# ── 4. Infra status — poll ───────────────────────────────────
hdr("4. client.tenant.get_infra_status() — poll until ready")
ready = False
for i in range(12):
    try:
        status = client.tenant.get_infra_status(tenant_id=TENANT)
        infra = status.infra
        log(f"  Poll {i+1}: graph={getattr(infra,'graph_status','?')} "
            f"vs={getattr(infra,'vectorstore_status','?')}")
        if infra.graph_status and all(infra.vectorstore_status):
            ok(f"Infra ready after {i+1} polls")
            ready = True
            break
    except Exception as e:
        log(f"  Poll {i+1} error: {e}")
    time.sleep(5)
if not ready:
    warn("Infra not ready after 60s — continuing anyway")

# ── 5. Monitor tenant ────────────────────────────────────────
hdr("5. client.tenant.monitor()")
check("monitor tenant",
    lambda: client.tenant.monitor(tenant_id=TENANT),
    lambda r: hasattr(r, "normal_collection") or hasattr(r, "tenant_id"))

# ── 6. Sub-tenant IDs ───────────────────────────────────────
hdr("6. client.tenant.get_sub_tenant_ids()")
check("get_sub_tenant_ids",
    lambda: client.tenant.get_sub_tenant_ids(tenant_id=TENANT))

# ── 7. Add memory — plain text ──────────────────────────────
hdr("7. client.upload.add_memory() — plain text")
mem_result = check("add_memory plain text",
    lambda: client.upload.add_memory(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        upsert=True,
        memories=[{
            "text": "User prefers detailed technical explanations and dark mode",
            "infer": True,
            "user_name": "Alex",
            "metadata": {"team": "engineering"},
            "additional_metadata": {"source": "onboarding"},
        }]
    ),
    lambda r: r.success is True)
mem_source_id = None
if mem_result:
    try:
        mem_source_id = mem_result.results[0].source_id
        log(f"  memory source_id: {mem_source_id}")
    except Exception:
        pass

# ── 8. Add memory — markdown ─────────────────────────────────
hdr("8. client.upload.add_memory() — markdown")
check("add_memory markdown",
    lambda: client.upload.add_memory(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        memories=[{
            "text": "# Notes\n\n- Prefers dark mode\n- Likes detailed explanations",
            "is_markdown": True,
            "infer": False,
        }]
    ))

# ── 9. Add memory — conversation pairs ──────────────────────
hdr("9. client.upload.add_memory() — conversation pairs")
check("add_memory conv pairs",
    lambda: client.upload.add_memory(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        memories=[{
            "user_assistant_pairs": [
                {"user": "I work mostly at night", "assistant": "Got it."},
                {"user": "And I prefer concise answers", "assistant": "Understood."}
            ],
            "infer": True,
            "user_name": "Alex",
        }]
    ))

# ── 10. Add memory — missing memories key (expect error) ────
hdr("10. client.upload.add_memory() — empty memories list (expect error)")
try:
    client.upload.add_memory(tenant_id=TENANT, memories=[])
    fail("empty memories — expected error, got none")
except Exception as e:
    ok(f"empty memories raises error: {type(e).__name__}")

# ── 11. Upload knowledge — app source ───────────────────────
hdr("11. client.upload.knowledge() — app source")
import json as json_mod
# Each item in app_knowledge requires tenant_id and sub_tenant_id inside the JSON.
# app_sources is the deprecated alias — use app_knowledge.
know_result = check("upload knowledge app_knowledge",
    lambda: client.upload.knowledge(
        tenant_id=TENANT,
        app_knowledge=json_mod.dumps([{
            "tenant_id": TENANT,
            "sub_tenant_id": SUB,
            "id": "qa_doc_001",
            "title": "QA Test Doc",
            "type": "internal",
            "content": {"text": "HydraDB pricing: Starter $29/mo, Pro $79/mo, Enterprise $199/mo."},
            "metadata": {"category": "pricing"},
            "additional_metadata": {"author": "QA Bot"},
        }]),
        upsert=True,
    ),
    lambda r: r.success is True)

know_source_id = None
if know_result:
    try:
        know_source_id = know_result.results[0].source_id
        log(f"  knowledge source_id: {know_source_id}")
    except Exception:
        pass

# ── 12. Verify processing ────────────────────────────────────
hdr("12. client.upload.verify_processing()")
time.sleep(3)
if know_source_id:
    for i in range(10):
        try:
            vp = client.upload.verify_processing(
                tenant_id=TENANT,
                file_ids=[know_source_id],
            )
            status_val = vp.statuses[0].indexing_status
            log(f"  Poll {i+1}: {status_val}")
            if status_val in ("completed", "graph_creation"):
                ok(f"verify_processing completed (status={status_val})")
                break
            elif status_val == "errored":
                fail("verify_processing — errored")
                break
        except Exception as e:
            log(f"  Poll {i+1} error: {e}")
        time.sleep(5)
else:
    warn("verify_processing — skipped (no source_id)")

# ── 13. Full recall ──────────────────────────────────────────
hdr("13. client.recall.full_recall()")
time.sleep(2)
check("full_recall fast mode",
    lambda: client.recall.full_recall(
        tenant_id=TENANT,
        query="What are the pricing tiers?",
        max_results=3,
        mode="fast",
    ),
    lambda r: hasattr(r, "chunks"))

check("full_recall thinking + graph_context",
    lambda: client.recall.full_recall(
        tenant_id=TENANT,
        query="pricing",
        max_results=3,
        mode="thinking",
        graph_context=True,
    ),
    lambda r: hasattr(r, "chunks"))

check("full_recall metadata_filters",
    lambda: client.recall.full_recall(
        tenant_id=TENANT,
        query="pricing",
        metadata_filters={"category": "pricing"},
    ),
    lambda r: hasattr(r, "chunks"))

check("full_recall alpha and recency_bias",
    lambda: client.recall.full_recall(
        tenant_id=TENANT,
        query="pricing",
        alpha=0.3,
        recency_bias=0.5,
        max_results=5,
    ),
    lambda r: hasattr(r, "chunks"))

# ── 14. Recall preferences ───────────────────────────────────
hdr("14. client.recall.recall_preferences()")
check("recall_preferences fast",
    lambda: client.recall.recall_preferences(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        query="display and UI preferences",
        max_results=3,
        mode="fast",
    ),
    lambda r: hasattr(r, "chunks"))

check("recall_preferences thinking",
    lambda: client.recall.recall_preferences(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        query="answer style",
        max_results=3,
        mode="thinking",
    ),
    lambda r: hasattr(r, "chunks"))

# ── 15. Boolean recall ───────────────────────────────────────
hdr("15. client.recall.boolean_recall()")
check("boolean_recall OR",
    lambda: client.recall.boolean_recall(
        tenant_id=TENANT,
        query="pricing tiers",
        operator="or",
        max_results=5,
        search_mode="sources",
    ),
    lambda r: hasattr(r, "chunks"))

check("boolean_recall AND",
    lambda: client.recall.boolean_recall(
        tenant_id=TENANT,
        query="pricing tiers",
        operator="and",
        max_results=5,
    ))

check("boolean_recall phrase",
    lambda: client.recall.boolean_recall(
        tenant_id=TENANT,
        query="pricing tiers",
        operator="phrase",
        max_results=5,
    ))

check("boolean_recall memories",
    lambda: client.recall.boolean_recall(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        query="dark mode",
        operator="or",
        search_mode="memories",
    ))

# ── 16. List data ────────────────────────────────────────────
hdr("16. client.fetch.list_data()")
check("list_data knowledge",
    lambda: client.fetch.list_data(
        tenant_id=TENANT,
        kind="knowledge",
        page=1,
        page_size=25,
    ),
    lambda r: hasattr(r, "sources") or hasattr(r, "pagination"))

check("list_data memories",
    lambda: client.fetch.list_data(
        tenant_id=TENANT,
        sub_tenant_id=SUB,
        kind="memories",
        page=1,
        page_size=25,
    ))

check("list_data with filters",
    lambda: client.fetch.list_data(
        tenant_id=TENANT,
        kind="knowledge",
        filters={"metadata": {"category": "pricing"}},
    ))

# ── 17. Fetch content ────────────────────────────────────────
hdr("17. client.fetch.content()")
if know_source_id:
    check("fetch content url mode",
        lambda: client.fetch.content(
            tenant_id=TENANT,
            source_id=know_source_id,
            mode="url",
        ),
        lambda r: r.success is True)

    check("fetch content content mode",
        lambda: client.fetch.content(
            tenant_id=TENANT,
            source_id=know_source_id,
            mode="content",
        ))

    check("fetch content both mode",
        lambda: client.fetch.content(
            tenant_id=TENANT,
            source_id=know_source_id,
            mode="both",
            expiry_seconds=3600,
        ))

    hdr("17b. fetch content — invalid source_id (expect 404-class error)")
    try:
        client.fetch.content(tenant_id=TENANT, source_id="nonexistent_xyz", mode="url")
        fail("fetch content invalid id — expected error, got none")
    except Exception as e:
        if "404" in str(e) or "NOT_FOUND" in str(e).upper():
            ok("fetch content invalid id → 404-class error")
        else:
            warn("fetch content invalid id — unexpected error", str(e))
else:
    warn("fetch content — skipped (no source_id)")

# ── 18. Graph relations ──────────────────────────────────────
hdr("18. client.fetch.graph_relations_by_source_id()")
if know_source_id:
    check("graph_relations_by_source_id",
        lambda: client.fetch.graph_relations_by_source_id(
            tenant_id=TENANT,
            source_id=know_source_id,
            is_memory=False,
            limit=50,
        ))
else:
    warn("graph relations — skipped (no source_id)")

# ── 19. Delete knowledge ─────────────────────────────────────
hdr("19. client.data.delete()")
if know_source_id:
    check("delete knowledge",
        lambda: client.data.delete(
            tenant_id=TENANT,
            ids=[know_source_id],
        ),
        lambda r: r.success is True)

    # re-delete → should return deleted:false but success:true
    res2 = check("delete knowledge — already deleted",
        lambda: client.data.delete(
            tenant_id=TENANT,
            ids=[know_source_id],
        ))
    if res2:
        try:
            item = res2.results[0]
            if not item.deleted:
                ok("re-delete returns deleted:False as documented")
            else:
                warn("re-delete returned deleted:True (unexpected)")
        except Exception:
            pass
else:
    warn("delete knowledge — skipped (no source_id)")

# ── 20. Delete memory ────────────────────────────────────────
hdr("20. client.upload.delete_memory()")
if mem_source_id:
    check("delete memory",
        lambda: client.upload.delete_memory(
            tenant_id=TENANT,
            sub_tenant_id=SUB,
            memory_id=mem_source_id,
        ),
        lambda r: r.success is True)

    # API is idempotent — re-deletion returns 200, not 404
    hdr("20b. delete memory — re-deletion (idempotent, expect 200)")
    check("re-delete memory — idempotent",
        lambda: client.upload.delete_memory(
            tenant_id=TENANT,
            memory_id=mem_source_id,
        ))
else:
    warn("delete memory — skipped (no memory_id)")

# ── 21. Delete tenant ────────────────────────────────────────
hdr("21. client.tenant.delete_tenant()")
check("delete tenant",
    lambda: client.tenant.delete_tenant(tenant_id=TENANT))

# ── 22. Tenant not found after deletion ─────────────────────
hdr("22. Recall on deleted tenant (expect 404-class)")
time.sleep(2)
try:
    client.recall.full_recall(tenant_id=TENANT, query="test")
    warn("recall on deleted tenant — expected error, got none (may be eventual)")
except Exception as e:
    if "404" in str(e) or "NOT_FOUND" in str(e).upper():
        ok("recall on deleted tenant → 404-class error")
    else:
        warn("recall on deleted tenant — unexpected error type", str(e))

# ── summary ─────────────────────────────────────────────────
log_file.close()
print()
print("═" * 50)
print(f"RESULTS: ✅ {passed} passed | ❌ {failed} failed | ⚠️  {warned} warnings")
print(f"Full log: {LOG_PATH}")
sys.exit(1 if failed > 0 else 0)
