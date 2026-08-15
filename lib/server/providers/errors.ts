export class ProviderRequestError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "ProviderRequestError";
  }
}

export async function readProviderResponse(response: Response) {
  const contentType = response.headers.get("content-type") ?? "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : await response.text();

  if (!response.ok) {
    const fallback = response.status === 402
      ? "This BFL project does not have enough credits."
      : response.status === 401 || response.status === 403
        ? "BFL rejected this API key."
        : response.status === 429
          ? "BFL is at its active request limit. Try again shortly."
          : `BFL returned ${response.status}.`;
    const message =
      typeof payload === "object" && payload !== null && "detail" in payload
        ? String((payload as { detail: unknown }).detail)
        : fallback;
    throw new ProviderRequestError(message, response.status, payload);
  }

  return payload;
}
