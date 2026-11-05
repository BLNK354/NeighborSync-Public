// Estimates how urgent a complaint sounds from its wording.
// A small English + Filipino/Taglish version of VADER sentiment scoring: word
// scores, boosters ("very", "sobrang"), negation ("hindi maayos"), caps and
// exclamation marks. Not the full VADER package. Use scoreSentiment().

// Word scores from -4 (very negative) to +4 (very positive), VADER's scale.
const LEXICON: Record<string, number> = {
  // General negative
  bad: -2.0, terrible: -3.0, awful: -3.0, horrible: -3.4, worst: -3.4,
  angry: -2.4, furious: -3.2, upset: -1.8, annoyed: -1.6, annoying: -1.6,
  disgusting: -3.0, hate: -2.8, complain: -1.2, complaint: -0.8,
  problem: -1.2, issue: -0.8, broken: -1.8, damaged: -1.6, unsafe: -2.6,
  dangerous: -3.0, danger: -3.0, hazard: -2.8, illegal: -2.0,
  disturbing: -2.2, disturbance: -1.8, nuisance: -1.8, filthy: -2.2,
  dirty: -1.4, rude: -2.0, disrespectful: -2.2, unacceptable: -2.6,
  ignored: -1.8, neglected: -2.0, negligence: -2.4, careless: -1.8,
  // Intensified negative (HOA-complaint specific)
  emergency: -3.2, urgent: -2.8, immediately: -1.6, threat: -3.2,
  threatening: -3.0, attacked: -3.4, attack: -3.0, assault: -3.6,
  fire: -3.2, flooding: -2.6, flood: -2.6, leaking: -1.8, leak: -1.6,
  overflowing: -1.8, infestation: -2.4, robbery: -3.4, theft: -2.8,
  stolen: -2.6, stealing: -2.6, trespassing: -2.2, harassing: -3.0,
  harassment: -3.2, breakin: -3.0, injured: -3.0, injury: -2.8,
  bleeding: -3.2, unresponsive: -2.4, collapsed: -2.8, exposed: -1.6,
  malfunctioning: -1.6, unattended: -1.6, sleeping: -1.0,
  screaming: -2.2, shouting: -1.8, fighting: -2.6, fight: -2.2,
  scared: -2.4, afraid: -2.2, terrified: -3.2, panic: -2.8,
  // Everyday English complaint vocabulary
  loud: -1.6, noisy: -1.8, noise: -1.2, blaring: -2.2, banging: -1.6,
  yelling: -2.0, barking: -1.2, blocking: -1.4, blocked: -1.4,
  clogged: -1.6, stuck: -1.4, cracked: -1.4, flooded: -2.6, smelly: -1.8,
  stench: -2.2, stinks: -2.0, suspicious: -2.0, loitering: -1.6,
  trespass: -2.2, vandalism: -2.6, drunk: -1.8, aggressive: -2.4,
  bullying: -2.6, harass: -3.0, unauthorized: -1.6, violation: -1.8,
  violating: -1.8, abandoned: -1.4, overcharged: -1.8, wrong: -1.6,
  incorrect: -1.4, missing: -1.4, unpaid: -1.0, delayed: -1.2,
  refuses: -1.6, refused: -1.6, failed: -1.6, useless: -2.2,
  ridiculous: -2.2, frustrated: -2.0, frustrating: -2.0,
  disappointed: -2.0, worried: -1.8, repeatedly: -1.0,
  // General positive (mild dampening if a complaint mentions these)
  good: 1.9, great: 3.1, thanks: 2.0, thank: 2.0, appreciate: 2.2,
  please: 0.4, kindly: 0.6, resolved: 1.8, fixed: 1.6, suggestion: 0.6,
  suggest: 0.4, improve: 1.0, improvement: 1.0,

  // --- Filipino / Taglish ---------------------------------------------
  // Same -4..+4 scale as the English entries above.
  // Do not add "patay": it usually means "off" ("patay ang ilaw"), so scoring
  // it would flag broken streetlights as urgent.

  // Filipino negative -- general
  masama: -2.0, pangit: -2.0, mali: -1.6, problema: -1.2, reklamo: -1.2,
  galit: -2.4, nagagalit: -2.4, inis: -1.6, nakakainis: -2.0,
  bastos: -2.4, walanghiya: -2.8, pasaway: -2.0, iresponsable: -2.0,
  pabaya: -2.0, kapabayaan: -2.4, nakakaabala: -2.0, abala: -1.6,
  istorbo: -2.0, gulo: -2.2, magulo: -2.0, nanggugulo: -2.4,
  // Filipino negative -- condition / disrepair
  sira: -1.8, sirang: -1.8, nasira: -1.8, basag: -1.6, guho: -2.2,
  barado: -1.8, tumutulo: -1.4, tumatagas: -1.8, tagas: -1.6,
  baha: -2.6, bumabaha: -2.6, binaha: -2.6, marumi: -1.6, dumi: -1.4,
  mabaho: -2.0, baho: -1.8, kalat: -1.4, makalat: -1.6, nabubulok: -2.0,
  peste: -2.0, daga: -1.6, ipis: -1.4, lamok: -1.4, bulok: -2.0,
  // Filipino negative -- noise
  ingay: -1.8, maingay: -2.0, nakakabingi: -2.4, sigawan: -2.0,
  sumisigaw: -2.2, nagsisigawan: -2.2,
  // Filipino negative -- danger / urgency
  delikado: -2.8, mapanganib: -3.0, panganib: -2.8, sunog: -3.2,
  nasusunog: -3.2, aksidente: -2.8, sugatan: -3.0, sugat: -2.6,
  duguan: -3.2, dugo: -2.4, nahimatay: -2.8, himatay: -2.6,
  nakakatakot: -2.6, takot: -2.2, natatakot: -2.4, kinakabahan: -1.8,
  emerhensiya: -3.2, saklolo: -3.2, tulong: -1.2,
  // Filipino negative -- crime / violence
  nakaw: -2.6, ninakaw: -2.8, magnanakaw: -3.0, nakawan: -3.0,
  holdap: -3.4, snatcher: -3.0, sinaksak: -3.6, saksakan: -3.4,
  barilan: -3.6, baril: -3.2, kutsilyo: -2.8, patalim: -3.0,
  away: -2.4, nagaaway: -2.4, rambulan: -3.0, suntok: -2.6,
  banta: -3.0, nagbanta: -3.0, binabantaan: -3.0, pananakot: -3.0,
  droga: -3.0, lasing: -1.8, nanlaban: -2.4,
  // Filipino negative -- billing / obstruction
  singil: -0.6, multa: -1.2, kulang: -1.2, doble: -1.0,
  harang: -1.4, nakaharang: -1.6, hinaharangan: -1.6, sagabal: -1.6,
  // Filipino -- attempted wrongdoing
  nagtangka: -2.0, nagtangkang: -2.0, pinilit: -1.4, sapilitan: -2.0,
  // Filipino positive. Keep "maayos"/"gumagana" positive: they usually come
  // negated ("hindi maayos") and the negation step flips them negative.
  salamat: 2.0, mabuti: 1.9, maganda: 1.9, ayos: 1.4, okay: 1.2,
  naayos: 1.8, maayos: 1.4, gumagana: 1.2, umaandar: 1.0,
  mungkahi: 0.6, suhestiyon: 0.6, pakiusap: 0.4, paki: 0.4,
};

