/**
 * HydraDB TypeScript SDK Test Suite — corrected
 * Confirmed from @hydradb/sdk type definitions:
 *   - ALL parameter field names are snake_case (tenant_id, sub_tenant_id, max_results, etc.)
 *   - Only method names are camelCase (getInfraStatus, addMemory, fullRecall, etc.)
 *   - app_knowledge is correct; app_sources is the deprecated alias
 *   - Each app_knowledge item requires tenant_id and sub_tenant_id inside the JSON
 *   - ContentFilter uses tenant_metadata / document_metadata (not metadata / additional_metadata)
 *   - delete_memory is idempotent — re-deletion returns 200, not 404
 *
 * Usage:
 *   HYDRADB_API_KEY="sk_live_..." npx ts-node tests/test_typescript.ts
 *
 * Requires:
 *   npm install @hydradb/sdk ts-node typescript @types/node
 *
 * Output: tests/results_typescript.log
 */

import { HydraDBClient } from "@hydradb/sdk";
import * as fs from "fs";

const API_KEY = process.env.HYDRADB_API_KEY ?? "";
if (!API_KEY) { console.error("ERROR: Set HYDRADB_API_KEY before running"); process.exit(1); }

const TENANT = `hydradb-ts-${Date.now()}`;
const SUB    = "ts_user_001";
const LOG    = "tests/results_typescript.log";
fs.mkdirSync("tests", { recursive: true });
const stream = fs.createWriteStream(LOG);

let passed = 0, failed = 0, warned = 0;

const log  = (m: string) => { console.log(m); stream.write(m + "\n"); };
const hdr  = (m: string) => log(`\n━━━ ${m} ━━━`);
const ok   = (m: string) => { log(`  ✅ PASS  ${m}`); passed++; };
const fail = (m: string, d = "") => { log(`  ❌ FAIL  ${m}`); if (d) log(`    ${d}`); failed++; };
const warn = (m: string, d = "") => { log(`  ⚠️  WARN  ${m}`); if (d) log(`    ${d}`); warned++; };
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

async function check<T>(
  label: string,
  fn: () => Promise<T>,
  validate?: (r: T) => void
): Promise<T | null> {
  try {
    const result = await fn();
    log(`  → ${label}: ${JSON.stringify(result).slice(0, 300)}`);
    if (validate) validate(result);
    ok(label);
    return result;
  } catch (e: any) {
    const msg = String(e?.message ?? e);
    if (msg.includes("429") || msg.toUpperCase().includes("RATE_LIMIT")) {
      warn(label, `Rate limited — ${msg}`);
      await sleep(5000);
      return null;
    }
    fail(label, `${e?.constructor?.name ?? "Error"}: ${msg}`);
    return null;
  }
}

