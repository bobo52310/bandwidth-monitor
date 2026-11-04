import zhHant from './locales/zh-Hant.json';
import enJson from './locales/en.json';
import jaJson from './locales/ja.json';
import koJson from './locales/ko.json';

export type Lang = 'zh-Hant' | 'en' | 'ja' | 'ko';

// zh-Hant is the single source of truth for the message schema. The other
// locales must match its shape, so a missing or misplaced key fails type-checking.
// (Array lengths are not checked by the type; scripts/check-i18n.mjs covers that.)
export type Messages = typeof zhHant;

const en: Messages = enJson;
const ja: Messages = jaJson;
const ko: Messages = koJson;

export const languages: Record<Lang, string> = {
  'zh-Hant': '繁體中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
};

export const defaultLang: Lang = 'zh-Hant';

export const translations: Record<Lang, Messages> = {
  'zh-Hant': zhHant,
  'en': en,
  'ja': ja,
  'ko': ko,
};

export function getLangFromUrl(url: URL): Lang {
  const [, lang] = url.pathname.split('/');
  if (lang in translations) return lang as Lang;
  return defaultLang;
}

/**
 * Returns a lookup for dotted keys such as `hero.ctaLearn`.
 * A missing key throws instead of falling back to another language, so a
 * forgotten translation breaks the build rather than shipping mixed-language pages.
 */
export function useTranslations(lang: Lang) {
  return function t(key: string): string {
    let value: unknown = translations[lang];

    for (const part of key.split('.')) {
      if (value !== null && typeof value === 'object' && part in value) {
        value = (value as Record<string, unknown>)[part];
      } else {
        throw new Error(`[i18n] Missing key "${key}" for locale "${lang}"`);
      }
    }

    if (typeof value !== 'string') {
      throw new Error(`[i18n] Key "${key}" for locale "${lang}" is not a string`);
    }
    return value;
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
