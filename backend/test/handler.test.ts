import { describe, expect, it, vi } from "vitest";
import { AnalyzerError, type AnalyzeInput, type MealAnalyzer } from "../src/analyze";
import { decodedSize, handleRequest, matchesMediaType, type RateLimiter, safeEqual, SCAN_PATH } from "../src/handler";
import { MAX_ITEMS, type MealAnalysis } from "../src/schema";

// A tiny but valid-looking JPEG payload (signature + padding).
const JPEG_BASE64 = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, ...new Array(120).fill(0x11)));
const PNG_BASE64 = btoa(String.fromCharCode(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...new Array(120).fill(0x22)));

const SAMPLE_ANALYSIS: MealAnalysis = {
  containsFood: true,
  mealName: "Chicken, rice and broccoli",
  items: [
    { name: "Grilled chicken breast", portion: "1 fillet", grams: 150, calories: 248, protein: 46.5, carbs: 0, fat: 5.4, confidence: "high" },
    { name: "White rice", portion: "1 cup", grams: 180.04, calories: 234.26, protein: 4.3, carbs: 51, fat: 0.5, confidence: "medium" },
  ],
  notes: "Cooking oil may add calories.",
};

function fakeAnalyzer(result: MealAnalysis | Error = SAMPLE_ANALYSIS) {
  const calls: AnalyzeInput[] = [];
  const analyzer: MealAnalyzer = {
    async analyze(input) {
      calls.push(input);
      if (result instanceof Error) throw result;
      return result;
    },
  };
  return { analyzer, calls };
}

function scanRequest(body: unknown, headers: Record<string, string> = {}): Request {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return new Request(`https://scan.example.com${SCAN_PATH}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: text,
  });
}

const validBody = { imageBase64: JPEG_BASE64, mediaType: "image/jpeg", locale: "de_DE", note: "no dressing" };

async function errorCode(response: Response): Promise<string> {
  const body = (await response.json()) as { error: { code: string } };
  return body.error.code;
}

describe("routing", () => {
  it("serves a health check", async () => {
    const response = await handleRequest(new Request("https://scan.example.com/health"), fakeAnalyzerConfig());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("returns 404 for unknown paths and 405 for wrong methods", async () => {
    expect((await handleRequest(new Request("https://scan.example.com/nope"), fakeAnalyzerConfig())).status).toBe(404);
    const get = await handleRequest(new Request(`https://scan.example.com${SCAN_PATH}`), fakeAnalyzerConfig());
    expect(get.status).toBe(405);
    expect(get.headers.get("allow")).toBe("POST");
  });
});

function fakeAnalyzerConfig() {
  return { analyzer: fakeAnalyzer().analyzer };
}

describe("meal scan", () => {
  it("analyzes a valid photo and returns normalized results", async () => {
    const { analyzer, calls } = fakeAnalyzer();
    const response = await handleRequest(scanRequest(validBody), { analyzer });

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
    const body = await response.json();
    expect(body).toEqual({
      containsFood: true,
      mealName: "Chicken, rice and broccoli",
      items: [
        { name: "Grilled chicken breast", portion: "1 fillet", grams: 150, calories: 248, protein: 46.5, carbs: 0, fat: 5.4, confidence: "high" },
        { name: "White rice", portion: "1 cup", grams: 180, calories: 234.3, protein: 4.3, carbs: 51, fat: 0.5, confidence: "medium" },
      ],
      notes: "Cooking oil may add calories.",
    });
    expect(calls).toEqual([{ imageBase64: JPEG_BASE64, mediaType: "image/jpeg", locale: "de_DE", note: "no dressing" }]);
  });

  it("accepts PNG and a request without locale or note", async () => {
    const { analyzer, calls } = fakeAnalyzer();
    const response = await handleRequest(scanRequest({ imageBase64: PNG_BASE64, mediaType: "image/png" }), { analyzer });
    expect(response.status).toBe(200);
    expect(calls[0]?.mediaType).toBe("image/png");
  });

  it("clamps, rounds, trims and caps model output", async () => {
    const messy: MealAnalysis = {
      containsFood: true,
      mealName: "  ",
      items: [
        { name: "  Sauce  ", portion: " ", grams: -5, calories: Number.NaN, protein: 1.26, carbs: 99999, fat: 2, confidence: "low" },
        { name: "   ", portion: null, grams: 10, calories: 10, protein: 0, carbs: 0, fat: 0, confidence: "low" },
        ...Array.from({ length: 30 }, (_, i) => ({
          name: `Item ${i}`, portion: null, grams: 10, calories: 10, protein: 1, carbs: 1, fat: 0, confidence: "medium" as const,
        })),
      ],
      notes: null,
    };
    const response = await handleRequest(scanRequest(validBody), { analyzer: fakeAnalyzer(messy).analyzer });
    const body = (await response.json()) as { mealName: string | null; items: Array<Record<string, unknown>> };
    expect(body.mealName).toBeNull();
    expect(body.items).toHaveLength(MAX_ITEMS);
    expect(body.items[0]).toEqual({ name: "Sauce", portion: null, grams: 0, calories: 0, protein: 1.3, carbs: 1000, fat: 2, confidence: "low" });
    expect(body.items.some((item) => item.name === "")).toBe(false);
  });

  it("reports no food when the model finds nothing", async () => {
    const notFood: MealAnalysis = { containsFood: false, mealName: null, items: [], notes: "This looks like a laptop." };
    const response = await handleRequest(scanRequest(validBody), { analyzer: fakeAnalyzer(notFood).analyzer });
    expect(await response.json()).toEqual({ containsFood: false, mealName: null, items: [], notes: "This looks like a laptop." });
  });
});

