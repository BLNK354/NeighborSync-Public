// Local severity scorer for security incidents. Used when the Claude path
// is unavailable (see claude-severity.ts). Combines a keyword list with a
// base weight per incident type, then maps the score to one of the four
// values security_incidents.severity accepts.

export type Severity = "low" | "medium" | "high" | "critical";

// Starting score for each incident `type`; keywords below can raise it.
const TYPE_BASE: Record<string, number> = {
  fire: 3.0,
  medical: 2.6,
  theft: 2.2,
  accident: 1.8,
  trespassing: 1.6,
  vandalism: 1.4,
  disturbance: 1.0,
  other: 1.0,
};

// Danger words in English and Filipino, grouped by weight. Matched as
// substrings of the lowercased text, so one match can set the severity.
// Do not add these ambiguous words; they cause false alarms:
//   "patay" ("patay ang ilaw" = light is off), "banta" (inside "bantay"),
//   "saksak" (plugging in), "away" (inside "runaway"), "bomb" (inside
//   "bomba", a water pump). Use the specific forms listed instead.
const KEYWORDS: Array<{ words: string[]; weight: number }> = [
  // Critical — active danger to life
  {
    weight: 3.0,
    words: [
      "gun", "firearm", "shooting", "shot", "knife", "stabbing", "stabbed",
      "weapon", "armed", "bombing", "bomb threat", "pipe bomb",
      "explosion", "explosive", "hostage",
      "kidnap", "dead", "death", "died", "killed", "fatal", "life-threatening",
      "unconscious", "not breathing", "cardiac", "heart attack", "drowning",
      "arson", "abduction", "molest",
      // Filipino
      "baril", "sinaksak", "granada", "nasawi", "bangkay", "walang malay",
      "hindi humihinga", "atake sa puso", "nalunod", "nakuryente",
      "sunog", "nagliliyab",
    ],
  },
  // High — serious harm or crime in progress
  {
    weight: 2.0,
    words: [
      "assault", "attack", "attacked", "injury", "injured", "bleeding",
      "blood", "wound", "burglary", "break-in", "break in", "broke in",
      "robbery", "robbed", "threat", "threatened", "fight", "violence",
      "violent", "fire spreading", "smoke", "trapped", "collapse", "gas leak",
      "electrocution", "overdose", "burglar", "mugged", "mugging",
      // Filipino ("nakaw" and "nag-away" are in the medium tier)
      "holdap", "akyat bahay", "akyat-bahay", "snatcher",
      "snatching", "sugat", "dugo", "nagbanta", "bantaan", "pananakot",
      "rambulan", "suntukan", "usok", "amoy gas", "nagwawala",
      "binugbog", "aksidente",
    ],
  },
  // Medium — real problem, no immediate danger to life
  {
    weight: 1.2,
    words: [
      "vandalism", "vandalized", "graffiti", "damage", "damaged", "stolen",
      "theft", "suspicious", "prowler", "harassment", "harassing",
      "intruder", "broken window", "tampering", "minor accident", "dispute",
      // Filipino
      "sira", "basag", "pinsala", "kahina-hinala", "kahina hinala",
      "nakakahinala", "delikado", "takot", "droga", "lasing", "pasaway",
      "nawawala", "nakaw", "nag-away",
    ],
  },
  // Low — nuisance level
  {
    weight: 0.4,
    words: [
      "noise", "loud", "loitering", "littering", "parking", "complaint",
      "minor", "verbal", "argument", "smell", "pet", "dog barking",
      // Filipino
      "ingay", "istorbo", "basura", "tambay", "alitan", "sigawan", "reklamo",
    ],
  },
];

// Turns a numeric score into a severity level.
function bucket(score: number): Severity {
  if (score >= 3.0) return "critical";
  if (score >= 2.0) return "high";
  if (score >= 1.1) return "medium";
  return "low";
}

export interface LocalSeverityResult {
  severity: Severity;
  confidence: number;
  score: number;
  topSignal: string | null;
}

/**
 * Scores an incident's severity from its type and free text. Never throws.
 * `confidence` is a rough estimate based on distance from the bucket edge,
 * not a real probability.
 */
export function scoreSeverity(type: string, text: string): LocalSeverityResult {
  const t = (text ?? "").toLowerCase();
  let score = TYPE_BASE[(type ?? "").toLowerCase()] ?? 1.0;
  let topSignal: string | null = null;
  let topWeight = 0;

  for (const group of KEYWORDS) {
    for (const w of group.words) {
      if (t.includes(w)) {
        // The strongest word is the main signal; others add a smaller bump.
        if (group.weight > topWeight) {
          topWeight = group.weight;
          topSignal = w;
        }
        // Nuisance-tier words must not add to the score, or minor words
        // would push ordinary incidents up to "critical".
        if (group.weight >= 1.0) score += group.weight * 0.5;
      }
    }
  }

  // The strongest keyword wins, so one "gun" is critical even for a mild type.
  score = Math.max(score, topWeight);

  const severity = bucket(score);

  // Confidence: distance from the bucket's lower edge, kept within 0.4–0.95.
  const edges: Record<Severity, number> = { low: 0, medium: 1.1, high: 2.0, critical: 3.0 };
  const span = severity === "critical" ? 1.0 : (severity === "high" ? 0.9 : (severity === "medium" ? 0.9 : 1.1));
  const confidence = Math.max(0.4, Math.min(0.95, 0.55 + ((score - edges[severity]) / span) * 0.4));

  return { severity, confidence: Number(confidence.toFixed(3)), score, topSignal };
}
