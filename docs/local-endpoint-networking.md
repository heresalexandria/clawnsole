# Local AI server connections

Enter the address of the AI server as reachable from the device running
Clawnsole. On a phone, `localhost` refers to the phone, not the computer running
the server. On Electron macOS, the companion makes the connection from the Mac.
For a server reached through Tailscale, connect both devices to the same tailnet
and use the server's tailnet address or a private Tailscale Serve HTTPS URL.
[Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) can expose
a local service to your tailnet. Clawnsole does not install or manage the VPN.

On iOS and macOS, allow Clawnsole's Local Network request when connecting to a
server on your LAN. If the first connection fails while the permission alert is
open, allow access and retry. If previously denied, enable Clawnsole in Settings
(System Settings on macOS) → Privacy & Security → Local Network. A VPN connection
may not trigger this LAN-specific permission.

## Platform implementation

The iOS app and packaged Electron app declare `NSLocalNetworkUsageDescription`.
Apple applies this permission to outgoing LAN connections even when they use
raw sockets. On macOS, connections made by the Dart companion are attributed to
the responsible app. The iOS Simulator does not exercise this permission; its
allow/deny behavior needs a physical-device check. See
[Apple's local network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

Local server requests use Dart HTTP sockets. Flutter's
[network policy guidance](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android)
distinguishes these from platform-native sockets, which enforce ATS or Android
cleartext policies. No broad ATS or Android cleartext exception is added.
Providers with local media outputs must likewise use a Dart download path and
be retained as assets before playback, rather than being handed to the
platform background downloader. The existing public-media client continues to
reject private network addresses.

The CI-pinned Flutter 3.47.0 targets Android SDK 36. Its existing `INTERNET`
permission permits LAN connections. When upgrading to target SDK 37 or later,
add and request `ACCESS_LOCAL_NETWORK` before local connections and handle
denial. Android explicitly advises against requesting it at lower target SDKs;
see [Android local network permissions](https://developer.android.com/privacy-and-security/local-network-permission).