describe("request validation", () => {
  const { analyzer } = fakeAnalyzer();

  it("requires JSON", async () => {
    const response = await handleRequest(scanRequest("hello", { "content-type": "text/plain" }), { analyzer });
    expect(response.status).toBe(415);
  });

  it("rejects malformed JSON", async () => {
    const response = await handleRequest(scanRequest("{not json"), { analyzer });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("invalid_json");
  });

  it("rejects unsupported media types", async () => {
    const response = await handleRequest(scanRequest({ ...validBody, mediaType: "image/heic" }), { analyzer });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("invalid_request");
  });

  it("rejects data that is not base64", async () => {
    const response = await handleRequest(scanRequest({ ...validBody, imageBase64: "%%%%" + "a".repeat(100) }), { analyzer });
    expect(response.status).toBe(400);
  });

  it("rejects images whose bytes don't match the declared type", async () => {
    const response = await handleRequest(scanRequest({ ...validBody, mediaType: "image/png" }), { analyzer });
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("invalid_image");
  });

  it("rejects invalid locales and long notes", async () => {
    expect((await handleRequest(scanRequest({ ...validBody, locale: "<script>" }), { analyzer })).status).toBe(400);
    expect((await handleRequest(scanRequest({ ...validBody, note: "x".repeat(301) }), { analyzer })).status).toBe(400);
  });

  it("rejects oversized uploads before reading them", async () => {
    const response = await handleRequest(scanRequest(validBody, { "content-length": String(50 * 1024 * 1024) }), { analyzer });
    expect(response.status).toBe(413);
  });
});

describe("access control", () => {
  it("requires the client token when configured", async () => {
    const { analyzer, calls } = fakeAnalyzer();
    const config = { analyzer, clientToken: "s3cret-token" };
    expect((await handleRequest(scanRequest(validBody), config)).status).toBe(401);
    expect((await handleRequest(scanRequest(validBody, { authorization: "Bearer wrong" }), config)).status).toBe(401);
    expect((await handleRequest(scanRequest(validBody, { authorization: "Bearer s3cret-token" }), config)).status).toBe(200);
    expect(calls).toHaveLength(1);
  });

  it("rate limits per installation, falling back to IP", async () => {
    const keys: string[] = [];
    const limiter: RateLimiter = {
      async limit({ key }) {
        keys.push(key);
        return { success: keys.length <= 1 };
      },
    };
    const { analyzer } = fakeAnalyzer();
    const first = await handleRequest(scanRequest(validBody, { "x-installation-id": "7F1C2B9A-1111-2222-3333-444455556666" }), { analyzer, rateLimiter: limiter });
    const second = await handleRequest(scanRequest(validBody, { "cf-connecting-ip": "203.0.113.9", "x-installation-id": "bad id!" }), { analyzer, rateLimiter: limiter });
    expect(first.status).toBe(200);
    expect(second.status).toBe(429);
    expect(second.headers.get("retry-after")).toBe("60");
    expect(keys).toEqual(["install:7F1C2B9A-1111-2222-3333-444455556666", "ip:203.0.113.9"]);
  });
});

describe("upstream failures", () => {
  it.each([
    ["refused", 422, "analysis_refused"],
    ["rate_limited", 503, "busy"],
    ["invalid_output", 502, "invalid_output"],
    ["upstream", 502, "upstream_error"],
    ["misconfigured", 502, "upstream_error"],
  ] as const)("maps %s to %i", async (kind, status, code) => {
    const log = vi.fn();
    const response = await handleRequest(scanRequest(validBody), {
      analyzer: fakeAnalyzer(new AnalyzerError(kind, "boom")).analyzer,
      log,
    });
    expect(response.status).toBe(status);
    expect(await errorCode(response)).toBe(code);
    expect(log).toHaveBeenCalledWith("meal scan failed", { kind, message: "boom" });
    // The image never ends up in logs.
    expect(JSON.stringify(log.mock.calls)).not.toContain(JPEG_BASE64);
  });
});

describe("helpers", () => {
  it("compares tokens in constant time semantics", () => {
    expect(safeEqual("abc", "abc")).toBe(true);
    expect(safeEqual("abc", "abd")).toBe(false);
    expect(safeEqual("abc", "abcd")).toBe(false);
    expect(safeEqual("", "")).toBe(true);
  });

  it("detects image signatures", () => {
    expect(matchesMediaType(JPEG_BASE64, "image/jpeg")).toBe(true);
    expect(matchesMediaType(PNG_BASE64, "image/png")).toBe(true);
    expect(matchesMediaType(JPEG_BASE64, "image/webp")).toBe(false);
    const webp = btoa("RIFF\u0000\u0000\u0000\u0000WEBPVP8 " + "x".repeat(60));
    expect(matchesMediaType(webp, "image/webp")).toBe(true);
  });

  it("computes decoded size from base64", () => {
    expect(decodedSize(btoa("abcd"))).toBe(4);
    expect(decodedSize(btoa("abcde"))).toBe(5);
    expect(decodedSize(btoa("abcdef"))).toBe(6);
  });
});
