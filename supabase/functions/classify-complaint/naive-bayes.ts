// A small Naive Bayes text classifier with no library. It trains in memory
// from training-data.ts on each cold start.
//
// It counts how often each word appears per category, then scores new text
// by how likely its words are in each category (unseen words are smoothed)
// and picks the highest.

// Common English and Filipino filler words, ignored when counting.
const STOPWORDS = new Set([
  // English
  "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
  "and", "or", "but", "if", "so", "to", "of", "in", "on", "at", "by",
  "for", "with", "about", "as", "it", "its", "this", "that", "these",
  "those", "i", "my", "we", "our", "you", "your", "he", "she", "they",
  "them", "their", "there", "here", "has", "have", "had", "do", "does",
  "did", "not", "no", "yes", "please", "can", "could", "would", "should",
  // Generic words that say nothing about the category.
  "someone", "somebody", "anyone", "everyone", "people", "person",
  "keeps", "keep", "get", "got", "also", "just", "very", "really",
  // Filipino / Taglish particles, pronouns and linkers
  "ang", "ng", "nang", "sa", "na", "ay", "mga", "po", "opo", "ho",
  "yung", "iyong", "ito", "iyan", "yan", "iyon", "yun", "dito", "diyan",
  "doon", "ako", "ko", "akin", "ka", "mo", "iyo", "siya", "niya", "kanya",
  "kami", "namin", "tayo", "natin", "kayo", "ninyo", "sila", "nila",
  "kanila", "at", "kung", "pero", "kasi", "dahil", "para", "may",
  "meron", "mayroon", "naman", "lang", "lamang", "din", "rin", "ba",
  "daw", "raw", "pa", "ni", "kay", "nga", "eh", "yata", "kaya", "kaysa",
  "tulad", "gaya", "isang", "isa",
]);

/** Lowercases text and splits it into words, dropping stopwords and 1-letter words. */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((w) => w.length > 1 && !STOPWORDS.has(w));
}

interface TrainedModel {
  categories: string[];
  priors: Record<string, number>;
  wordCounts: Record<string, Record<string, number>>;
  totalWordsInCategory: Record<string, number>;
  vocabSize: number;
}

/** Builds a model from `{ category: [example texts] }`. */
export function trainNaiveBayes(trainingData: Record<string, string[]>): TrainedModel {
  const categories = Object.keys(trainingData);
  const wordCounts: Record<string, Record<string, number>> = {};
  const totalWordsInCategory: Record<string, number> = {};
  const priors: Record<string, number> = {};
  const vocab = new Set<string>();

  const totalExamples = Object.values(trainingData).reduce((sum, arr) => sum + arr.length, 0);

  for (const category of categories) {
    const examples = trainingData[category];
    priors[category] = examples.length / totalExamples;
    wordCounts[category] = {};
    totalWordsInCategory[category] = 0;

    for (const example of examples) {
      for (const word of tokenize(example)) {
        vocab.add(word);
        wordCounts[category][word] = (wordCounts[category][word] ?? 0) + 1;
        totalWordsInCategory[category] += 1;
      }
    }
  }

  return { categories, priors, wordCounts, totalWordsInCategory, vocabSize: vocab.size };
}

export interface ClassificationResult {
  category: string;
  confidence: number; // 0-1, this category's share of the total probability
}

/** Classifies `text` against a model already trained by [trainNaiveBayes]. */
export function classify(model: TrainedModel, text: string): ClassificationResult {
  const words = tokenize(text);

  // Add logs instead of multiplying probabilities, which would underflow to 0.
  const logScores: Record<string, number> = {};
  for (const category of model.categories) {
    let logScore = Math.log(model.priors[category]);
    const denom = model.totalWordsInCategory[category] + model.vocabSize; // Laplace smoothing denominator
    for (const word of words) {
      const count = model.wordCounts[category][word] ?? 0;
      logScore += Math.log((count + 1) / denom); // +1 = Laplace smoothing numerator
    }
    logScores[category] = logScore;
  }

  // Turn scores into a 0-1 confidence; subtracting the max avoids overflow in Math.exp.
  const maxLog = Math.max(...Object.values(logScores));
  const expScores: Record<string, number> = {};
  let sumExp = 0;
  for (const category of model.categories) {
    expScores[category] = Math.exp(logScores[category] - maxLog);
    sumExp += expScores[category];
  }

  let bestCategory = model.categories[0];
  let bestConfidence = 0;
  for (const category of model.categories) {
    const confidence = expScores[category] / sumExp;
    if (confidence > bestConfidence) {
      bestCategory = category;
      bestConfidence = confidence;
    }
  }

  return { category: bestCategory, confidence: bestConfidence };
}
