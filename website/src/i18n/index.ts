import zhHant from './locales/zh-Hant.json';
import en from './locales/en.json';
import ja from './locales/ja.json';
import ko from './locales/ko.json';

export const languages = {
  'zh-Hant': '繁體中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
};

export const defaultLang = 'zh-Hant';

export const translations = {
  'zh-Hant': zhHant,
  'en': en,
  'ja': ja,
  'ko': ko,
} as const;

export type Lang = keyof typeof translations;

export function getLangFromUrl(url: URL): Lang {
  const [, lang] = url.pathname.split('/');
  if (lang in translations) return lang as Lang;
  return defaultLang;
}

export function useTranslations(lang: Lang) {
  return function t(key: string): string {
    const keys = key.split('.');
    let value: any = translations[lang];

    for (const k of keys) {
      if (value && typeof value === 'object' && k in value) {
        value = value[k];
      } else {
        // Fallback to default language
        value = translations[defaultLang];
        for (const fallbackKey of keys) {
          if (value && typeof value === 'object' && fallbackKey in value) {
            value = value[fallbackKey];
          } else {
            return key; // Return key if not found
          }
        }
        break;
      }
    }

    return typeof value === 'string' ? value : key;
  };
}

export function getLocalizedPath(lang: Lang, path: string): string {
  if (lang === defaultLang) {
    return path;
  }
  return `/${lang}${path}`;
}

export function getAlternateLinks(currentPath: string): { lang: Lang; href: string }[] {
  const basePath = currentPath.replace(/^\/(en|ja|ko)/, '') || '/';

  return (Object.keys(languages) as Lang[]).map((lang) => ({
    lang,
    href: getLocalizedPath(lang, basePath),
  }));
}
