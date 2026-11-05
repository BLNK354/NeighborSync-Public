import { createClient } from "jsr:@supabase/supabase-js@2";

// Dumps the database tables to one JSON file in the private 'backups' bucket.
// Uses the service-role key, which must never reach the app.
//
// The whole backup fails if any listed table can't be dumped. Keep the lists
// below in step with the live schema, and redeploy this BEFORE a migration
// that drops a table.
//
// Left out on purpose: system_backups (restoring would erase the backup log)
// and login_sessions (rebuilt at next sign-in).
//
// A table with no created_at column must go in ALWAYS_FULL_TABLES, because
// incremental backups filter on that column.

// Needed so the browser allows the web app to call this function.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Always dumped in full, whatever the backup type.
const ALWAYS_FULL_TABLES = [
  "phases",
  "roles", "permissions", "role_permissions", "permit_types",
  "violation_types", "budget_categories", "system_settings",
  "waste_schedules", "blocks",
  "document_folders", "facilities", "payment_channels", "backup_settings",
];

// Dumped by date in incremental backups. updatedAt: true also catches edits
// (a database trigger keeps updated_at current).
const FILTERABLE_TABLES: Record<string, { updatedAt: boolean }> = {
  users: { updatedAt: true },
  lots: { updatedAt: true },
  announcements: { updatedAt: true },
  events: { updatedAt: true },
  bills: { updatedAt: true },
  payments: { updatedAt: true },
  payment_submissions: { updatedAt: true },
  budget_expenses: { updatedAt: true },
  complaints: { updatedAt: true },
  violations: { updatedAt: true },
  permits: { updatedAt: true },
  vehicles: { updatedAt: true },
  visitor_logs: { updatedAt: true },
  gate_passes: { updatedAt: true },
  move_requests: { updatedAt: true },
  household_members: { updatedAt: true },
  reservations: { updatedAt: true },
  security_incidents: { updatedAt: true },
  documents: { updatedAt: true },
  notifications: { updatedAt: true },
  personal_folders: { updatedAt: true },
  // Append-only: rows are never edited, so created_at alone is enough.
  audit_logs: { updatedAt: false },
};

const TABLES = [...ALWAYS_FULL_TABLES, ...Object.keys(FILTERABLE_TABLES)];

// Builds a JSON response with the CORS headers.
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}

// Reads the role claim from the token without checking its signature.
function jwtRole(authHeader: string): string | null {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const payloadB64 = token.split(".")[1];
    const normalized = payloadB64.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized));
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
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

  let body: { backup_type?: string; trigger?: string } = {};
  try {
    if (req.headers.get("Content-Type")?.includes("application/json")) {
      body = await req.json();
    }
  } catch {
    // No or invalid body: use the defaults below.
  }
  const backupType = body.backup_type === "incremental" ? "incremental" : "full";
  const isScheduled = body.trigger === "scheduled";

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const isServiceRoleCaller = jwtRole(authHeader) === "service_role";

  let createdBy: number | null = null;
  let triggerSource: "manual" | "scheduled" = "manual";

  if (isServiceRoleCaller) {
    triggerSource = isScheduled ? "scheduled" : "manual";
  } else {
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: allowed, error: permError } = await callerClient.rpc("has_permission", {
      p_module: "backup",
      p_action: "create",
    });
    if (permError) {
      return json({ error: `Permission check failed: ${permError.message}` }, 500);
    }
    if (allowed !== true) {
      return json({ error: "You do not have permission to create backups." }, 403);
    }
    const { data: authUser } = await callerClient.auth.getUser();
    if (authUser.user) {
      const { data: userRow } = await callerClient
        .from("users")
        .select("id")
        .eq("supabase_uid", authUser.user.id)
        .maybeSingle();
      createdBy = (userRow?.id as number | undefined) ?? null;
    }
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  let since: string | null = null;
  if (backupType === "incremental") {
    const { data: lastBackup } = await adminClient
      .from("system_backups")
      .select("created_at")
      .eq("destination", "supabase")
      .eq("status", "completed")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    since = (lastBackup?.created_at as string | undefined) ?? null;
  }
  const effectiveType = since ? backupType : "full";

  const dump: Record<string, unknown[]> = {};
  let rowCount = 0;
  for (const table of TABLES) {
    let query = adminClient.from(table).select("*");
    if (effectiveType === "incremental" && since && table in FILTERABLE_TABLES) {
      const hasUpdatedAt = FILTERABLE_TABLES[table].updatedAt;
      query = hasUpdatedAt
        ? query.or(`created_at.gte.${since},updated_at.gte.${since}`)
        : query.gte("created_at", since);
    }
    const { data, error } = await query;
    if (error) {
      return json({ error: `Failed dumping table "${table}": ${error.message}` }, 500);
    }
    dump[table] = data ?? [];
    rowCount += (data ?? []).length;
  }

  // Sign-in accounts, read through an RPC because the API can't see the auth
  // schema. Includes password hashes; one-time tokens are blanked and TOTP
  // secrets are left out.
  const { data: authDump, error: authError } = await adminClient.rpc("backup_auth_accounts", {
    p_since: effectiveType === "incremental" ? since : null,
  });
  if (authError) {
    return json({ error: `Failed dumping sign-in accounts: ${authError.message}` }, 500);
  }
  for (const key of ["auth_users", "auth_identities"]) {
    const rows = ((authDump as Record<string, unknown[]> | null)?.[key] ?? []) as unknown[];
    dump[key] = rows;
    rowCount += rows.length;
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const fileName = `backup_${effectiveType}_${timestamp}.json`;
  const storagePath = `${timestamp}/${fileName}`;
  const jsonBody = JSON.stringify({
    generated_at: new Date().toISOString(),
    backup_type: effectiveType,
    since,
    tables: dump,
  });
  const bytes = new TextEncoder().encode(jsonBody);

  const { error: uploadError } = await adminClient.storage
    .from("backups")
    .upload(storagePath, bytes, { contentType: "application/json", upsert: false });

  if (uploadError) {
    await adminClient.from("system_backups").insert({
      destination: "supabase",
      file_name: fileName,
      status: "failed",
      error_message: uploadError.message,
      table_count: TABLES.length + 2,
      backup_type: effectiveType,
      since_timestamp: since,
      trigger_source: triggerSource,
      created_by: createdBy,
    });
    return json({ error: `Upload failed: ${uploadError.message}` }, 500);
  }

  const { data: logRow, error: logError } = await adminClient
    .from("system_backups")
    .insert({
      destination: "supabase",
      file_name: fileName,
      size_bytes: bytes.length,
      status: "completed",
      storage_path: storagePath,
      table_count: TABLES.length + 2,
      row_count: rowCount,
      backup_type: effectiveType,
      since_timestamp: since,
      trigger_source: triggerSource,
      created_by: createdBy,
    })
    .select()
    .single();

  if (logError) {
    return json({ error: `Backup file stored, but logging failed: ${logError.message}` }, 500);
  }

  return json({ backup: logRow });
});
