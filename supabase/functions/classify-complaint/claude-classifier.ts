// Optional Claude classifier. It only runs when the ANTHROPIC_API_KEY secret
// is set; otherwise classifyWithClaude() returns null and index.ts falls back
// to the local Naive Bayes + VADER models. To turn it on, set the secret
// (no redeploy needed):
//   supabase secrets set ANTHROPIC_API_KEY=<your key> --project-ref <ref>

// Must match the app dropdown's category values (see training-data.ts).
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

/** The classifier's answer: category, priority, 0-1 confidence and a short reason. */
export interface ClaudeClassificationResult {
  category: string;
  priority: "low" | "medium" | "high" | "urgent";
  confidence: number;
  reasoning: string;
}

const SYSTEM_PROMPT = `You are a classifier for HOA (homeowners association) resident complaints.
Given a complaint's subject and description, respond with ONLY a JSON object (no markdown, no prose, no code fence) in this exact shape:
{"category": "<one of: ${CATEGORIES.join(", ")}>", "priority": "<one of: ${PRIORITIES.join(", ")}>", "confidence": <number 0-1>, "reasoning": "<one short sentence>"}
category is the best-fitting complaint type. priority reflects how urgently this needs officer attention: "urgent" for anything involving safety, injury, fire, weapons, or active danger; "high" for serious ongoing disruption; "medium" for a real but non-urgent issue; "low" for minor annoyances or suggestions.`;

/**
 * Classifies a complaint with Claude. Never throws: returns null when the key
 * is missing, the call fails or the reply is invalid, and the caller then
 * uses the local models.
 */
export async function classifyWithClaude(text: string): Promise<ClaudeClassificationResult | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return null;

  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 200,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: text.slice(0, 4000) }],
      }),
    });

    if (!res.ok) return null;

    const data = await res.json();
    const raw = data?.content?.[0]?.text;
    if (typeof raw !== "string") return null;

    // Strip a markdown code fence if one is added anyway.
    const cleaned = raw.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
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
      return null;
    }

    return {
      category: parsed.category,
      priority: parsed.priority as ClaudeClassificationResult["priority"],
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning : "",
    };
  } catch {
    return null;
  }
}
