// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  vite: {
    plugins: [tailwindcss()]
  },
  i18n: {
    defaultLocale: 'zh-Hant',
    locales: ['zh-Hant', 'en', 'ja', 'ko'],
    routing: {
      prefixDefaultLocale: false
    }
  }
});