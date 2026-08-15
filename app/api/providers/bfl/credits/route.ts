import { getBflCredits } from "../../../../../lib/server/providers/bfl";
import { ProviderRequestError } from "../../../../../lib/server/providers/errors";
import { getBflApiKey } from "../../../../../lib/server/data-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

async function creditResponse(apiKey: string) {
  try {
    if (!apiKey) {
      return Response.json({ error: "An API key is required." }, { status: 400 });
    }
    return Response.json(await getBflCredits(apiKey), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    if (error instanceof ProviderRequestError) {
      return Response.json({ error: error.message }, { status: error.status });
    }
    return Response.json({ error: "The key could not be checked." }, { status: 500 });
  }
}

export async function GET() {
  return creditResponse(await getBflApiKey());
}

export async function POST(request: Request) {
  const body = (await request.json()) as { apiKey?: string };
  return creditResponse(body.apiKey?.trim() || await getBflApiKey());
}
