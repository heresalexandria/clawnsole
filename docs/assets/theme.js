(() => {
  const storageKey = 'clawnsole-site-theme';
  const picker = document.querySelector('[data-theme-picker]');
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
    if (picker) picker.value = theme;
  };

  picker?.addEventListener('change', (event) => {
    const theme = event.target.value;
    try {
      if (theme === 'system') localStorage.removeItem(storageKey);
      else localStorage.setItem(storageKey, theme);
    } catch (_) {}
    applyTheme(theme);
  });

  media.addEventListener('change', () => {
    if (storedTheme() === 'system') applyTheme('system');
  });

  applyTheme(storedTheme());
})();
