// "admin-reset-password" Edge Function.
//
// Lets an officer email a password-reset link to a resident. The officer never
// sees a password; the resident picks their own from the link.
//
// It runs on the server because the link must not use PKCE. The request below
// sends no code_challenge, so the resident can open the link in any browser.
//
// Checks, in order:
//   1. caller has users:update (via has_permission, not a role list)
//   2. caller can see the target under RLS (looked up with the caller's client)
//   3. target has a login (roster rows have supabase_uid null)
//   4. not your own account (Profile > Change Password handles that)
//   5. only a super_admin may reset a super_admin

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json().catch(() => ({}));
    const user_id = body?.user_id;

    // Where the emailed link lands. Not trusted here: Supabase checks it
    // against the Redirect URLs allow-list.
    const redirectTo = typeof body?.redirect_to === "string" ? body.redirect_to : "";

    if (!user_id) return json({ error: "user_id is required" }, 400);

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user: authUser } } = await caller.auth.getUser();
    if (!authUser) return json({ error: "Not signed in" }, 401);

    // Guard 1: check the permission, not the role name.
    const { data: mayUpdate, error: permErr } = await caller.rpc("has_permission", {
      p_module: "users",
      p_action: "update",
    });
    if (permErr || mayUpdate !== true) {
      return json({ error: "You don't have permission to reset account passwords." }, 403);
    }

    // Guard 2: RLS limits what the officer can see. Hidden and missing rows
    // give the same "not found" so other phases' ids are not revealed.
    const { data: target, error: tErr } = await caller
      .from("users")
      .select("id, email, supabase_uid, first_name, last_name, roles(name)")
      .eq("id", user_id)
      .maybeSingle();
    if (tErr || !target) return json({ error: "Account not found." }, 404);

    // Guard 3: a roster record has no login to reset.
    if (!target.supabase_uid) {
      return json({
        error:
          "This account has no login yet. It came from a roster import, and the " +
          "homeowner claims it by registering with this same email address.",
      }, 400);
    }
    if (!target.email) {
      return json({ error: "This account has no email address on record." }, 400);
    }

    // Guard 4: your own password is not reset from here.
    const { data: me } = await caller
      .from("users")
      .select("id, roles(name)")
      .eq("supabase_uid", authUser.id)
      .maybeSingle();
    if (me?.id === target.id) {
      return json({
        error: "Use Profile > Change Password for your own account. It asks for your current password.",
      }, 400);
    }

    // Guard 5: only a super_admin may reset a super_admin.
    const targetRole = (target.roles as { name?: string } | null)?.name;
    const callerRole = (me?.roles as { name?: string } | null)?.name;
    if (targetRole === "super_admin" && callerRole !== "super_admin") {
      return json({ error: "Only the system administrator can reset a Super Admin password." }, 403);
    }

    // Send it. Call the REST endpoint directly; no code_challenge means no
    // PKCE, so the resident's browser can use the link.
    const url = new URL(`${SUPABASE_URL}/auth/v1/recover`);
    if (redirectTo) url.searchParams.set("redirect_to", redirectTo);

    const res = await fetch(url.toString(), {
      method: "POST",
      headers: {
        "apikey": ANON_KEY,
        "Authorization": `Bearer ${ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email: target.email }),
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      // 429 means one reset per address per minute; say so plainly.
      if (res.status === 429) {
        return json({
          error: "A reset email was already sent to this address in the last minute. Wait a moment and try again.",
        }, 429);
      }
      return json({ error: `Supabase refused the reset request (${res.status}). ${detail}`.trim() }, 502);
    }

    const name = [target.first_name, target.last_name]
      .filter((s) => s && String(s).length > 0)
      .join(" ");

    return json({ ok: true, email: target.email, name: name.length > 0 ? name : null });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

/** Builds a JSON response with CORS headers. */
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
