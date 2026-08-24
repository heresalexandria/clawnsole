# Clawnsole privacy policy

Effective: August 20, 2026

Clawnsole is a unified client for third-party video generation services across
mobile and desktop. The installed desktop and mobile apps contain no
analytics or advertising SDKs. The splash page at `clawnsole.app` uses Google
Analytics with region-aware consent controls, as described below. The developer
does not operate an account system or cloud database for project data.

## Data stored on your device

Clawnsole stores the information needed to provide its features in the app's
private local storage. Depending on how you use the app, this can include:

- your selected provider and user-supplied provider API keys;
- prompts, generation settings, provider job identifiers, status, errors, and
  estimated or provider-reported usage and cost;
- saved and in-progress reference images, video, and audio; generated media;
  local file references; and reference names, folders, and tags;
- appearance, retention, and other app preferences; and
- on the `clawnsole.app` splash page, your analytics consent choice.

Provider keys are kept in operating-system-backed secure storage rather than
the local project-history JSON. They can be added, replaced, or removed from **Providers**. Saved
references can be renamed, reorganized, or deleted from **References**.
Generation history and app preferences can be cleared from **Settings**.
Removing the app may also remove data held in its application sandbox, subject
to the backup and device-management behavior of your operating system.

## Optional Google Drive storage

