import { ProviderRequestError } from "../../../lib/server/providers/errors";
import { assertBflPollingUrl } from "../../../lib/server/providers/bfl";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function safeFilename(value: string | null) {
  return (value || "clawnsole-video.mp4").replace(/[^a-zA-Z0-9._-]/g, "-");
}

export async function GET(request: Request) {
  try {
    const source = new URL(request.url).searchParams.get("url");
    if (!source) {
      return Response.json({ error: "A media URL is required." }, { status: 400 });
    }
    const url = assertBflPollingUrl(source);
    const range = request.headers.get("range");
    const response = await fetch(url, {
      headers: range ? { Range: range } : undefined,
      cache: "no-store",
    });
    if (!response.ok || !response.body) {
      return Response.json(
        { error: "This BFL delivery link is no longer available." },
        { status: response.status || 502 },
      );
    }

    const params = new URL(request.url).searchParams;
    const headers = new Headers();
    for (const name of ["content-type", "content-length", "content-range", "accept-ranges"]) {
      const value = response.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set("Cache-Control", "private, no-store");
    if (params.get("download") === "1") {
      headers.set("Content-Disposition", `attachment; filename="${safeFilename(params.get("filename"))}"`);
    }
    return new Response(response.body, { status: response.status, headers });
  } catch (error) {
    const status = error instanceof ProviderRequestError ? error.status : 500;
    return Response.json(
      { error: error instanceof Error ? error.message : "Media is unavailable." },
      { status },
    );
  }
}
