import { deleteGeneration, toPublicLocalState } from "../../../../lib/server/data-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function DELETE(request: Request) {
  try {
    const localId = new URL(request.url).searchParams.get("id");
    if (!localId) return Response.json({ error: "A generation id is required." }, { status: 400 });
    await deleteGeneration(localId);
    return Response.json(await toPublicLocalState());
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "The generation could not be removed." },
      { status: 500 },
    );
  }
}
