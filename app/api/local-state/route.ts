import type { LocalPreferences } from "../../../lib/generations";
import {
  clearGenerationHistory,
  deleteLocalDataFile,
  readLocalData,
  resetPreferences,
  setBflApiKey,
  setPreferences,
  toPublicLocalState,
} from "../../../lib/server/data-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return Response.json(await toPublicLocalState(), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Local data is unavailable." },
      { status: 500 },
    );
  }
}

type LocalStateAction =
  | { action: "setApiKey"; value?: string }
  | { action: "setPreferences"; value?: Partial<LocalPreferences> }
  | { action: "clearHistory" }
  | { action: "clearPreferences" }
  | { action: "clearApiKey" }
  | { action: "clearAll" };

export async function PATCH(request: Request) {
  try {
    const body = (await request.json()) as LocalStateAction;
    if (body.action === "setApiKey") await setBflApiKey(body.value ?? "");
    else if (body.action === "setPreferences") await setPreferences(body.value ?? {});
    else if (body.action === "clearHistory") await clearGenerationHistory();
    else if (body.action === "clearPreferences") await resetPreferences();
    else if (body.action === "clearApiKey") await setBflApiKey("");
    else if (body.action === "clearAll") await deleteLocalDataFile();
    else return Response.json({ error: "Unknown local data action." }, { status: 400 });

    return Response.json(await toPublicLocalState(await readLocalData()));
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Local data could not be updated." },
      { status: 500 },
    );
  }
}
