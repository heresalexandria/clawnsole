# ComfyUI generation

Clawnsole can submit your own ComfyUI API workflows to a server on the same
computer, your LAN, or your Tailscale network. The same setup works from iOS,
Android, native Windows/Linux, and the Electron macOS app. Models, checkpoints,
custom nodes, GPU requirements, and workflow execution remain on that server.

Use a workflow that already runs successfully in your ComfyUI installation.
This includes an H3 or LTX workflow if your server has the necessary model and
nodes; Clawnsole does not install them or assume a particular graph. This is
the self-hosted ComfyUI API, not a separate Maestro or Comfy Cloud integration.

## Connect and import

1. Start ComfyUI. On the same computer, its usual URL is
   `http://127.0.0.1:8188`. From another device, use the server's LAN address or
   private Tailscale IP/MagicDNS name and configure ComfyUI's listening address
   and firewall to accept that connection. `localhost` on a phone means the
   phone, not your computer. Tailscale is optional for local/LAN access.
2. In ComfyUI, run the graph successfully, enable developer/API export options
   if needed, and export **API format** JSON. The editor format with top-level
   `nodes` and `links` is not executable through this API.
3. Replace the positive prompt input's text with `"{{prompt}}"`. Keep the
   surrounding JSON valid. It can also appear inside a longer text input,
   such as `"A cinematic scene: {{prompt}}"`.
4. In Clawnsole, open **Providers → ComfyUI → Configure server & workflows**.
   Enter the server URL, choose the video or image slot, and import or paste
   the JSON. Enter the JSON key of the final output node, for example `9`.
   This should be a `SaveImage`, `SaveVideo`, or compatible video node with
   output saving enabled. The node ID is not its display title.
5. Select **Test & save**, then select ComfyUI and the corresponding workflow
   in Create. You can configure both slots independently. Clearing one slot's
   JSON removes it when saved; **Remove connection** clears both settings.

The connection test validates the graph's structure/placeholders and contacts
`/system_stats`; it does not render or validate installed node/model names.
ComfyUI performs its normal graph validation on submission, and failures appear
in the generation's error message. Each graph is limited to 128 KB and cannot
embed media data URLs. Use local model nodes without embedded credentials.

## Map optional controls

Every graph input retains its exported value unless you deliberately replace
it with a supported placeholder. Numeric placeholders must occupy the entire
quoted JSON value; Clawnsole converts them to JSON integers before submission.

| Placeholder | Submitted value |
| --- | --- |
| `{{prompt}}` | The Create prompt, substituted as text |
| `{{seed}}` | The selected seed, or a fresh random seed |
| `{{width}}`, `{{height}}` | The selected long edge (768/1024 px) and aspect ratio, rounded to multiples of 64 px |
| `{{duration}}` | Selected duration in seconds |
| `{{fps}}` | 24 |
| `{{frames}}` | Selected seconds × 24 + 1 |

Check your model's dimension and frame-count constraints. These optional
conventions are suitable only when your graph accepts them. A graph may keep
its own fixed frame rate, dimensions, frame count, audio, sampler, and all other
settings; unmatched Create controls do not override them. This first version
accepts text prompts, not Clawnsole reference-image/video uploads.

For example, an LTX graph input for latent frame count can use
`"length": "{{frames}}"`, while its video output frame rate uses
`"frame_rate": "{{fps}}"`. Keep graph connections such as `["6", 0]` unchanged.
Do not add placeholders to node IDs, class names, or metadata.

## Results, recovery, and private access

Clawnsole submits `/prompt`, then polls `/history/{prompt_id}` and `/queue`.
It retains the first matching output from the chosen final node: PNG/JPEG/WebP
for an image slot, or MP4/WebM/MOV for video. Native `SaveVideo` outputs under
`images` and VideoHelperSuite outputs under `gifs` are supported. Preview nodes
and temporary outputs are ignored. Configure SaveVideo/VideoHelperSuite to save **MP4 with H.264 video** for
playback across iOS, Android, and desktop. Container support alone does not
guarantee every codec plays on every platform; WebM playback is particularly
platform-dependent.

Keep ComfyUI running until the result has been saved in Clawnsole. Accepted
jobs retain their original server URL, job ID, output node, and output type,
so changing connection settings or restarting Clawnsole does not redirect or
resubmit them. If ComfyUI restarts and loses its queue/history, Clawnsole reports
that the job is missing instead of leaving it pending forever. Downloaded media
remains available in the normal local/Drive asset store. Workflow JSON is stored
once in settings, not copied into generation history.

No API key is required or forwarded. ComfyUI's self-hosted API normally has no
authentication: use a trusted private network or Tailscale rather than exposing
the port to the public internet. Configure Tailscale on both the server and the
device running Clawnsole. See [local-network access](local-endpoint-networking.md)
for platform permission details. Private results are downloaded through the
configured provider transport and retained before playback; the general
public-media downloader remains restricted.

Protocol references: [ComfyUI server routes](https://docs.comfy.org/development/comfyui-server/comms_routes),
[API workflow export and submission](https://docs.comfy.org/development/api-development/quickstart),
and [ComfyUI server implementation](https://github.com/Comfy-Org/ComfyUI/blob/master/server.py).