Every installed Clawnsole app can use a Google Drive folder that you authorize to make
selected Clawnsole data available across devices. If enabled, Clawnsole stores
prompts, generation records, saved-reference metadata, retained
input media, generated media, folders, and tags in that folder. If you also
enable encrypted settings sync, provider API keys and app preferences are
uploaded only inside an authenticated encrypted vault. Google processes and
retains the project files and encrypted vault under your Google account
settings and the [Google Privacy Policy](https://policies.google.com/privacy).

Clawnsole requests the limited `drive.file` permission and can access only the
Drive files it creates or that you explicitly make available to the app. Drive
access tokens and desktop refresh tokens are not sent to the developer; desktop
refresh tokens use operating-system-backed encrypted storage. The settings
vault is encrypted on the device with a random key protected by your sync
passphrase. The passphrase is not stored. A recovery code is shown once, and an
unlocked vault key is cached in device-secure storage so you normally enter the
passphrase only once per device. Keep the passphrase and recovery code private.

## Data sent to a generation provider

When you ask Clawnsole to verify a provider account, check a balance, load a
model catalog or price, or create, monitor, or download a generation, the app
communicates with the selected provider. It sends the provider API key and the
information required for that request. Depending on the provider, model, and
task, this can include prompts, settings, reference images, source video and its
audio, provider job identifiers, and related request metadata.

Clawnsole currently supports these generation providers:

- **Apple Intelligence:** On supported iPhones and iPads, Clawnsole sends the
  prompt and selected image settings to Apple's Image Playground system
  framework. It requires no Clawnsole or third-party provider API key. Apple
  controls device eligibility, model availability, processing, and applicable
  usage limits under its platform terms and privacy disclosures. Clawnsole
  stores only the resulting image or locally encoded silent image sequence in
  the library location you selected.

- **Black Forest Labs (BFL / FLUX 3):** Review the
  [BFL privacy policy](https://bfl.ai/legal/privacy-policy) and
  [usage policy](https://bfl.ai/legal/usage-policy).
- **LTX:** LTX is operated by Lightricks. Review the
  [LTX Platform privacy policy](https://static.lightricks.com/legal/Privacy%20Policy%20-%20LTX%20Platform.pdf).
- **ArtCraft:** Review the current privacy disclosures presented by
  [ArtCraft](https://app.getartcraft.com/) before using its service.
- **Atlas Cloud:** Review the
  [Atlas Cloud privacy policy](https://www.atlascloud.ai/privacy). Atlas Cloud
  is an API aggregation platform and may forward prompts and generation inputs
  to the underlying model provider selected for the request; that provider's
  own data-handling and retention policies also apply.

Those providers process and may retain data under their own terms and privacy
policies. Review the applicable documents before sending private or sensitive
material. Clawnsole is an independent client and is not affiliated with or
endorsed by Black Forest Labs, Lightricks/LTX, ArtCraft, or Atlas Cloud.

## App Review provider access

A mobile build prepared for store review may include a temporary ArtCraft
credential so reviewers can test the restricted Seedance route without
entering a key manually. This credential is compiled into that build, is not
written to Clawnsole's local data file, and is never displayed in the
interface. Requests made with it are still sent to and processed by ArtCraft
as described above. A user-supplied key takes precedence after it is saved.
After Clawnsole successfully refreshes a catalog that removes that app version
from the review list, the compiled credential is disabled and only a
user-supplied ArtCraft key can be used. Apple Intelligence routes never use
this credential.

## Update checks and external links

The macOS, Windows, iOS, and Android builds ask GitHub's public releases
API whether a newer Clawnsole version exists once per app launch, every 24 hours
while running, and when you manually check where that action is available. That
request carries no provider API key, prompt, media, or history. GitHub receives
only an ordinary web request and its usual connection metadata. The iOS and
Android stores still handle installation.

Links that you choose to open, including provider consoles, documentation,
pricing pages, and this policy, open in your browser and are governed by the
destination site's policy.

## Google Analytics on clawnsole.app

The splash page at `https://clawnsole.app/` uses Google Analytics to understand
visits and interactions, evaluate site performance, and decide what to improve.
The Analytics tag is not present on the privacy policy, terms of use, or
installed macOS, Windows, iOS, and Android apps.

The splash page uses the time zone reported by your browser through JavaScript's
`Intl.DateTimeFormat` API as a best-effort estimate of whether you are in the
European Economic Area, United Kingdom, or Switzerland. This check happens in
your browser and is not sent to Clawnsole or a separate IP geolocation service.
Because a device time zone can be changed, unavailable, or different from your
actual location, it is not a precise country determination. If the time zone is
unavailable or ambiguous, Clawnsole shows the consent controls.

When the browser-reported time zone maps to one of those regions, Google
Analytics is off by default. The Google tag is not loaded and no data is sent to
Google Analytics unless you select **Allow analytics**. In other detected
regions, Analytics loads automatically unless you previously selected
**Decline**. Clawnsole stores an explicit choice in your browser's localStorage
so it can be honored on later visits. Visitors everywhere can open **Analytics
choices** in the splash-page footer. Withdrawing consent disables Analytics,
removes accessible Analytics cookies, and prevents it from loading on later
visits in that browser.

When Analytics is enabled, Google Analytics may process the splash-page URL,
referral information, interactions, session statistics, approximate location,
browser and device information, IP addresses for processing and coarse
location, and identifiers stored in first-party cookies. Google processes this
information under its
[explanation for sites that use Google services](https://policies.google.com/technologies/partner-sites)
and its [privacy policy](https://policies.google.com/privacy).

Clawnsole does not intentionally send provider API keys, prompts, reference
media, generated media, Google Drive contents, or project history to Google
Analytics. Analytics data is used for splash-page audience and product
measurement, not advertising or cross-app tracking. Advertising storage, ads
user data, ads personalization, Google signals, and ad personalization signals
remain disabled. Google Analytics retention is controlled through the Analytics
property settings. You can also limit Analytics through your browser's cookie
controls or Google's
[Analytics opt-out browser add-on](https://tools.google.com/dlpage/gaoptout).

## Data collected by the developer

The installed Clawnsole apps do not send the developer your API keys, prompts,
reference media, generated media, generation history, contacts, precise
location, advertising identifiers, or analytics events. The developer can
access aggregate and event-level splash-page usage reports for visits where
Google Analytics is enabled, as described above. Clawnsole does not use data
for advertising or cross-app tracking.

Apple, Google, GitHub, the selected generation provider, any underlying model
provider, and the platform through which you install or use Clawnsole may
process account, download, purchase, diagnostic, crash, request, or connection
information under their own policies and your settings with those services.

## Security and retention

Keep provider API keys private and revoke a key through the provider if you
believe it has been exposed. Clawnsole keeps local data until you clear it,
remove it through the app, or uninstall the app. Optional Drive data remains in
your Google account until you delete it through Clawnsole or Google Drive.
Provider-side retention and deletion are controlled by the selected provider
and, for an aggregated model, may also be controlled by the underlying model
provider.

## Changes and contact

This policy may be updated as Clawnsole adds providers or changes how data is
handled. Material changes will be reflected in this document and its effective
date.

For privacy questions, open an issue at
<https://github.com/heresalexandria/clawnsole/issues>. Do not include API keys,
private prompts, or personal media in a public issue.

The public version of this policy is available at
<https://clawnsole.app/privacy/>.
