// Classifies a complaint with Google Gemini.
//
// index.ts tries GEMINI_API_KEY, then ANTHROPIC_API_KEY, then the local
// Naive Bayes model. Each layer returns null on failure instead of throwing.
// Set GEMINI_API_KEY in Supabase Dashboard -> Edge Functions -> Secrets; it
// is read per request, so no redeploy is needed.

// Must match the complaint category values the app's dropdown sends.
const CATEGORIES = [
  "noise",
  "maintenance",
  "billing",
  "security",
  "parking",
  "pets",
  "sanitation",
  "common_area",
  "neighbor_dispute",
  "other",
] as const;

const PRIORITIES = ["low", "medium", "high", "urgent"] as const;

export interface GeminiClassificationResult {
  category: string;
  priority: "low" | "medium" | "high" | "urgent";
  confidence: number;
  reasoning: string;
}

// Model name. Set GEMINI_MODEL to override the default.
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";

const SYSTEM_PROMPT =
  `You are a classifier for HOA (homeowners association) resident complaints in the Philippines.
Residents write in English, Filipino, or a mix of both (Taglish) -- treat all three as normal.
Given a complaint's subject and description, decide its category and how urgently it needs officer attention.
category is the best-fitting complaint type. These four overlap, so read them carefully:
- "sanitation" = garbage, waste, uncollected trash, animal droppings, foul smell, drainage, pests, anything unhygienic. Filipino: basura, kalat, tae, dumi, baho, amoy, kanal, ipis, daga, lamok, langaw.
- "maintenance" = something built is broken or worn and needs repair -- a resident's own unit, a street light, a road, a leaking pipe. Filipino: sira, butas, tagas, baha, wasak.
- "common_area" = the shared amenities and facilities themselves: clubhouse, function hall, pool, court, playground, park, gate, guardhouse -- their condition, use, booking or upkeep.
- "pets" = an animal's behaviour or its owner's handling of it: stray, unleashed, biting, aggressive, mess left behind, unregistered. Filipino: aso, pusa, alagang hayop, gala, kagat, tumatahol.
Note a barking dog is "noise", not "pets" -- classify by the actual problem, not the object mentioned.
priority: "urgent" for anything involving safety, injury, fire, weapons, or active danger; "high" for serious ongoing disruption; "medium" for a real but non-urgent issue; "low" for minor annoyances or suggestions.
confidence is your own certainty, 0 to 1.
reasoning is one short sentence.`;

// Structured-output schema: the API limits category and priority to these
// enum values.
const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    category: { type: "STRING", enum: [...CATEGORIES] },
    priority: { type: "STRING", enum: [...PRIORITIES] },
    confidence: { type: "NUMBER" },
    reasoning: { type: "STRING" },
  },
  required: ["category", "priority", "confidence", "reasoning"],
  propertyOrdering: ["category", "priority", "confidence", "reasoning"],
};

// Safety filters are off: complaints describe threats, fights and fire, and a
// blocked response would drop a real emergency to the local scorer.
const SAFETY_SETTINGS = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
];

/**
 * Returns null (never throws) if GEMINI_API_KEY isn't set, the call fails,
 * the response is blocked, or it can't be parsed. The caller then falls back
 * to Claude and the local models. Failures are logged with the reason.
 */
export async function classifyWithGemini(
  text: string,
): Promise<GeminiClassificationResult | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
          contents: [{ role: "user", parts: [{ text: text.slice(0, 4000) }] }],
          safetySettings: SAFETY_SETTINGS,
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
            temperature: 0,
            // Keep this large: thinking tokens count toward it, and a small
            // cap returns an empty answer with no error.
            maxOutputTokens: 2048,
          },
        }),
      },
    );

    if (!res.ok) {
      console.error(
        `[gemini] ${MODEL} HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`,
      );
      return null;
    }

    const data = await res.json();

    // A prompt refused outright reports it here rather than as an HTTP error.
    const blocked = data?.promptFeedback?.blockReason;
    if (blocked) {
      console.error(`[gemini] prompt blocked: ${blocked}`);
      return null;
    }

    const candidate = data?.candidates?.[0];
    const raw = candidate?.content?.parts?.[0]?.text;
    if (typeof raw !== "string") {
      console.error(
        `[gemini] no text part, finishReason=${candidate?.finishReason}`,
      );
      return null;
    }

    // Strip markdown fences in case the model adds them anyway.
    const cleaned = raw.trim()
      .replace(/^```(?:json)?/i, "")
      .replace(/```$/, "")
      .trim();
    const parsed = JSON.parse(cleaned);

    const categories: readonly string[] = CATEGORIES;
    const priorities: readonly string[] = PRIORITIES;

    if (
      typeof parsed.category !== "string" ||
      !categories.includes(parsed.category) ||
      typeof parsed.priority !== "string" ||
      !priorities.includes(parsed.priority) ||
      typeof parsed.confidence !== "number"
    ) {
      console.error(`[gemini] unexpected shape: ${cleaned.slice(0, 200)}`);
      return null;
    }

    return {
      category: parsed.category,
      priority: parsed.priority as GeminiClassificationResult["priority"],
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning : "",
    };
  } catch (e) {
    console.error(`[gemini] ${String(e)}`);
    return null;
  }
}
