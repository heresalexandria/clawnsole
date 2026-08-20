(() => {
  // GitHub Pages exposes no trustworthy first-party country signal, so the
  // consent-first behavior is intentionally consistent for every visitor.
  const measurementId = 'G-1CKFFHE5GY';
  const storageKey = 'clawnsole-site-analytics-consent-v1';
  const banner = document.querySelector('[data-analytics-consent]');
  const allowButton = banner?.querySelector('[data-analytics-allow]');
  const declineButton = banner?.querySelector('[data-analytics-decline]');
  const closeButton = banner?.querySelector('[data-analytics-close]');
  const manageButton = document.querySelector('[data-analytics-manage]');

  if (!banner || !allowButton || !declineButton || !closeButton) return;

  let analyticsLoaded = false;
  let returnFocusTo = null;

  const consentState = (analyticsStorage) => ({
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    analytics_storage: analyticsStorage,
  });

  const readChoice = () => {
    try {
      const choice = localStorage.getItem(storageKey);
      return choice === 'granted' || choice === 'denied' ? choice : null;
    } catch (_) {
      return null;
    }
  };

  const saveChoice = (choice) => {
    try {
      localStorage.setItem(storageKey, choice);
    } catch (_) {}
  };

  const ensureGoogleTagQueue = () => {
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function gtag() {
      window.dataLayer.push(arguments);
    };
  };

  const loadAnalytics = () => {
    if (analyticsLoaded) return;
    analyticsLoaded = true;
    window[`ga-disable-${measurementId}`] = false;
    ensureGoogleTagQueue();

    window.gtag('consent', 'default', consentState('denied'));
    window.gtag('consent', 'update', consentState('granted'));
    window.gtag('js', new Date());
    window.gtag('config', measurementId, {
      allow_ad_personalization_signals: false,
      allow_google_signals: false,
    });

    const script = document.createElement('script');
    script.async = true;
    script.dataset.clawnsoleAnalytics = 'true';
    script.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
    document.head.append(script);
  };

  const deleteAnalyticsCookies = () => {
    const cookieNames = document.cookie
      .split(';')
      .map((cookie) => cookie.split('=', 1)[0].trim())
      .filter((name) => /^(_ga|_gid|_gat|_gac_|_gcl_)/.test(name));
    const hostname = window.location.hostname;
    const domains = ['', hostname, `.${hostname}`];

    cookieNames.forEach((name) => {
      domains.forEach((domain) => {
        const domainAttribute = domain ? `; domain=${domain}` : '';
        const expiredCookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`;
        document.cookie = `${expiredCookie}${domainAttribute}`;
      });
    });
  };

  const hideBanner = () => {
    banner.hidden = true;
    if (returnFocusTo?.isConnected) returnFocusTo.focus();
    returnFocusTo = null;
  };

  const showBanner = ({ focus = false } = {}) => {
    const hasChoice = readChoice() !== null;
    closeButton.hidden = !hasChoice;
    banner.hidden = false;
    if (focus) declineButton.focus();
  };

  allowButton.addEventListener('click', () => {
    saveChoice('granted');
    loadAnalytics();
    hideBanner();
  });

  declineButton.addEventListener('click', () => {
    saveChoice('denied');
    if (!analyticsLoaded) {
      hideBanner();
      return;
    }

    window.gtag('consent', 'update', consentState('denied'));
    window[`ga-disable-${measurementId}`] = true;
    deleteAnalyticsCookies();
    window.setTimeout(() => window.location.reload(), 100);
  });

  closeButton.addEventListener('click', hideBanner);
  manageButton?.addEventListener('click', () => {
    returnFocusTo = manageButton;
    showBanner({ focus: true });
  });

  banner.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && readChoice() !== null) hideBanner();
  });

  const choice = readChoice();
  if (choice === 'granted') loadAnalytics();
  else if (choice === null) showBanner();
})();
