# Clawnsole privacy policy

Effective: August 16, 2026

Clawnsole is a local-first client for third-party video generation services. The
developer of Clawnsole does not operate an account system, analytics service,
advertising network, or cloud database for the app.

## Data stored on your device

Clawnsole stores the information needed to provide its features in the app's
private local storage. Depending on how you use the app, this can include:

- your selected provider and API key;
- prompts, generation settings, provider job identifiers, status, errors, and
  estimated or reported credit usage;
- reference images, source video, generated video, and local file references;
- appearance, retention, and other app preferences.

You can inspect and clear this data from Clawnsole's Settings screen. Removing
the app may also remove data held in its application sandbox, subject to the
backup and device-management behavior of your operating system.

## Data sent to a generation provider

When you ask Clawnsole to check an account balance or create, monitor, or
download a generation, the app communicates directly with the selected
provider. It sends the provider API key and the information required for that
request. For Black Forest Labs, this can include prompts, settings, reference
images, source video, job identifiers, and related request metadata.

That provider processes and may retain information under its own terms and
privacy policy. Black Forest Labs is currently the only supported generation
provider. Its requests can include audio contained in a submitted source video.
Review the [Black Forest Labs privacy policy](https://bfl.ai/legal/privacy-policy)
and [usage policy](https://bfl.ai/legal/usage-policy) before sending private or
sensitive material. Clawnsole is an independent client and is not affiliated
with or endorsed by Black Forest Labs.

## Update checks

The desktop app and the web build ask GitHub's public releases API whether a
newer Clawnsole version exists: once per app launch, and again when you open the
version dialog or choose **Check for Updates…**. That request carries no API
key, prompt, media, or history — GitHub receives only an ordinary web request
and its usual connection metadata. The iOS and Android apps do not make this
request; the App Store handles their updates.

## Data collected by the developer

Clawnsole does not operate a sync service and does not send the developer your
API key, prompts, reference media, generated media, generation history,
contacts, precise location, advertising identifiers, or analytics events. The
app does not use data for advertising or cross-app tracking.

Apple and the platform through which you install Clawnsole may process download,
purchase, diagnostic, or crash information under their own policies and the
settings of your device or developer account.

## Security and retention

Keep provider API keys private and revoke a key through the provider if you
believe it has been exposed. Clawnsole keeps local data until you clear it,
remove it through the app, or uninstall the app. Provider-side retention is
controlled by the provider.

## Changes and contact

This policy may be updated as Clawnsole adds providers or changes how data is
handled. Material changes will be reflected in this document and its effective
date.

For privacy questions, open an issue at
<https://github.com/heresalexandria/clawnsole/issues>. Do not include API keys,
private prompts, or personal media in a public issue.

The public version of this policy is available at
<https://heresalexandria.github.io/clawnsole/privacy/>.
