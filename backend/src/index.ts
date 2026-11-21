import Anthropic from "@anthropic-ai/sdk";
import { createClaudeAnalyzer, parseEffort } from "./analyze";
import { handleRequest, type RateLimiter } from "./handler";

export interface Env {
  /** Secret: `wrangler secret put ANTHROPIC_API_KEY`. Lives only on the server. */
  ANTHROPIC_API_KEY?: string;
  /** Optional secret shared with the app (SCAN_API_CLIENT_TOKEN). */
  APP_CLIENT_TOKEN?: string;
  CLAUDE_MODEL?: string;
  CLAUDE_EFFORT?: string;
  RATE_LIMITER?: RateLimiter;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.ANTHROPIC_API_KEY) {
      console.error("ANTHROPIC_API_KEY is not configured");
      return new Response(JSON.stringify({ error: { code: "misconfigured", message: "The scanner is not configured." } }), {
        status: 503,
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }

    const analyzer = createClaudeAnalyzer({
      client: new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 2, timeout: 90_000 }),
      model: env.CLAUDE_MODEL,
      effort: parseEffort(env.CLAUDE_EFFORT),
    });

    return handleRequest(request, {
      analyzer,
      clientToken: env.APP_CLIENT_TOKEN || undefined,
      rateLimiter: env.RATE_LIMITER,
      log: (message, details) => console.warn(message, JSON.stringify(details ?? {})),
    });
  },
} satisfies ExportedHandler<Env>;
