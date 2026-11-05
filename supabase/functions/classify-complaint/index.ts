// "classify-complaint" Edge Function.
//
// Given a complaint id, suggests a category and priority from the subject and
// description, then saves them on the complaint (suggested_* columns, plus
// priority itself). Tries Gemini, then Claude, then the local Naive Bayes +
// VADER models. classification_source records which one answered.
// An officer can change priority later; suggested_priority keeps the AI's
// original call so the change can be logged. category is never touched.
// To retrain the local model, add examples to training-data.ts and redeploy.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { trainNaiveBayes, classify } from "./naive-bayes.ts";
import { scoreSentiment } from "./vader.ts";
import { trainingData } from "./training-data.ts";
import { classifyWithClaude } from "./claude-classifier.ts";
import { classifyWithGemini } from "./gemini-classifier.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Trained once per cold start; the data is small, so it is fast.
const model = trainNaiveBayes(trainingData);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Callers send either {complaint_id} or {id}; accept both.
    const body = await req.json();
    const complaint_id = body.complaint_id ?? body.id;
    if (!complaint_id) {
      return new Response(JSON.stringify({ error: "complaint_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Service role bypasses RLS; residents have no UPDATE policy on complaints.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: complaint, error: fetchError } = await supabase
      .from("complaints")
      .select("id, subject, description")
      .eq("id", complaint_id)
      .maybeSingle();

    if (fetchError || !complaint) {
      return new Response(JSON.stringify({ error: fetchError?.message ?? "Complaint not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const text = `${complaint.subject ?? ""} ${complaint.description ?? ""}`.trim();

    // Order: Gemini, then Claude, then the local models below. Each returns
    // null (not an error) when its key is missing or the call fails.
    const geminiResult = await classifyWithGemini(text);
    const aiResult = geminiResult ?? await classifyWithClaude(text);
    const aiSource = geminiResult ? "gemini" : (aiResult ? "claude" : null);

    let suggestedCategory: string;
    let suggestedPriority: string;
    let confidence: number;
    let source: string;
    let sentimentCompound: number | null = null;
    let triggeredHardWord: string | null = null;

    if (aiResult) {
      suggestedCategory = aiResult.category;
      suggestedPriority = aiResult.priority;
      confidence = aiResult.confidence;
      source = aiSource!;
    } else {
      const categoryResult = classify(model, text);
      const sentimentResult = scoreSentiment(text);
      suggestedCategory = categoryResult.category;
      suggestedPriority = sentimentResult.priority;
      confidence = categoryResult.confidence;
      source = "naive_bayes+vader";
      sentimentCompound = sentimentResult.compound;
      triggeredHardWord = sentimentResult.triggeredHardWord;
    }

    // Sets both priority and suggested_priority; keep suggested_priority
    // unchanged later so an officer override can be detected.
    const { error: updateError } = await supabase
      .from("complaints")
      .update({
        priority: suggestedPriority,
        suggested_category: suggestedCategory,
        suggested_priority: suggestedPriority,
        classification_confidence: Number(confidence.toFixed(3)),
        classification_source: source,
        classified_at: new Date().toISOString(),
      })
      .eq("id", complaint_id);

    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        suggested_category: suggestedCategory,
        confidence,
        suggested_priority: suggestedPriority,
        sentiment_compound: sentimentCompound,
        triggered_hard_word: triggeredHardWord,
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
