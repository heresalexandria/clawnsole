(() => {
  const storageKey = 'clawnsole-site-theme';
  const picker = document.querySelector('[data-theme-picker]');
  const trigger = picker?.querySelector('[data-theme-trigger]');
  const choices = picker?.querySelectorAll('[data-theme-value]') ?? [];
  const colorMeta = document.querySelector('#theme-color');
  const media = window.matchMedia('(prefers-color-scheme: dark)');

  const storedTheme = () => {
    try {
      const value = localStorage.getItem(storageKey);
      return value === 'light' || value === 'dark' ? value : 'system';
    } catch (_) {
      return 'system';
    }
  };

  const applyTheme = (theme) => {
    if (theme === 'light' || theme === 'dark') {
      document.documentElement.dataset.theme = theme;
    } else {
      delete document.documentElement.dataset.theme;
    }
    const isDark = theme === 'dark' || (theme === 'system' && media.matches);
    colorMeta?.setAttribute('content', isDark ? '#171116' : '#f8f3e8');
    if (picker) picker.dataset.resolvedTheme = isDark ? 'dark' : 'light';
    if (trigger) {
      const label = `Theme: ${theme}. Current appearance: ${isDark ? 'dark' : 'light'}`;
      trigger.setAttribute('aria-label', label);
      trigger.setAttribute('title', label);
    }
    choices.forEach((choice) => {
      choice.setAttribute('aria-pressed', String(choice.dataset.themeValue === theme));
    });
  };

  choices.forEach((choice) => choice.addEventListener('click', () => {
    const theme = choice.dataset.themeValue;
    try {
      if (theme === 'system') localStorage.removeItem(storageKey);
      else localStorage.setItem(storageKey, theme);
    } catch (_) {}
    applyTheme(theme);
    picker.removeAttribute('open');
    trigger?.focus();
  }));

  document.addEventListener('click', (event) => {
    if (picker?.open && !picker.contains(event.target)) {
      picker.removeAttribute('open');
    }
  });

  picker?.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      picker.removeAttribute('open');
      trigger?.focus();
    }
  });

  media.addEventListener('change', () => {
    if (storedTheme() === 'system') applyTheme('system');
  });

  applyTheme(storedTheme());
})();
