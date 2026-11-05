// Rates how serious a security incident is, using Gemini.
// index.ts tries GEMINI_API_KEY, then ANTHROPIC_API_KEY, then severity-lexicon.ts.
// To turn on: set the GEMINI_API_KEY secret in Supabase (Edge Functions -> Secrets).

const SEVERITIES = ["low", "medium", "high", "critical"] as const;

export interface GeminiSeverityResult {
  severity: "low" | "medium" | "high" | "critical";
  confidence: number;
  reasoning: string;
}

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";

const SYSTEM_PROMPT =
  `You assess the severity of security incidents reported in an HOA (homeowners association) community in the Philippines.
Guards and residents write in English, Filipino, or a mix of both (Taglish) -- treat all three as normal.
Given an incident's type, title and description, rate how serious and urgent it is.
"critical" = active danger to life (weapons, fire, serious injury, someone unconscious or not breathing, armed intruder).
"high" = serious crime or harm (assault, burglary in progress, injury, credible threats, gas leak).
"medium" = a real incident with property loss or damage but no immediate danger to a person (theft, vandalism, suspicious activity, trespassing).
"low" = nuisance-level (noise, loitering, minor disputes, parking).
confidence is your own certainty, 0 to 1.
reasoning is one short sentence.
This is a recommendation only; a human officer makes the final call.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    severity: { type: "STRING", enum: [...SEVERITIES] },
    confidence: { type: "NUMBER" },
    reasoning: { type: "STRING" },
  },
  required: ["severity", "confidence", "reasoning"],
  propertyOrdering: ["severity", "confidence", "reasoning"],
};

// Filters stay off on purpose: a block on violent wording would silently
// drop a critical incident to the keyword scorer.
const SAFETY_SETTINGS = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
];

/**
 * Returns null (never throws) if the key is missing, the call fails, or the
 * reply is blocked or unreadable; the caller then uses the next fallback.
 * The reason is logged.
 */
export async function assessSeverityWithGemini(
  text: string,
): Promise<GeminiSeverityResult | null> {
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
            // Thinking tokens count here; a tight cap gives an empty reply.
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

    const cleaned = raw.trim()
      .replace(/^```(?:json)?/i, "")
      .replace(/```$/, "")
      .trim();
    const parsed = JSON.parse(cleaned);

    const severities: readonly string[] = SEVERITIES;
    if (
      typeof parsed.severity !== "string" ||
      !severities.includes(parsed.severity) ||
      typeof parsed.confidence !== "number"
    ) {
      console.error(`[gemini] unexpected shape: ${cleaned.slice(0, 200)}`);
      return null;
    }

    return {
      severity: parsed.severity as GeminiSeverityResult["severity"],
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning : "",
    };
  } catch (e) {
    console.error(`[gemini] ${String(e)}`);
    return null;
  }
}
