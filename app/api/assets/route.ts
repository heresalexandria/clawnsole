import { Readable } from "node:stream";
import { findLocalAsset, openLocalAsset, storeRemoteResult } from "../../../lib/server/asset-store";
import { readLocalData, updateGeneration } from "../../../lib/server/data-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function safeFilename(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]/g, "-") || "clawnsole-asset";
}

function parseRange(value: string | null, size: number) {
  const match = value?.match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return null;
  let start = match[1] ? Number(match[1]) : NaN;
  let end = match[2] ? Number(match[2]) : NaN;
  if (Number.isNaN(start) && Number.isFinite(end)) {
    start = Math.max(0, size - end);
    end = size - 1;
  } else {
    if (!Number.isFinite(start)) return null;
    if (!Number.isFinite(end)) end = size - 1;
  }
  if (start < 0 || end < start || start >= size) return null;
  return { start, end: Math.min(end, size - 1) };
}

export async function GET(request: Request) {
  try {
    const params = new URL(request.url).searchParams;
    const id = params.get("id") || "";
    const data = await readLocalData();
    const reference = findLocalAsset(data.generations, id);
    if (!reference) return Response.json({ error: "The local asset was not found." }, { status: 404 });

    const { filePath, file, createReadStream } = await openLocalAsset(id);
    const range = parseRange(request.headers.get("range"), file.size);
    const start = range?.start ?? 0;
    const end = range?.end ?? file.size - 1;
    const stream = createReadStream(filePath, { start, end });
    const headers = new Headers({
      "Accept-Ranges": "bytes",
      "Cache-Control": "private, no-store",
      "Content-Length": String(Math.max(0, end - start + 1)),
      "Content-Type": reference.contentType || "application/octet-stream",
      "X-Content-Type-Options": "nosniff",
    });
    if (range) headers.set("Content-Range", `bytes ${start}-${end}/${file.size}`);
    if (params.get("download") === "1") {
      headers.set("Content-Disposition", `attachment; filename="${safeFilename(reference.label)}"`);
    }
    return new Response(Readable.toWeb(stream) as ReadableStream, {
      status: range ? 206 : 200,
      headers,
    });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return Response.json({ error: "The local asset file is missing." }, { status: 404 });
    }
    return Response.json(
      { error: error instanceof Error ? error.message : "The local asset is unavailable." },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { localId?: string };
    if (!body.localId) return Response.json({ error: "A generation id is required." }, { status: 400 });
    const current = (await readLocalData()).generations.find((item) => item.localId === body.localId);
    if (!current) return Response.json({ error: "The generation was not found." }, { status: 404 });
    if (current.resultAsset) return Response.json({ generation: current });
    if (!current.resultUrl) {
      return Response.json({ error: "The BFL delivery link is no longer available." }, { status: 410 });
    }
    const resultAsset = await storeRemoteResult(
      current.resultUrl,
      `clawnsole-${current.localId.slice(0, 8)}.mp4`,
    );
    const generation = await updateGeneration(current.localId, (item) => ({
      ...item,
      resultAsset,
      deliveryExpired: false,
      updatedAt: new Date().toISOString(),
    }));
    return Response.json({ generation }, { status: 201 });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "The completed video could not be retained." },
      { status: 500 },
    );
  }
}
