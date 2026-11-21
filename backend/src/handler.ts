import { AnalyzerError, type MealAnalyzer } from "./analyze";
import {
  type ErrorBody,
  MAX_BODY_BYTES,
  MAX_IMAGE_BYTES,
  MealScanRequestSchema,
  normalizeAnalysis,
  type SupportedMediaType,
} from "./schema";

export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface HandlerConfig {
  analyzer: MealAnalyzer;
  /** When set, requests must send `Authorization: Bearer <token>`. */
  clientToken?: string;
  rateLimiter?: RateLimiter;
  log?: (message: string, details?: Record<string, unknown>) => void;
}

export const SCAN_PATH = "/v1/meal-scans";

const BASE_HEADERS: Record<string, string> = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

function json(status: number, body: unknown, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, ...extraHeaders } });
}

function errorResponse(status: number, code: string, message: string, extraHeaders: Record<string, string> = {}): Response {
  const body: ErrorBody = { error: { code, message } };
  return json(status, body, extraHeaders);
}

/** Constant-time comparison so the token can't be guessed byte by byte from response timing. */
export function safeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

/** Checks that the decoded image starts with the signature of its declared type. */
export function matchesMediaType(imageBase64: string, mediaType: SupportedMediaType): boolean {
  let header: string;
  try {
    header = atob(imageBase64.slice(0, 16));
  } catch {
    return false;
  }
  const bytes = Array.from(header, (char) => char.charCodeAt(0));
  switch (mediaType) {
    case "image/jpeg":
      return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
    case "image/png":
      return bytes[0] === 0x89 && header.slice(1, 4) === "PNG";
    case "image/webp":
      return header.slice(0, 4) === "RIFF" && header.slice(8, 12) === "WEBP";
  }
}

export function decodedSize(imageBase64: string): number {
  const padding = imageBase64.endsWith("==") ? 2 : imageBase64.endsWith("=") ? 1 : 0;
  return Math.floor((imageBase64.length * 3) / 4) - padding;
}

function rateLimitKey(request: Request): string {
  const installation = request.headers.get("x-installation-id") ?? "";
  if (/^[A-Za-z0-9-]{8,64}$/.test(installation)) {
    return `install:${installation}`;
  }
  return `ip:${request.headers.get("cf-connecting-ip") ?? "unknown"}`;
}

export async function handleRequest(request: Request, config: HandlerConfig): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/health") {
    return request.method === "GET" ? json(200, { status: "ok" }) : errorResponse(405, "method_not_allowed", "Use GET.", { allow: "GET" });
  }
  if (url.pathname !== SCAN_PATH) {
    return errorResponse(404, "not_found", "Not found.");
  }
  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Use POST.", { allow: "POST" });
  }

  if (config.clientToken) {
    const authorization = request.headers.get("authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice("Bearer ".length).trim() : "";
    if (!safeEqual(token, config.clientToken)) {
      return errorResponse(401, "unauthorized", "Missing or invalid client token.");
    }
  }

  if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) {
    return errorResponse(415, "unsupported_media_type", "Send the request as application/json.");
  }
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (declaredLength > MAX_BODY_BYTES) {
    return errorResponse(413, "payload_too_large", "The photo is too large.");
  }

  if (config.rateLimiter) {
    const { success } = await config.rateLimiter.limit({ key: rateLimitKey(request) });
    if (!success) {
      return errorResponse(429, "rate_limited", "Too many scans. Please wait a minute and try again.", { "retry-after": "60" });
    }
  }

  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    return errorResponse(413, "payload_too_large", "The photo is too large.");
  }

  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    return errorResponse(400, "invalid_json", "The request body is not valid JSON.");
  }

  const parsed = MealScanRequestSchema.safeParse(payload);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const field = issue?.path.join(".") || "body";
    return errorResponse(400, "invalid_request", `${field}: ${issue?.message ?? "invalid value"}`);
  }
  const scan = parsed.data;

  if (decodedSize(scan.imageBase64) > MAX_IMAGE_BYTES) {
    return errorResponse(413, "payload_too_large", "The photo is too large.");
  }
  if (!matchesMediaType(scan.imageBase64, scan.mediaType)) {
    return errorResponse(400, "invalid_image", `The image is not a valid ${scan.mediaType} file.`);
  }

  try {
    const analysis = await config.analyzer.analyze({
      imageBase64: scan.imageBase64,
      mediaType: scan.mediaType,
      locale: scan.locale,
      note: scan.note,
    });
    return json(200, normalizeAnalysis(analysis));
  } catch (error) {
    // Never log the image or the user's note; only the failure category.
    const kind = error instanceof AnalyzerError ? error.kind : "unexpected";
    config.log?.("meal scan failed", { kind, message: error instanceof Error ? error.message : String(error) });
    switch (kind) {
      case "refused":
        return errorResponse(422, "analysis_refused", "This photo couldn't be analyzed. Please try a different photo or add the meal manually.");
      case "rate_limited":
        return errorResponse(503, "busy", "The scanner is busy right now. Please try again in a moment.", { "retry-after": "30" });
      case "invalid_output":
        return errorResponse(502, "invalid_output", "The analysis didn't come back in a usable form. Please try again.");
      default:
        return errorResponse(502, "upstream_error", "The scanner is unavailable right now. Please try again.");
    }
  }
}
