"use strict";

const APP_ICON_DATA_URL = "data:image/png;base64,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";

const RESULT_COPY = {
  success: {
    title: "Clawnsole connected",
    eyebrow: "Google Drive library",
    heading: "You’re connected.",
    lede: "Clawnsole can now keep your Drive library in sync across your devices.",
    status: "Authorization complete",
    detail: "Return to Clawnsole to choose or create your library folder.",
  },
  failure: {
    title: "Clawnsole connection not completed",
    eyebrow: "Google Drive library",
    heading: "Connection not completed.",
    lede: "Google Drive did not authorize Clawnsole. No Drive files were changed.",
    status: "Return to Clawnsole",
    detail: "Close this tab and try Connect Google Drive again when you’re ready.",
  },
};

function oauthResultPage(success) {
  const state = success ? "success" : "failure";
  const copy = RESULT_COPY[state];
  const statusIcon = success
    ? '<path d="m7.4 12.2 3.1 3.1 6.3-7" />'
    : '<path d="m8.4 8.4 7.2 7.2m0-7.2-7.2 7.2" />';

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" media="(prefers-color-scheme: light)" content="#f8f3e8">
    <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#171116">
    <title>${copy.title}</title>
    <link rel="icon" href="${APP_ICON_DATA_URL}" type="image/png">
    <style>
      :root {
        color-scheme: light dark;
        --ink: light-dark(#281d2b, #f3ead9);
        --muted: light-dark(#675e70, #c7b9bc);
        --paper: light-dark(#f8f3e8, #171116);
        --paper-deep: light-dark(#efe4d0, #2a2025);
        --cream: light-dark(#fffaf0, #21191d);
        --plum: light-dark(#5a2856, #d2a0ca);
        --plum-action: light-dark(#5a2856, #70406b);
        --plum-dark: light-dark(#2b1a29, #21151f);
        --navy: light-dark(#17345b, #6e99cf);
        --brass: light-dark(#a67525, #d9b36c);
        --line: light-dark(#d9ccb4, #4a3b40);
        --card: light-dark(rgba(255, 250, 240, 0.94), rgba(42, 31, 37, 0.94));
        --glow-brass: light-dark(rgba(166, 117, 37, 0.12), rgba(217, 179, 108, 0.08));
        --glow-plum: light-dark(rgba(90, 40, 86, 0.1), rgba(210, 160, 202, 0.08));
        --page-grid-x: light-dark(rgba(96, 72, 45, 0.018), rgba(232, 207, 168, 0.018));
        --page-grid-y: light-dark(rgba(96, 72, 45, 0.014), rgba(232, 207, 168, 0.012));
        --shadow: 0 30px 70px light-dark(rgba(46, 28, 35, 0.16), rgba(0, 0, 0, 0.4));
        font-family: "Avenir Next", Avenir, "Segoe UI", Helvetica, Arial, sans-serif;
        font-synthesis: none;
      }

      * { box-sizing: border-box; }

      html, body { min-height: 100%; }

      body {
        margin: 0;
        color: var(--ink);
        background:
          radial-gradient(circle at 14% 14%, var(--glow-brass), transparent 25rem),
          radial-gradient(circle at 88% 84%, var(--glow-plum), transparent 28rem),
          repeating-linear-gradient(0deg, var(--page-grid-x) 0 1px, transparent 1px 4px),
          repeating-linear-gradient(90deg, var(--page-grid-y) 0 1px, transparent 1px 5px),
          var(--paper);
        font-size: 16px;
        line-height: 1.6;
      }

      .page {
        display: grid;
        width: min(100% - 40px, 760px);
        min-height: 100vh;
        margin-inline: auto;
        padding-block: clamp(28px, 7vh, 72px);
        align-content: center;
      }

      .wordmark {
        display: inline-flex;
        gap: 12px;
        align-items: center;
        width: max-content;
        margin: 0 0 22px 24px;
        color: var(--ink);
        font-family: Georgia, "Times New Roman", serif;
        font-size: 1.45rem;
        font-weight: 700;
        letter-spacing: -0.035em;
      }

      .wordmark img {
        width: 42px;
        height: 42px;
        border-radius: 11px;
        box-shadow: 0 4px 12px rgba(46, 28, 35, 0.22);
      }

      .card {
        position: relative;
        overflow: hidden;
        padding: clamp(36px, 7vw, 68px);
        border: 1px solid var(--line);
        border-radius: 24px;
        background: var(--card);
        box-shadow: var(--shadow);
      }

      .card::after {
        position: absolute;
        right: -86px;
        bottom: -112px;
        width: 260px;
        height: 260px;
        border-radius: 44% 56% 62% 38%;
        background: var(--paper-deep);
        content: "";
        transform: rotate(-18deg);
      }

      .eyebrow {
        margin: 0 0 18px;
        color: var(--brass);
        font-size: 0.7rem;
        font-weight: 800;
        letter-spacing: 0.23em;
        text-transform: uppercase;
      }

      h1 {
        max-width: 11ch;
        margin: 0 0 22px;
        font-family: Georgia, "Times New Roman", serif;
        font-size: clamp(3rem, 9vw, 5.5rem);
        font-weight: 500;
        letter-spacing: -0.045em;
        line-height: 0.98;
      }

      .success h1 { color: var(--plum); }
      .failure h1 { color: var(--navy); }

      .lede {
        position: relative;
        z-index: 1;
        max-width: 34rem;
        margin: 0 0 34px;
        color: var(--muted);
        font-family: Georgia, "Times New Roman", serif;
        font-size: clamp(1.1rem, 3vw, 1.4rem);
        line-height: 1.52;
      }

      .status {
        position: relative;
        z-index: 1;
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 14px;
        align-items: center;
        max-width: 35rem;
        padding: 18px 20px;
        border: 1px solid var(--line);
        border-radius: 13px;
        background: var(--paper);
      }

      .status-icon {
        display: grid;
        width: 40px;
        height: 40px;
        border-radius: 50%;
        color: white;
        background: var(--plum-action);
        place-items: center;
      }

      .failure .status-icon { background: var(--navy); }

      .status-icon svg {
        width: 24px;
        height: 24px;
        fill: none;
        stroke: currentColor;
        stroke-linecap: round;
        stroke-linejoin: round;
        stroke-width: 2.2;
      }

      .status strong,
      .status span { display: block; }

      .status strong {
        margin-bottom: 2px;
        font-size: 0.82rem;
        letter-spacing: 0.035em;
      }

      .status span {
        color: var(--muted);
        font-size: 0.82rem;
        line-height: 1.45;
      }

      .close-note {
        margin: 20px 24px 0;
        color: var(--muted);
        font-size: 0.72rem;
        letter-spacing: 0.035em;
      }

      @media (max-width: 520px) {
        .page { width: min(100% - 24px, 760px); }
        .wordmark { margin-left: 12px; }
        .card { border-radius: 18px; }
        .status { grid-template-columns: 1fr; }
      }
    </style>
  </head>
  <body class="${state}">
    <div class="page">
      <header class="wordmark">
        <img src="${APP_ICON_DATA_URL}" width="64" height="64" alt="">
        <span>Clawnsole</span>
      </header>
      <main class="card">
        <p class="eyebrow">${copy.eyebrow}</p>
        <h1>${copy.heading}</h1>
        <p class="lede">${copy.lede}</p>
        <div class="status">
          <span class="status-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24">${statusIcon}</svg>
          </span>
          <div>
            <strong>${copy.status}</strong>
            <span>${copy.detail}</span>
          </div>
        </div>
      </main>
      <p class="close-note">You can safely close this tab.</p>
    </div>
  </body>
</html>`;
}

module.exports = {
  oauthResultPage,
};
