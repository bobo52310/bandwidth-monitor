// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://bandwidth-ecg.bobochen.dev',
  // Astro 7 defaults to 'jsx', which strips whitespace between inline elements.
  compressHTML: true,
  vite: {
    plugins: [tailwindcss()],
    build: {
      // Astro builds with target 'esnext', and cssTarget inherits it, so the CSS
      // minifier drops prefixes Safari 17 still needs (-webkit-backdrop-filter).
      // This is Vite's own default browser list, stated explicitly.
      cssTarget: ['chrome111', 'edge111', 'firefox114', 'safari16.4', 'ios16.4']
    }
  },
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'zh-Hant',
        locales: {
          'zh-Hant': 'zh-Hant',
          en: 'en',
          ja: 'ja',
          ko: 'ko'
        }
      }
    })
  ],
  i18n: {
    defaultLocale: 'zh-Hant',
    locales: ['zh-Hant', 'en', 'ja', 'ko'],
    routing: {
      prefixDefaultLocale: false
    }
  }
});