async function main() {
  log(`HydraDB TypeScript SDK Test Suite`);
  log(`Tenant: ${TENANT}`);

  const client = new HydraDBClient({ token: API_KEY });
  ok("HydraDBClient initialised");

  // ── 1. List tenant IDs ──────────────────────────────────────
  hdr("1. client.tenant.getTenantIds()");
  const existing = await check("getTenantIds",
    () => client.tenant.getTenantIds());
  log(`  Existing tenants: ${JSON.stringify((existing as any)?.tenant_ids)}`);

  // ── 2. Create tenant ────────────────────────────────────────
  hdr("2. client.tenant.create()");
  await check("create tenant",
    () => client.tenant.create({
      tenant_id: TENANT,
      tenant_metadata_schema: [
        { name: "category", data_type: "VARCHAR", max_length: 256, enable_match: true }
      ]
    }));

  // ── 3. Duplicate tenant → expect error ──────────────────────
  hdr("3. client.tenant.create() — duplicate (expect error)");
  try {
    await client.tenant.create({ tenant_id: TENANT });
    fail("duplicate tenant — expected error, got none");
  } catch (e: any) {
    const msg = String(e?.message ?? e);
    if (msg.includes("409") || msg.toLowerCase().includes("already")) {
      ok("duplicate tenant → 409-class error");
    } else {
      warn("duplicate tenant — unexpected error type", msg);
    }
  }

  // ── 4. Infra status — poll ───────────────────────────────────
  hdr("4. client.tenant.getInfraStatus() — poll until ready");
  let ready = false;
  for (let i = 0; i < 12; i++) {
    try {
      const s = await client.tenant.getInfraStatus({ tenant_id: TENANT });
      const infra = (s as any).infra;
      log(`  Poll ${i+1}: graph=${infra?.graph_status} vs=${JSON.stringify(infra?.vectorstore_status)}`);
      if (infra?.graph_status && (infra?.vectorstore_status as boolean[])?.every(Boolean)) {
        ok(`Infra ready after ${i+1} polls`); ready = true; break;
      }
    } catch (e: any) { log(`  Poll ${i+1} error: ${e.message}`); }
    await sleep(5000);
  }
  if (!ready) warn("Infra not ready after 60s — continuing anyway");

  // ── 5. Monitor ──────────────────────────────────────────────
  hdr("5. client.tenant.monitor()");
  await check("monitor", () => client.tenant.monitor({ tenant_id: TENANT }));

  // ── 6. Sub-tenant IDs ───────────────────────────────────────
  hdr("6. client.tenant.getSubTenantIds()");
  await check("getSubTenantIds",
    () => client.tenant.getSubTenantIds({ tenant_id: TENANT }));

  // ── 7. Add memory — plain text ──────────────────────────────
  hdr("7. client.upload.addMemory() — plain text");
  const memResult = await check("addMemory plain text",
    () => client.upload.addMemory({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      upsert: true,
      memories: [{
        text: "User prefers detailed technical explanations and dark mode",
        infer: true,
        user_name: "Alex",
        metadata: { team: "engineering" },
        additional_metadata: { source: "onboarding" },
      }]
    }),
    r => { if (!(r as any).success) throw new Error("success !== true"); });
  const memSourceId: string | null = (memResult as any)?.results?.[0]?.source_id ?? null;
  log(`  memory source_id: ${memSourceId}`);

  // ── 8. Add memory — conversation pairs ──────────────────────
  hdr("8. client.upload.addMemory() — conversation pairs");
  await check("addMemory conv pairs",
    () => client.upload.addMemory({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      memories: [{
        user_assistant_pairs: [
          { user: "I work at night", assistant: "Noted." },
          { user: "I prefer concise answers", assistant: "Understood." },
        ],
        infer: true,
        user_name: "Alex",
      }]
    }));

  // ── 9. Add memory — empty (expect error) ────────────────────
  hdr("9. client.upload.addMemory() — empty memories (expect error)");
  try {
    await client.upload.addMemory({ tenant_id: TENANT, memories: [] });
    fail("empty memories — expected error, got none");
  } catch (e: any) {
    ok(`empty memories → error: ${e?.constructor?.name}`);
  }

  // ── 10. Upload knowledge — app_knowledge ────────────────────
  // Each item in app_knowledge requires tenant_id and sub_tenant_id inside the JSON.
  // app_sources is the deprecated alias — use app_knowledge.
  hdr("10. client.upload.knowledge() — app_knowledge");
  const knowResult = await check("upload knowledge",
    () => client.upload.knowledge({
      tenant_id: TENANT,
      app_knowledge: JSON.stringify([{
        tenant_id: TENANT,
        sub_tenant_id: SUB,
        id: "qa_doc_ts_001",
        title: "TS QA Test Doc",
        type: "internal",
        content: { text: "HydraDB pricing: Starter $29, Pro $79, Enterprise $199." },
        metadata: { category: "pricing" },
        additional_metadata: { author: "TS QA" },
      }]),
      upsert: true,
    }),
    r => { if (!(r as any).success) throw new Error("success !== true"); });
  const knowSourceId: string | null = (knowResult as any)?.results?.[0]?.source_id ?? null;
  log(`  knowledge source_id: ${knowSourceId}`);

  // ── 11. Verify processing ────────────────────────────────────
  hdr("11. client.upload.verifyProcessing()");
  await sleep(3000);
  if (knowSourceId) {
    let done = false;
    for (let i = 0; i < 10; i++) {
      try {
        const vp = await client.upload.verifyProcessing({
          tenant_id: TENANT,
          file_ids: [knowSourceId],
        });
        const st = (vp as any).statuses?.[0]?.indexing_status;
        log(`  Poll ${i+1}: ${st}`);
        if (st === "completed" || st === "graph_creation") {
          ok(`verifyProcessing (status=${st})`); done = true; break;
        } else if (st === "errored") { fail("verifyProcessing — errored"); break; }
      } catch (e: any) { log(`  Poll ${i+1} error: ${e.message}`); }
      await sleep(5000);
    }
    if (!done) warn("verifyProcessing — not completed in time");
  } else {
    warn("verifyProcessing — skipped (no source_id)");
  }

  // ── 12. Full recall ──────────────────────────────────────────
  hdr("12. client.recall.fullRecall()");
  await sleep(2000);

  await check("fullRecall fast",
    () => client.recall.fullRecall({
      tenant_id: TENANT,
      query: "What are the pricing tiers?",
      max_results: 3,
      mode: "fast",
    }),
    r => { if (!(r as any).chunks) throw new Error("missing chunks field"); });

  await check("fullRecall thinking + graph_context",
    () => client.recall.fullRecall({
      tenant_id: TENANT,
      query: "pricing",
      max_results: 3,
      mode: "thinking",
      graph_context: true,
    }),
    r => { if (!(r as any).chunks) throw new Error("missing chunks field"); });

  await check("fullRecall metadata_filters",
    () => client.recall.fullRecall({
      tenant_id: TENANT,
      query: "pricing",
      metadata_filters: { category: "pricing" },
    }));

  await check("fullRecall alpha + recency_bias",
    () => client.recall.fullRecall({
      tenant_id: TENANT,
      query: "pricing",
      alpha: 0.3,
      recency_bias: 0.5,
      max_results: 5,
    }));

  // ── 13. Recall preferences ───────────────────────────────────
  hdr("13. client.recall.recallPreferences()");
  await check("recallPreferences fast",
    () => client.recall.recallPreferences({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      query: "display and UI preferences",
      max_results: 3,
      mode: "fast",
    }),
    r => { if (!(r as any).chunks) throw new Error("missing chunks"); });

  await check("recallPreferences thinking",
    () => client.recall.recallPreferences({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      query: "answer style",
      mode: "thinking",
    }));

  // ── 14. Boolean recall ───────────────────────────────────────
  hdr("14. client.recall.booleanRecall()");
  await check("booleanRecall OR",
    () => client.recall.booleanRecall({
      tenant_id: TENANT,
      query: "pricing tiers",
      operator: "or",
      max_results: 5,
      search_mode: "sources",
    }));

  await check("booleanRecall AND",
    () => client.recall.booleanRecall({
      tenant_id: TENANT,
      query: "pricing tiers",
      operator: "and",
    }));

  await check("booleanRecall phrase",
    () => client.recall.booleanRecall({
      tenant_id: TENANT,
      query: "pricing tiers",
      operator: "phrase",
    }));

  await check("booleanRecall memories",
    () => client.recall.booleanRecall({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      query: "dark mode",
      operator: "or",
      search_mode: "memories",
    }));

  // ── 15. List data ────────────────────────────────────────────
  // Note: ContentFilter uses tenant_metadata / document_metadata (not metadata / additional_metadata)
  hdr("15. client.fetch.listData()");
  await check("listData knowledge",
    () => client.fetch.listData({
      tenant_id: TENANT,
      kind: "knowledge",
      page: 1,
      page_size: 25,
    }));

  await check("listData memories",
    () => client.fetch.listData({
      tenant_id: TENANT,
      sub_tenant_id: SUB,
      kind: "memories",
    }));

  await check("listData with ContentFilter",
    () => client.fetch.listData({
      tenant_id: TENANT,
      kind: "knowledge",
      filters: { tenant_metadata: { category: "pricing" } },
    }));

  // ── 16. Fetch content ────────────────────────────────────────
  hdr("16. client.fetch.content()");
  if (knowSourceId) {
    await check("fetch content url",
      () => client.fetch.content({
        tenant_id: TENANT,
        source_id: knowSourceId,
        mode: "url",
      }),
      r => { if (!(r as any).success) throw new Error("success !== true"); });

    await check("fetch content content mode",
      () => client.fetch.content({
        tenant_id: TENANT,
        source_id: knowSourceId,
        mode: "content",
      }));

    await check("fetch content both mode",
      () => client.fetch.content({
        tenant_id: TENANT,
        source_id: knowSourceId,
        mode: "both",
        expiry_seconds: 3600,
      }));

    hdr("16b. fetch content — invalid source_id (expect error)");
    try {
      await client.fetch.content({ tenant_id: TENANT, source_id: "nonexistent_xyz", mode: "url" });
      fail("invalid source_id — expected error, got none");
    } catch (e: any) {
      const msg = String(e?.message ?? e);
      if (msg.includes("404") || msg.toUpperCase().includes("NOT_FOUND")) {
        ok("invalid source_id → 404-class error");
      } else {
        warn("invalid source_id — unexpected error", msg);
      }
    }
  } else {
    warn("fetch content — skipped (no source_id)");
  }

  // ── 17. Graph relations ──────────────────────────────────────
  hdr("17. client.fetch.graphRelationsBySourceId()");
  if (knowSourceId) {
    await check("graphRelationsBySourceId",
      () => client.fetch.graphRelationsBySourceId({
        tenant_id: TENANT,
        source_id: knowSourceId,
        is_memory: false,
        limit: 50,
      }));
  } else {
    warn("graphRelationsBySourceId — skipped");
  }

  // ── 18. Delete knowledge ─────────────────────────────────────
  hdr("18. client.data.delete()");
  if (knowSourceId) {
    await check("delete knowledge",
      () => client.data.delete({
        tenant_id: TENANT,
        ids: [knowSourceId],
      }),
      r => { if (!(r as any).success) throw new Error("success !== true"); });
  } else {
    warn("delete knowledge — skipped");
  }

  // ── 19. Delete memory ────────────────────────────────────────
  hdr("19. client.upload.deleteMemory()");
  if (memSourceId) {
    await check("deleteMemory",
      () => client.upload.deleteMemory({
        tenant_id: TENANT,
        sub_tenant_id: SUB,
        memory_id: memSourceId,
      }),
      r => { if (!(r as any).success) throw new Error("success !== true"); });

    // API is idempotent — re-deletion returns 200 success, not 404
    hdr("19b. deleteMemory — re-deletion (idempotent, expect 200)");
    await check("re-delete memory — idempotent",
      () => client.upload.deleteMemory({
        tenant_id: TENANT,
        memory_id: memSourceId,
      }));
  } else {
    warn("deleteMemory — skipped");
  }

  // ── 20. Delete tenant ────────────────────────────────────────
  hdr("20. client.tenant.deleteTenant()");
  await check("deleteTenant",
    () => client.tenant.deleteTenant({ tenant_id: TENANT }));

  // ── summary ─────────────────────────────────────────────────
  stream.end();
  console.log("\n" + "═".repeat(50));
  console.log(`RESULTS: ✅ ${passed} passed | ❌ ${failed} failed | ⚠️  ${warned} warnings`);
  console.log(`Full log: ${LOG}`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error("Fatal:", e); process.exit(1); });
