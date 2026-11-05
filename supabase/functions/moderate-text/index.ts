// "moderate-text" Edge Function.
//
// Asks Gemini (GEMINI_API_KEY) whether text about to be saved is offensive
// (English, Filipino or Taglish). The app calls this before saving a form
// and shows the reason if flagged.
//
// The database word list (public.contains_profanity, enforced by the
// trg_01_block_profanity triggers) still blocks the write either way. When
// Gemini is missing or fails, this falls back to that list.
//
// Body: { "text": "..." }  ->  { flagged: bool, reason: string|null, source }

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";

const SYSTEM_PROMPT =
  `You moderate text that residents and officers of a Philippine homeowners association type into forms (complaints, permits, visitor passes, notices).
They write in English, Filipino, or Taglish -- all normal.
Flag the text ONLY if it contains profanity, slurs, sexual content, or words aimed at insulting, mocking or harassing people (e.g. "putangina", "gago", "pakyu", "manigas kayo", "bobo kayo", "f*ck you").
Do NOT flag: honest complaints, even angry ones ("sobrang ingay ng kapitbahay, nakakainis na"); reports describing a threat or crime ("may nagbanta ng saksak"); ordinary words that merely contain a bad word inside them ("computation", "shiitake", "leche flan").
reason: one short sentence a resident can read, saying what to change. Write it in the same language the text is in. Empty when not flagged.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    flagged: { type: "BOOLEAN" },
    reason: { type: "STRING" },
  },
  required: ["flagged", "reason"],
  propertyOrdering: ["flagged", "reason"],
};

// Filters off: the default would refuse to read abusive text and the check
// would pass it.
const SAFETY_SETTINGS = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
];

// Builds a JSON response with CORS headers.
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// Returns Gemini's verdict, or null if it is unavailable or fails.
async function askGemini(
  text: string,
): Promise<{ flagged: boolean; reason: string } | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: "POST",
        // The form waits on this, so give up after 5 s and use the word list.
        signal: AbortSignal.timeout(5000),
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
          contents: [{ role: "user", parts: [{ text: text.slice(0, 4000) }] }],
          safetySettings: SAFETY_SETTINGS,
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
            temperature: 0,
            // Keep high: thinking tokens share it, and a low cap returns an
            // empty reply with no error.
            maxOutputTokens: 2048,
          },
        }),
      },
    );
    if (!res.ok) {
      console.error(`[moderate] ${MODEL} HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
      return null;
    }
    const data = await res.json();
    const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof raw !== "string") {
      console.error(`[moderate] no text, finishReason=${data?.candidates?.[0]?.finishReason}`);
      return null;
    }
    const parsed = JSON.parse(raw.replace(/^```(json)?|```$/g, "").trim());
    if (typeof parsed?.flagged !== "boolean") return null;
    return { flagged: parsed.flagged, reason: String(parsed.reason ?? "") };
  } catch (e) {
    console.error(`[moderate] ${e}`);
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const text = String(body?.text ?? "").trim();
    if (!text) return json({ flagged: false, reason: null, source: "empty" });

    const ai = await askGemini(text);
    if (ai) {
      return json({
        flagged: ai.flagged,
        reason: ai.flagged ? (ai.reason || null) : null,
        source: "gemini",
      });
    }

    // Fallback: the database word list, run as the caller.
    const caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
    );
    const { data, error } = await caller.rpc("contains_profanity", { p: text });
    if (error) {
      console.error(`[moderate] word list failed: ${error.message}`);
      return json({ flagged: false, reason: null, source: "unavailable" });
    }
    return json({
      flagged: data === true,
      reason: data === true ? "Please remove the offensive words before saving." : null,
      source: "word_list",
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
