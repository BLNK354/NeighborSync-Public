// Optional Claude severity check. It only runs when the ANTHROPIC_API_KEY
// secret is set; otherwise it returns null and index.ts uses the keyword
// scorer in severity-lexicon.ts. Set the secret with:
//   supabase secrets set ANTHROPIC_API_KEY=<your key> --project-ref <project-ref>

const SEVERITIES = ["low", "medium", "high", "critical"] as const;

export interface ClaudeSeverityResult {
  severity: "low" | "medium" | "high" | "critical";
  confidence: number;
  reasoning: string;
}

const SYSTEM_PROMPT = `You assess the severity of security incidents reported in an HOA (homeowners association) community.
Given an incident's type, title and description, respond with ONLY a JSON object (no markdown, no prose, no code fence) in this exact shape:
{"severity": "<one of: ${SEVERITIES.join(", ")}>", "confidence": <number 0-1>, "reasoning": "<one short sentence>"}
severity reflects how serious and urgent the incident is:
"critical" = active danger to life (weapons, fire, serious injury, someone unconscious or not breathing, armed intruder).
"high" = serious crime or harm (assault, burglary in progress, injury, credible threats, gas leak).
"medium" = a real incident with property loss or damage but no immediate danger to a person (theft, vandalism, suspicious activity, trespassing).
"low" = nuisance-level (noise, loitering, minor disputes, parking).
This is a recommendation only; a human officer makes the final call.`;

/** Asks Claude to rate an incident. Never throws; returns null on any failure so the caller can fall back. */
export async function assessSeverityWithClaude(text: string): Promise<ClaudeSeverityResult | null> {
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

    const cleaned = raw.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
    const parsed = JSON.parse(cleaned);

    const severities: readonly string[] = SEVERITIES;
    if (
      typeof parsed.severity !== "string" ||
      !severities.includes(parsed.severity) ||
      typeof parsed.confidence !== "number"
    ) {
      return null;
    }

    return {
      severity: parsed.severity as ClaudeSeverityResult["severity"],
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      reasoning: typeof parsed.reasoning === "string" ? parsed.reasoning : "",
    };
  } catch {
    return null;
  }
}