// Words that scale the score of the word right after them up or down.
// Keep these out of LEXICON, or the same word counts twice.
const BOOSTERS: Record<string, number> = {
  very: 0.29, extremely: 0.45, really: 0.25, so: 0.22, too: 0.2,
  completely: 0.35, totally: 0.3, absolutely: 0.35, constantly: 0.25,
  always: 0.2, still: 0.15, again: 0.15, seriously: 0.3,
  slightly: -0.25, somewhat: -0.2, barely: -0.35, kind: -0.2, sort: -0.2,
  // Filipino amplifiers
  sobra: 0.35, sobrang: 0.35, grabe: 0.4, grabeng: 0.4, napaka: 0.4,
  masyado: 0.3, masyadong: 0.3, talaga: 0.25, talagang: 0.25,
  todo: 0.3, ubod: 0.35, lubha: 0.35, lubhang: 0.35,
  lagi: 0.2, palagi: 0.2, parati: 0.2, laging: 0.2, palaging: 0.2,
  // Filipino dampeners
  medyo: -0.25, konti: -0.3, konting: -0.3, bahagya: -0.3,
  bahagyang: -0.3, parang: -0.2,
};

// Words that flip the score of a word up to two places after them.
const NEGATIONS = new Set([
  "not", "no", "never", "cannot", "cant", "can't", "won't", "wont",
  "didn't", "didnt", "doesn't", "doesnt", "isn't", "isnt", "wasn't", "wasnt",
  // Filipino negators -- "hindi maayos", "walang tubig", "di gumagana"
  "hindi", "di", "wala", "walang", "wala'y", "hindi'y", "ayaw", "huwag",
]);

