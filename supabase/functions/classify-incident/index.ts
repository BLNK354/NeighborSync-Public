// "classify-incident" Edge Function: suggests a severity for a security
// incident. Send { incident_id }. It tries Gemini, then Claude, then a
// local keyword scorer, and saves the suggestion plus which engine made it.
// The real `severity` is filled only if the reporter left it blank.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { scoreSeverity } from "./severity-lexicon.ts";
import { assessSeverityWithClaude } from "./claude-severity.ts";
import { assessSeverityWithGemini } from "./gemini-severity.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const incidentId = body.incident_id ?? body.id;
    if (!incidentId) {
      return new Response(JSON.stringify({ error: "incident_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Service role bypasses RLS; reporters may not have an UPDATE policy.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: incident, error: fetchError } = await supabase
      .from("security_incidents")
      .select("id, type, title, description, severity")
      .eq("id", incidentId)
      .maybeSingle();

    if (fetchError || !incident) {
      return new Response(JSON.stringify({ error: fetchError?.message ?? "Incident not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const text = `${incident.title ?? ""}. ${incident.description ?? ""}`.trim();

    // Order: Gemini, then Claude, then the keyword scorer. Each returns
    // null (not an error) when unavailable, so the next one runs.
    const prompt = `Type: ${incident.type ?? "other"}\n${text}`;
    const geminiResult = await assessSeverityWithGemini(prompt);
    const aiResult = geminiResult ?? await assessSeverityWithClaude(prompt);
    const aiSource = geminiResult ? "gemini" : (aiResult ? "claude" : null);

    let severity: string;
    let confidence: number;
    let source: string;

    if (aiResult) {
      severity = aiResult.severity;
      confidence = aiResult.confidence;
      source = aiSource!;
    } else {
      const local = scoreSeverity(incident.type ?? "other", text);
      severity = local.severity;
      confidence = local.confidence;
      source = "keyword";
    }

    // Never overwrite a severity a person chose; the suggestion is always saved.
    const currentSeverity = (incident.severity ?? "").toString().trim();
    const update: Record<string, unknown> = {
      suggested_severity: severity,
      severity_confidence: Number(confidence.toFixed(3)),
      classification_source: source,
      classified_at: new Date().toISOString(),
    };
    if (currentSeverity === "") {
      update.severity = severity;
    }

    const { error: updateError } = await supabase
      .from("security_incidents")
      .update(update)
      .eq("id", incidentId);

    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        suggested_severity: severity,
        severity_confidence: confidence,
        applied_to_severity: currentSeverity === "",
        source,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
