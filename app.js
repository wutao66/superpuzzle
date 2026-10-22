(() => {
  const storageKey = 'super-puzzle-site-language';
  const body = document.body;
  const savedLanguage = localStorage.getItem(storageKey);
  const systemLanguage = navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en';

  function applyLanguage(language) {
    const selected = language === 'zh' ? 'zh' : 'en';
    body.dataset.lang = selected;
    document.documentElement.lang = selected === 'zh' ? 'zh-CN' : 'en';
    document.title = selected === 'zh' ? body.dataset.titleZh : body.dataset.titleEn;
    localStorage.setItem(storageKey, selected);
  }

  applyLanguage(savedLanguage || systemLanguage);

  document.querySelectorAll('[data-language-toggle]').forEach((button) => {
    button.addEventListener('click', () => applyLanguage(body.dataset.lang === 'zh' ? 'en' : 'zh'));
  });

  document.querySelectorAll('[data-current-year]').forEach((node) => {
    node.textContent = String(new Date().getFullYear());
  });
})();