// Safety words that make a complaint "urgent" however calmly it is worded.
// One match overrides the whole score, so entries must be unambiguous: use
// "sinaksak" (stabbed), not "saksak" (also plugging in), and never "patay".
const HARD_TRIGGERS = new Set([
  // English
  "fire", "gun", "weapon", "knife", "assault", "attacked", "attack",
  "robbery", "breakin", "bleeding", "unconscious", "collapsed",
  "unresponsive", "threatening", "threat", "emergency", "injured", "injury",
  "stabbed", "shooting", "gunshot", "gunshots", "explosion", "electrocuted",
  "drowning", "drowned", "choking", "overdose", "trapped",
  // Filipino
  "sunog", "nasusunog", "baril", "barilan", "sinaksak", "saksakan",
  "holdap", "duguan", "sugatan", "nahimatay", "aksidente", "banta",
  "binabantaan", "nagbanta", "emerhensiya", "saklolo", "rambulan",
]);

// --- Filipino affix handling -------------------------------------------
//
// When a word is not in LEXICON, strip its affixes and retry, so inflected
// forms still score ("nagnakaw" -> "nakaw"). Stripping can produce a root that
// means something else, so keep these rules:
//  - The exact lookup always wins; stemming only runs on a miss.
//  - Never strip "-y", or "bantay" (guard) becomes "banta" (threat).
//  - One prefix, infix, reduplication and suffix only; no recursion.
//  - Roots need at least four letters; shorter ones match by accident.
//  - HARD_TRIGGERS never match through the stemmer; a false stem would mark an
//    ordinary complaint urgent.
//  - No "ka-" or bare "i-" prefix: "ka" turns "kaway" (wave) into "away" (fight).

// Tried in order: a longer prefix must come before a shorter one it starts with.
const STEM_PREFIXES = [
  "nakakapang", "nakakapag", "nagpapa", "nakaka", "nagkaka",
  "napaka", "pinaka", "nagka", "nagpa", "pinag", "nagsi", "nagma",
  "naka", "nang", "mang", "pang", "nag", "mag", "nam", "nan",
  "mam", "man", "pag", "na", "ma", "in",
];

// Tried in order: "han"/"hin" must come before "an"/"in".
const STEM_SUFFIXES = ["han", "hin", "an", "in"];

/// Words that must never be stemmed. Empty for now; if a word gets a false
/// match, add it here rather than weakening the rules.
const NEVER_STEM = new Set<string>([]);

// Shortest root the stemmer will accept.
const MIN_ROOT = 4;

/// Drops one trailing affix. Also tried on its own, because the prefix step
/// can eat part of the root ("nakawin" becomes "kawin" instead of "nakaw").
function stripSuffix(word: string): string {
  for (const s of STEM_SUFFIXES) {
    if (word.endsWith(s) && word.length - s.length >= MIN_ROOT) {
      return word.slice(0, -s.length);
    }
  }
  return word;
}

