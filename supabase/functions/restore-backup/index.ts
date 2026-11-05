import { createClient } from "jsr:@supabase/supabase-js@2";

// Restores a backup. Send a Storage path or a `tables` object.
// Needs the backup:restore permission; rows are written with the service role.
// Merge mode adds and overwrites rows; replace mode also deletes rows the
// backup lacks. Tables are written in RESTORE_ORDER (foreign keys), and a
// failed table is retried once. Tables absent from the backup are untouched.
// Every response carries CORS headers, errors included, so the browser can read them.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Parent tables come before the tables that point to them.
const RESTORE_ORDER = [
  "phases",
  "roles", "permissions", "role_permissions", "permit_types",
  "violation_types", "budget_categories", "system_settings",
  "waste_schedules", "blocks", "lots", "users",
  "backup_settings", "document_folders", "facilities", "payment_channels",
  "household_members", "personal_folders", "announcements",
  "events", "budget_expenses", "bills", "payments", "payment_submissions",
  "complaints", "violations", "permits", "vehicles", "visitor_logs",
  "gate_passes", "move_requests", "reservations", "security_incidents",
  "documents", "notifications", "audit_logs",
];

// Tables that no longer exist. Old backups still list them, so they are
// skipped by name instead of failing as unknown tables.
const DROPPED_TABLES = new Set([
  "conversations", "messages", "chatbot_sessions", "chatbot_messages",
]);

// Sign-in accounts are stored under these keys and restored through
// restore_auth_accounts(), because restore_backup_table() does not cover
// the auth schema.
const AUTH_KEYS = new Set(["auth_users", "auth_identities"]);

// Rows sent per database call, to stay under the request size limit.
const CHUNK = 1000;

// Primary key columns for tables not keyed on `id`, used by replace mode
// to list the rows to keep. Must match the real keys.
const KEY_COLUMNS: Record<string, string[]> = {
  role_permissions: ["role_id", "permission_id"],
  phases: ["code"],
};

/** Sends a JSON response with CORS headers. */
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}

