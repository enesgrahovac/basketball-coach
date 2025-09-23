// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// Environment variables set via `supabase secrets set`.
const MODAL_ANALYZE_URL = Deno.env.get("MODAL_ANALYZE_URL");
const WORKER_AUTH_TOKEN = Deno.env.get("WORKER_AUTH_TOKEN");

if (!MODAL_ANALYZE_URL) {
  console.error("Missing env MODAL_ANALYZE_URL");
}
if (!WORKER_AUTH_TOKEN) {
  console.error("Missing env WORKER_AUTH_TOKEN");
}

serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.includes("application/json")) {
      return new Response(JSON.stringify({ error: "Expected application/json" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body = (await req.json()) as any;
    const clip_id = body?.clip_id as string | undefined;
    const storage_key = body?.storage_key as string | undefined;

    if (!clip_id || !storage_key) {
      return new Response(JSON.stringify({ error: "clip_id and storage_key are required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Optional: In future, verify the caller owns the clip via RLS-enabled client.
    // For MVP, we forward to the worker.

    const resp = await fetch(MODAL_ANALYZE_URL!, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ 
        clip_id, 
        storage_key,
        x_worker_auth: WORKER_AUTH_TOKEN
      }),
    });

    const data = await resp.json().catch(() => ({}));

    // Forward worker response and status code
    return new Response(JSON.stringify(data), {
      status: resp.status,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