/// Strips one layer of Filipino affixation. Returns null when nothing
/// applied or the result is too short to trust.
function stemFilipino(word: string): string | null {
  if (word.length < MIN_ROOT + 1 || NEVER_STEM.has(word)) return null;
  let w = word;

  for (const p of STEM_PREFIXES) {
    if (w.startsWith(p) && w.length - p.length >= MIN_ROOT) {
      w = w.slice(p.length);
      break; // longest-first, one layer only
    }
  }

  // -um- infix in second position: s-um-isira.
  if (w.length >= MIN_ROOT + 2 && w.slice(1, 3) === "um") {
    w = w[0] + w.slice(3);
  }

  // CV- or V- reduplication: babaha -> baha, sisira -> sira, aaway -> away.
  if (w.length >= MIN_ROOT + 2 && w.slice(0, 2) === w.slice(2, 4)) {
    w = w.slice(2);
  } else if (w.length >= MIN_ROOT + 1 && w[0] === w[1]) {
    w = w.slice(1);
  }

  w = stripSuffix(w);

  return w !== word && w.length >= MIN_ROOT ? w : null;
}

/// Looks up a word's score: exact first, then at most two stemming attempts.
/// Returns undefined when the word has no score. A stemmed form must land on a
/// word already in LEXICON, so stemming cannot invent a score.
function valenceOf(word: string): number | undefined {
  const direct = LEXICON[word];
  if (direct !== undefined) return direct;
  if (NEVER_STEM.has(word)) return undefined;

  const suffixOnly = stripSuffix(word);
  if (suffixOnly !== word && LEXICON[suffixOnly] !== undefined) {
    return LEXICON[suffixOnly];
  }

  const root = stemFilipino(word);
  return root === null ? undefined : LEXICON[root];
}

function normalize(score: number, alpha = 15): number {
  // VADER's formula: keeps the score between -1 and 1 at any sentence length.
  return score / Math.sqrt(score * score + alpha);
}

/** What scoreSentiment returns. triggeredHardWord is the first hard trigger found. */
export interface SentimentResult {
  compound: number; // -1 (extremely alarming) to +1 (calm/positive)
  priority: "low" | "medium" | "high" | "urgent";
  triggeredHardWord: string | null;
}

/** Scores a complaint's text and turns it into a priority. A hard trigger word is always "urgent". */
export function scoreSentiment(text: string): SentimentResult {
  const rawWords = text.toLowerCase().replace(/[^a-z0-9'\s!]/g, " ").split(/\s+/).filter(Boolean);

  let total = 0;
  let hardTrigger: string | null = null;

  for (let i = 0; i < rawWords.length; i++) {
    const word = rawWords[i].replace(/'/g, "");
    if (HARD_TRIGGERS.has(word) && !hardTrigger) hardTrigger = word;

    // Exact match first, then Filipino stemming. The hard trigger check above
    // must stay on the exact word.
    let valence = valenceOf(word);
    if (valence === undefined) continue;

    // A booster right before this word scales it. Keep the booster's sign, or
    // dampeners would intensify and "slightly loud" would outrank "loud".
    const prevWord = i > 0 ? rawWords[i - 1].replace(/'/g, "") : null;
    if (prevWord && BOOSTERS[prevWord] !== undefined) {
      valence += Math.sign(valence) * BOOSTERS[prevWord] * 2.5;
    }

    // A negation in the previous 2 words flips the sign and dampens it, so
    // "not bad" is only mildly positive.
    const window = rawWords.slice(Math.max(0, i - 2), i).map((w) => w.replace(/'/g, ""));
    if (window.some((w) => NEGATIONS.has(w))) {
      valence *= -0.74;
    }

    total += valence;
  }

  // ALL-CAPS words add a little emphasis, counting at most three.
  const original = text.split(/\s+/);
  const capsWords = original.filter((w) => w.length > 2 && w === w.toUpperCase() && /[A-Z]/.test(w));
  if (capsWords.length > 0) total += Math.sign(total) * 0.4 * Math.min(capsWords.length, 3);

  // Exclamation marks add emphasis too, counting at most four.
  const exclaims = Math.min((text.match(/!/g) ?? []).length, 4);
  total += Math.sign(total) * 0.292 * exclaims;

  const compound = normalize(total);

  let priority: SentimentResult["priority"];
  if (hardTrigger || compound <= -0.75) priority = "urgent";
  else if (compound <= -0.4) priority = "high";
  else if (compound <= -0.05) priority = "medium";
  else priority = "low";

  return { compound, priority, triggeredHardWord: hardTrigger };
}