/** Outcome of restoring one table. */
interface TableResult {
  attempted: number;
  restored: boolean;
  rowCount: number;
  error?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  // mode "merge" (default): add and overwrite, never delete.
  // mode "replace": also delete rows the backup lacks, so the system
  // matches it exactly. Refused for incremental backups, which would
  // delete nearly everything.
  let body: {
    storage_path?: string;
    tables?: Record<string, unknown[]>;
    mode?: string;
    backup_type?: string;
  } = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!body.storage_path && !body.tables) {
    return json({ error: "Provide either storage_path or tables" }, 400);
  }
  const replace = body.mode === "replace";

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Permission check runs as the caller, using the app's own RBAC data.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: allowed, error: permError } = await callerClient.rpc("has_permission", {
    p_module: "backup",
    p_action: "restore",
  });
  if (permError) {
    return json({ error: `Permission check failed: ${permError.message}` }, 500);
  }
  if (allowed !== true) {
    return json({ error: "You do not have permission to restore backups." }, 403);
  }

  let actorId: number | null = null;
  let actorAuthId: string | null = null;
  const { data: authUser } = await callerClient.auth.getUser();
  actorAuthId = authUser.user?.id ?? null;
  if (authUser.user) {
    const { data: userRow } = await callerClient
      .from("users")
      .select("id")
      .eq("supabase_uid", authUser.user.id)
      .maybeSingle();
    actorId = (userRow?.id as number | undefined) ?? null;
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  // Get the table data from Storage or from the request body.
  let tables: Record<string, unknown[]>;
  let backupType: string | null = null;
  let sourceLabel: string;
  if (body.storage_path) {
    const { data: file, error: downloadError } = await adminClient.storage
      .from("backups")
      .download(body.storage_path);
    if (downloadError || !file) {
      return json({ error: `Could not read backup file: ${downloadError?.message ?? "not found"}` }, 404);
    }
    try {
      const parsed = JSON.parse(await file.text());
      tables = (parsed.tables ?? {}) as Record<string, unknown[]>;
      backupType = typeof parsed.backup_type === "string" ? parsed.backup_type : null;
    } catch (e) {
      return json({ error: `Backup file is not valid JSON: ${e}` }, 400);
    }
    sourceLabel = body.storage_path;
  } else {
    tables = body.tables!;
    sourceLabel = "uploaded file";
    backupType = typeof body.backup_type === "string" ? body.backup_type : null;
  }

  // Writes one table through restore_backup_table(), not a plain upsert:
  // identity columns refuse stored ids and validation triggers reject old
  // rows. The function upserts with triggers paused.
  async function restoreTable(table: string): Promise<TableResult> {
    const rows = tables[table];
    if (!Array.isArray(rows) || rows.length === 0) {
      return { attempted: 0, restored: true, rowCount: 0 };
    }
    let written = 0;
    for (let i = 0; i < rows.length; i += CHUNK) {
      const { data, error } = await adminClient.rpc("restore_backup_table", {
        p_table: table,
        p_rows: rows.slice(i, i + CHUNK),
      });
      if (error) {
        return { attempted: rows.length, restored: false, rowCount: written, error: error.message };
      }
      written += (data as number | null) ?? 0;
    }
    return { attempted: rows.length, restored: true, rowCount: written };
  }

  const results: Record<string, TableResult> = {};
  const dumpedTables = Object.keys(tables).filter((t) => !DROPPED_TABLES.has(t) && !AUTH_KEYS.has(t));
  // Tables not in RESTORE_ORDER are restored last.
  const orderedTables = [
    ...RESTORE_ORDER.filter((t) => dumpedTables.includes(t)),
    ...dumpedTables.filter((t) => !RESTORE_ORDER.includes(t)),
  ];

  if (replace && backupType !== "full") {
    return json({
      error: "Replace needs a FULL backup. This file is " +
        (backupType ? `an ${backupType} backup` : "not marked as a full backup") +
        ", so making the system match it would delete records it simply does not carry. Use Merge instead.",
    }, 400);
  }

  // Sign-in accounts first. Backups without auth keys leave logins untouched.
  const authUsers = Array.isArray(tables["auth_users"]) ? tables["auth_users"] : null;
  const authIdentities = Array.isArray(tables["auth_identities"]) ? tables["auth_identities"] : [];
  if (authUsers) {
    let written = 0;
    let authErr: string | null = null;
    for (let i = 0; i < authUsers.length && !authErr; i += CHUNK) {
      const { data, error } = await adminClient.rpc("restore_auth_accounts", {
        p_users: authUsers.slice(i, i + CHUNK), p_identities: [],
      });
      if (error) authErr = error.message;
      else written += Number((data as Record<string, number> | null)?.users ?? 0);
    }
    for (let i = 0; i < authIdentities.length && !authErr; i += CHUNK) {
      const { error } = await adminClient.rpc("restore_auth_accounts", {
        p_users: [], p_identities: authIdentities.slice(i, i + CHUNK),
      });
      if (error) authErr = error.message;
    }
    results["sign-in accounts"] = authErr
      ? { attempted: authUsers.length, restored: false, rowCount: written, error: authErr }
      : { attempted: authUsers.length, restored: true, rowCount: written };
  }

  const retryQueue: string[] = [];
  // Names of tables that have failed so far.
  const failedTables0 = () =>
    Object.entries(results).filter(([, r]) => !r.restored).map(([t]) => t);
  for (const table of orderedTables) {
    const result = await restoreTable(table);
    results[table] = result;
    if (!result.restored) retryQueue.push(table);
  }

  // Second pass for tables that failed, probably on a missing dependency.
  for (const table of retryQueue) {
    const result = await restoreTable(table);
    results[table] = result;
  }

  // Replace: delete rows the backup lacks. Tables the file does not list
  // are left alone.
  const pruned: Record<string, number> = {};
  if (replace && failedTables0().length === 0) {
    for (const table of orderedTables) {
      const rows = tables[table];
      if (!Array.isArray(rows)) continue;
      const keyCols = KEY_COLUMNS[table] ?? ["id"];
      const keys = rows.map((r) => {
        const o: Record<string, unknown> = {};
        for (const c of keyCols) o[c] = (r as Record<string, unknown>)[c];
        return o;
      });
      const { data, error } = await adminClient.rpc("prune_backup_table", {
        p_table: table,
        p_keys: keys,
        p_keep_user: actorId,
      });
      if (error) {
        results[table] = { ...results[table], restored: false, error: `Could not remove extra rows: ${error.message}` };
      } else {
        pruned[table] = (data as number | null) ?? 0;
      }
    }
    // Remove logins the backup lacks, never the caller's own.
    if (authUsers) {
      const ids = authUsers.map((r) => (r as Record<string, unknown>).id);
      const { data, error } = await adminClient.rpc("prune_auth_accounts", {
        p_ids: ids, p_keep: actorAuthId,
      });
      if (error) {
        results["sign-in accounts"] = { ...results["sign-in accounts"], restored: false, error: `Could not remove extra logins: ${error.message}` };
      } else {
        pruned["sign-in accounts"] = (data as number | null) ?? 0;
      }
    }
  } else if (replace) {
    // A table failed, so nothing is deleted (avoids a half-restored system).
    results["(replace)"] = {
      attempted: 0, restored: false, rowCount: 0,
      error: "Extra rows were NOT removed because a table above failed to restore. Fix that and run it again.",
    };
  }

  // Move id sequences and reference counters past the restored rows so new
  // records do not collide with them.
  const { error: finishError } = await adminClient.rpc("finish_backup_restore");
  if (finishError) {
    results["(counters)"] = { attempted: 0, restored: false, rowCount: 0, error: finishError.message };
  }

  const totalRestored = Object.values(results).reduce((sum, r) => sum + r.rowCount, 0);
  const failedTables = Object.entries(results)
    .filter(([, r]) => !r.restored)
    .map(([t]) => t);

  if (actorId != null) {
    await adminClient.rpc("log_audit_event", {
      p_user_id: actorId,
      p_action: "restore",
      p_module: "backup",
      p_resource: "system_backups",
      p_resource_id: null,
      p_new_values: JSON.stringify({
        source: sourceLabel,
        mode: replace ? "replace" : "merge",
        total_restored: totalRestored,
        rows_removed: Object.values(pruned).reduce((a, b) => a + b, 0),
        failed_tables: failedTables,
        table_count: Object.keys(results).length,
      }),
      p_severity: failedTables.length > 0 ? "warning" : "info",
    });
  }

  return json({
    source: sourceLabel,
    mode: replace ? "replace" : "merge",
    total_restored: totalRestored,
    rows_removed: Object.values(pruned).reduce((a, b) => a + b, 0),
    pruned,
    results,
    failed_tables: failedTables,
  });
});
