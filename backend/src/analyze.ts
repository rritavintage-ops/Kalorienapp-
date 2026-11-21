import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt";
import { type MealAnalysis, MealAnalysisSchema, type SupportedMediaType } from "./schema";

export const DEFAULT_MODEL = "claude-opus-5-5";
export const DEFAULT_EFFORT: Effort = "medium";
const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
export type Effort = (typeof EFFORTS)[number];

export interface AnalyzeInput {
  imageBase64: string;
  mediaType: SupportedMediaType;
  locale?: string | null;
  note?: string | null;
}

export interface MealAnalyzer {
  analyze(input: AnalyzeInput): Promise<MealAnalysis>;
}

export type AnalyzerErrorKind = "refused" | "rate_limited" | "upstream" | "invalid_output" | "misconfigured";

export class AnalyzerError extends Error {
  constructor(
    readonly kind: AnalyzerErrorKind,
    message: string,
  ) {
    super(message);
    this.name = "AnalyzerError";
  }
}

export function parseEffort(value: string | undefined): Effort {
  return (EFFORTS as readonly string[]).includes(value ?? "") ? (value as Effort) : DEFAULT_EFFORT;
}

/** The subset of the SDK client used here, so tests can pass a fake. */
export type ClaudeClient = Pick<Anthropic, "beta">;

export interface ClaudeAnalyzerOptions {
  client: ClaudeClient;
  model?: string;
  effort?: Effort;
}

/** Estimates foods, portions and nutrients from a meal photo with Claude vision + structured outputs. */
export function createClaudeAnalyzer(options: ClaudeAnalyzerOptions): MealAnalyzer {
  const model = options.model?.trim() || DEFAULT_MODEL;
  const effort = options.effort ?? DEFAULT_EFFORT;

  return {
    async analyze(input) {
      let response;
      try {
        response = await options.client.beta.messages.parse({
          model,
          max_tokens: 16000,
          // On a safety decline, the API retries on the recommended fallback model inside the same call.
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          output_config: {
            effort,
            format: betaZodOutputFormat(MealAnalysisSchema),
          },
          system: SYSTEM_PROMPT,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: { type: "base64", media_type: input.mediaType, data: input.imageBase64 },
                },
                { type: "text", text: buildUserPrompt(input.locale, input.note) },
              ],
            },
          ],
        });
      } catch (error) {
        throw toAnalyzerError(error);
      }

      if (response.stop_reason === "refusal") {
        throw new AnalyzerError("refused", "The model declined to analyze this image.");
      }
      if (response.stop_reason === "max_tokens" || !response.parsed_output) {
        throw new AnalyzerError("invalid_output", `Unusable model output (stop_reason: ${response.stop_reason ?? "unknown"}).`);
      }
      return response.parsed_output;
    },
  };
}

function toAnalyzerError(error: unknown): AnalyzerError {
  if (error instanceof AnalyzerError) return error;
  if (error instanceof Anthropic.RateLimitError) {
    return new AnalyzerError("rate_limited", "Upstream rate limit reached.");
  }
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    return new AnalyzerError("misconfigured", "The AI provider rejected the server's credentials.");
  }
  if (error instanceof Anthropic.BadRequestError) {
    return new AnalyzerError("upstream", "The AI provider rejected the request.");
  }
  if (error instanceof Anthropic.APIError) {
    return new AnalyzerError("upstream", `AI provider error (${error.status ?? "network"}).`);
  }
  if (error instanceof Anthropic.AnthropicError) {
    // Thrown by `.parse()` when the structured output does not match the schema.
    return new AnalyzerError("invalid_output", "The model output did not match the expected format.");
  }
  return new AnalyzerError("upstream", "Unexpected error while contacting the AI provider.");
}
