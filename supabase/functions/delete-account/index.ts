// "delete-account" Edge Function: removes an account.
//
// Two outcomes, chosen automatically:
//   "deleted" -- no bills or payments, so the user row and personal data go.
//   "retired" -- the account has bills or payments. Those are kept with the
//                person's name so the books still reconcile; all other
//                personal data is cleared and the login is revoked.
//
// Checks, in order:
//   1. Caller holds users:delete (asked via has_permission, not a role list).
//   2. Caller can see the target under RLS, so phase isolation applies.
//   3. Not your own account; only a super_admin may delete a super_admin.
//
// Send { user_id, dry_run: true } to preview the result without changing anything.

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Admin = ReturnType<typeof createClient>;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json();
    const user_id = body?.user_id;
    // When true, only report what would happen and change nothing.
    const dryRun = body?.dry_run === true;

    if (!user_id) return json({ error: "user_id is required" }, 400);

    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user: authUser } } = await caller.auth.getUser();
    if (!authUser) return json({ error: "Not signed in" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: me } = await admin
      .from("users")
      .select("id")
      .eq("supabase_uid", authUser.id)
      .maybeSingle();

    // Check the permission, not a role name, so this follows the RBAC tables.
    // Runs with the caller's JWT, so it answers for whoever is asking.
    const { data: mayDelete, error: permErr } = await caller.rpc("has_permission", {
      p_module: "users",
      p_action: "delete",
    });
    if (permErr || mayDelete !== true) {
      return json({ error: "You don't have permission to delete accounts." }, 403);
    }
    if (me?.id === user_id) return json({ error: "You can't delete your own account." }, 400);

    // Must use the caller's client, not admin: admin skips RLS and would
    // let an officer delete another phase's account.
    const { data: target, error: tErr } = await caller
      .from("users")
      .select("id, supabase_uid, first_name, last_name, profile_photo_url, phase, roles(name)")
      .eq("id", user_id)
      .maybeSingle();
    if (tErr || !target) return json({ error: "Account not found." }, 404);
    // Only a Super Admin may remove another Super Admin.
    if ((target.roles as { name?: string } | null)?.name === "super_admin") {
      const { data: myRole } = await caller.rpc("current_role_name");
      if (myRole !== "super_admin") {
        return json({ error: "Only a Super Admin can delete a Super Admin account." }, 403);
      }
    }

    // ── Survey what's attached ───────────────────────────────────────────
    // Personal and case data, removed with the account. The confirmation
    // dialog shows these counts first.
    const personal = {
      household_members: await count(admin, "household_members", "resident_id", user_id),
      vehicles:          await count(admin, "vehicles", "user_id", user_id),
      gate_passes:       await count(admin, "gate_passes", "requested_by", user_id),
      move_requests:     await count(admin, "move_requests", "resident_id", user_id),
      documents:         await count(admin, "documents", "uploaded_by", user_id),
      complaints:        await count(admin, "complaints", "complainant_id", user_id),
      violations:        await count(admin, "violations", "reported_against", user_id),
      permits:           await count(admin, "permits", "applicant_id", user_id),
      notifications:     await count(admin, "notifications", "user_id", user_id),
    };

    // Money records. Only these force "retired" instead of "deleted".
    const retained = {
      bills:    await count(admin, "bills", "user_id", user_id),
      payments: await count(admin, "payments", "user_id", user_id),
    };
    const retainedTotal = Object.values(retained).reduce((a, b) => a + b, 0);
    const tenantsUnderThisLandlord = await count(admin, "users", "landlord_id", user_id);

    if (dryRun) {
      return json({
        ok: true,
        dry_run: true,
        mode: retainedTotal > 0 ? "retired" : "deleted",
        name: `${target.first_name ?? ""} ${target.last_name ?? ""}`.trim(),
        personal,
        retained,
        tenants_under_this_landlord: tenantsUnderThisLandlord,
      });
    }

    // ── 1. Revoke login first ────────────────────────────────────────────
    // Done first so a half-finished delete still cannot sign in.
    if (target.supabase_uid) {
      try { await admin.auth.admin.deleteUser(target.supabase_uid as string); } catch (_) { /* may already be gone */ }
    }

    // ── 2. Remove the account's own files from Storage ───────────────────
    // Files are not removed by foreign keys, so delete them explicitly.
    try {
      const { data: docs } = await admin
        .from("documents")
        .select("storage_path")
        .eq("uploaded_by", user_id);
      const paths = (docs ?? [])
        .map((d: { storage_path?: string }) => d.storage_path)
        .filter((p: string | undefined): p is string => !!p);
      if (paths.length) await admin.storage.from("documents").remove(paths);
    } catch (_) { /* best effort */ }

    try {
      const photo = target.profile_photo_url as string | null;
      if (photo && target.supabase_uid) {
        await admin.storage.from("avatars").remove([`${target.supabase_uid}/photo.jpg`]);
      }
    } catch (_) { /* best effort */ }

    // ── 3. Detach tenants pointing at this landlord ──────────────────────
    // users.landlord_id blocks the delete while it is still set.
    if (tenantsUnderThisLandlord > 0) {
      try {
        await admin.from("users")
          .update({ landlord_id: null, lease_end_date: null })
          .eq("landlord_id", user_id);
      } catch (_) { /* falls through to retire */ }
    }

    // ── 4. Clear everything personal ─────────────────────────────────────
    // Order matters: children before parents.
    await del(admin, "household_members", "resident_id", user_id);
    await del(admin, "vehicles", "user_id", user_id);
    await del(admin, "gate_passes", "requested_by", user_id);
    await del(admin, "move_requests", "resident_id", user_id);
    await del(admin, "documents", "uploaded_by", user_id);
    // Pointers on other people's rows are cleared, not deleted.
    await del(admin, "complaints", "complainant_id", user_id);
    await nullOut(admin, "complaints", "against_user_id", user_id);
    await nullOut(admin, "complaints", "assigned_to", user_id);
    await del(admin, "violations", "reported_against", user_id);
    await nullOut(admin, "violations", "reported_by", user_id);
    await del(admin, "permits", "applicant_id", user_id);
    await nullOut(admin, "permits", "reviewed_by", user_id);
    await nullOut(admin, "permits", "approved_by", user_id);
    await nullOut(admin, "gate_passes", "approved_by", user_id);
    await nullOut(admin, "move_requests", "reviewed_by", user_id);
    await nullOut(admin, "security_incidents", "assigned_to", user_id);
    await nullOut(admin, "visitor_logs", "logged_by", user_id);
    await nullOut(admin, "payments", "received_by", user_id);
    await nullOut(admin, "payments", "verified_by", user_id);
    await nullOut(admin, "bills", "created_by", user_id);
    await del(admin, "notifications", "user_id", user_id);
    await del(admin, "login_sessions", "user_id", user_id);
    await del(admin, "audit_logs", "user_id", user_id);

    // ── 5. Hard delete, or retire if HOA records still reference it ──────
    const delUser = await admin.from("users").delete().eq("id", user_id);
    let mode = "deleted";

    if (delUser.error) {
      // Keep the name so bills and payments stay attributable; clear the rest.
      const retire = await admin
        .from("users")
        .update({
          // first_name / last_name deliberately preserved.
          email: `deleted+${user_id}@deleted.invalid`, // NOT NULL, needs a unique value
          phone: null,
          address: null,
          middle_name: null,
          suffix: null,
          profile_photo_url: null,
          supabase_uid: null,
          landlord_id: null,
          lease_end_date: null,
          lot_id: null,
          requested_lot_id: null,
          preferences: null,
          notes: null,
          mfa_enabled: false,
          status: "inactive",
          deleted_at: new Date().toISOString(),
        })
        .eq("id", user_id);
      if (retire.error) {
        return json({ error: `Could not remove account: ${retire.error.message}` }, 500);
      }
      mode = "retired";
    }

    return json({ ok: true, mode, personal, retained });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

/** Counts rows in a table where the column equals the id. */
async function count(admin: Admin, table: string, col: string, id: unknown): Promise<number> {
  try {
    const { count: n } = await admin
      .from(table)
      .select("*", { count: "exact", head: true })
      .eq(col, id);
    return n ?? 0;
  } catch (_) {
    return 0; // table/column may not exist -- treat as nothing attached
  }
}

// Deletes matching rows. Errors are ignored so one missing table
// cannot stop the whole delete.
async function del(admin: Admin, table: string, col: string, id: unknown) {
  if (!col) return;
  try { await admin.from(table).delete().eq(col, id); } catch (_) { /* ignore */ }
}

// Clears this user's id from rows that belong to someone else; the row stays.
// If the column is NOT NULL it fails silently and the account is retired instead.
async function nullOut(admin: Admin, table: string, col: string, id: unknown) {
  try {
    await admin.from(table).update({ [col]: null }).eq(col, id);
  } catch (_) { /* ignore */ }
}

/** Builds a JSON response with the CORS headers. */
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
