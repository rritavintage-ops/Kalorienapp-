import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { AnalyzerError, type ClaudeClient, createClaudeAnalyzer, DEFAULT_MODEL, parseEffort } from "../src/analyze";
import { SYSTEM_PROMPT } from "../src/prompt";
import type { MealAnalysis } from "../src/schema";

const ANALYSIS: MealAnalysis = {
  containsFood: true,
  mealName: "Porridge",
  items: [{ name: "Porridge", portion: "1 bowl", grams: 250, calories: 320, protein: 11, carbs: 54, fat: 6.5, confidence: "high" }],
  notes: null,
};

type ParseParams = Record<string, unknown> & {
  messages: Array<{ role: string; content: Array<Record<string, unknown>> }>;
  output_config: { effort: string; format: { type: string; schema: Record<string, unknown> } };
};

/** Minimal stand-in for the SDK client: records the request and returns a canned response. */
function fakeClient(respond: (params: ParseParams) => unknown) {
  const requests: ParseParams[] = [];
  const client = {
    beta: {
      messages: {
        parse: async (params: ParseParams) => {
          requests.push(params);
          return respond(params);
        },
      },
    },
  } as unknown as ClaudeClient;
  return { client, requests };
}

const input = { imageBase64: "aGVsbG8=", mediaType: "image/jpeg" as const, locale: "en-GB", note: "large portion" };

describe("createClaudeAnalyzer", () => {
  it("sends the photo to Claude with structured output and returns the parsed result", async () => {
    const { client, requests } = fakeClient(() => ({ stop_reason: "end_turn", parsed_output: ANALYSIS }));
    const result = await createClaudeAnalyzer({ client }).analyze(input);

    expect(result).toEqual(ANALYSIS);
    const request = requests[0]!;
    expect(request.model).toBe(DEFAULT_MODEL);
    expect(request.model).toBe("claude-opus-5-5");
    expect(request.fallbacks).toBe("default");
    expect(request.betas).toEqual(["server-side-fallback-2026-07-01"]);
    expect(request.system).toBe(SYSTEM_PROMPT);
    expect(request.output_config.effort).toBe("medium");
    expect(request.output_config.format.type).toBe("json_schema");
    expect(Object.keys(request.output_config.format.schema.properties as object)).toEqual(["containsFood", "mealName", "items", "notes"]);

    const [image, text] = request.messages[0]!.content;
    expect(image).toEqual({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: "aGVsbG8=" } });
    expect(text?.type).toBe("text");
    expect(text?.text).toContain("User locale: en-GB.");
    expect(text?.text).toContain('"large portion"');
  });

  it("uses the configured model and effort", async () => {
    const { client, requests } = fakeClient(() => ({ stop_reason: "end_turn", parsed_output: ANALYSIS }));
    await createClaudeAnalyzer({ client, model: "claude-sonnet-5-5", effort: "low" }).analyze(input);
    expect(requests[0]!.model).toBe("claude-sonnet-5-5");
    expect(requests[0]!.output_config.effort).toBe("low");
  });

  it("treats a refusal as a refused analysis", async () => {
    const { client } = fakeClient(() => ({ stop_reason: "refusal", parsed_output: null }));
    await expect(createClaudeAnalyzer({ client }).analyze(input)).rejects.toMatchObject({ kind: "refused" });
  });

  it("treats truncated or unparsable output as invalid", async () => {
    const truncated = fakeClient(() => ({ stop_reason: "max_tokens", parsed_output: null }));
    await expect(createClaudeAnalyzer({ client: truncated.client }).analyze(input)).rejects.toMatchObject({ kind: "invalid_output" });

    const schemaMismatch = fakeClient(() => {
      throw new Anthropic.AnthropicError("Failed to parse structured output");
    });
    await expect(createClaudeAnalyzer({ client: schemaMismatch.client }).analyze(input)).rejects.toMatchObject({ kind: "invalid_output" });
  });

  it("maps SDK errors to analyzer errors", async () => {
    const cases: Array<[Error, string]> = [
      [new Anthropic.RateLimitError(429, undefined, "slow down", new Headers()), "rate_limited"],
      [new Anthropic.AuthenticationError(401, undefined, "bad key", new Headers()), "misconfigured"],
      [new Anthropic.InternalServerError(529, undefined, "overloaded", new Headers()), "upstream"],
      [new Anthropic.APIConnectionError({ message: "offline" }), "upstream"],
      [new Error("weird"), "upstream"],
    ];
    for (const [error, kind] of cases) {
      const { client } = fakeClient(() => {
        throw error;
      });
      const failure = await createClaudeAnalyzer({ client }).analyze(input).catch((e: unknown) => e);
      expect(failure).toBeInstanceOf(AnalyzerError);
      expect((failure as AnalyzerError).kind).toBe(kind);
    }
  });
});

describe("parseEffort", () => {
  it("accepts known levels and falls back to medium", () => {
    expect(parseEffort("high")).toBe("high");
    expect(parseEffort(undefined)).toBe("medium");
    expect(parseEffort("turbo")).toBe("medium");
  });
});
