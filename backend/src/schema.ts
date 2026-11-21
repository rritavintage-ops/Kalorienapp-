import { z } from "zod";

// Wire format shared with the iOS app (ios/Packages/CalorieCore/Sources/CalorieCore/MealScan.swift).

export const SUPPORTED_MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export type SupportedMediaType = (typeof SUPPORTED_MEDIA_TYPES)[number];

/** Claude accepts images up to 5 MB; base64 adds ~33 %. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const MAX_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;
/** Request body limit (base64 image + small JSON envelope). */
export const MAX_BODY_BYTES = MAX_BASE64_LENGTH + 16 * 1024;
export const MAX_ITEMS = 20;

export const MealScanRequestSchema = z.object({
  imageBase64: z
    .string()
    .min(64, "image is too small")
    .max(MAX_BASE64_LENGTH, "image is too large")
    .regex(/^[A-Za-z0-9+/]+={0,2}$/, "image must be base64 encoded"),
  mediaType: z.enum(SUPPORTED_MEDIA_TYPES),
  locale: z
    .string()
    .max(35)
    .regex(/^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$/, "invalid locale")
    .nullish(),
  note: z.string().max(300).nullish(),
});
export type MealScanRequest = z.infer<typeof MealScanRequestSchema>;

/**
 * Structured output requested from Claude. Kept free of numeric range constraints so
 * a slightly off estimate never fails parsing; values are normalized afterwards.
 */
export const MealAnalysisSchema = z.object({
  containsFood: z.boolean().describe("False when the photo shows no food or drink."),
  mealName: z.string().nullable().describe("Short name for the whole meal, e.g. 'Chicken with rice and broccoli'."),
  items: z
    .array(
      z.object({
        name: z.string().describe("Specific, concise food name in the user's language."),
        portion: z.string().nullable().describe("Human-readable portion, e.g. '1 fillet', '1 cup', '2 slices'."),
        grams: z.number().describe("Estimated weight of this portion in grams (1 ml counts as 1 g)."),
        calories: z.number().describe("Energy of this portion in kcal."),
        protein: z.number().describe("Protein in this portion, grams."),
        carbs: z.number().describe("Carbohydrates in this portion, grams."),
        fat: z.number().describe("Fat in this portion, grams."),
        confidence: z.enum(["low", "medium", "high"]),
      }),
    )
    .describe("One entry per distinct food or drink being eaten."),
  notes: z.string().nullable().describe("One or two short sentences on what the user should double-check, or null."),
});
export type MealAnalysis = z.infer<typeof MealAnalysisSchema>;

export interface ScannedFoodItem {
  name: string;
  portion: string | null;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  confidence: "low" | "medium" | "high";
}

export interface MealScanResponse {
  containsFood: boolean;
  mealName: string | null;
  items: ScannedFoodItem[];
  notes: string | null;
}

export interface ErrorBody {
  error: { code: string; message: string };
}

function cleanNumber(value: number, maximum: number): number {
  if (!Number.isFinite(value) || value < 0) return 0;
  return Math.round(Math.min(value, maximum) * 10) / 10;
}

function cleanText(value: string | null | undefined, maxLength: number): string | null {
  const trimmed = (value ?? "").replace(/\s+/g, " ").trim();
  return trimmed.length > 0 ? trimmed.slice(0, maxLength) : null;
}

/** Clamps and rounds the model output into the wire format. */
export function normalizeAnalysis(analysis: MealAnalysis): MealScanResponse {
  const items: ScannedFoodItem[] = [];
  for (const item of analysis.items) {
    const name = cleanText(item.name, 80);
    if (!name) continue;
    items.push({
      name,
      portion: cleanText(item.portion, 60),
      grams: cleanNumber(item.grams, 5000),
      calories: cleanNumber(item.calories, 10000),
      protein: cleanNumber(item.protein, 1000),
      carbs: cleanNumber(item.carbs, 1000),
      fat: cleanNumber(item.fat, 1000),
      confidence: item.confidence,
    });
    if (items.length >= MAX_ITEMS) break;
  }
  return {
    containsFood: analysis.containsFood && items.length > 0,
    mealName: cleanText(analysis.mealName, 80),
    items,
    notes: cleanText(analysis.notes, 400),
  };
}
