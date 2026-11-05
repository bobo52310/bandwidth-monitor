# Bandwidth ECG 官網

[Bandwidth ECG](../README.md) 的行銷單頁，四個語系（zh-Hant 為預設，en、ja、ko）。Astro 7 靜態輸出，Tailwind 4，部署在 Cloudflare Pages。

## 指令

需要 Node 22.23.4 以上（`.node-version` 與 `package.json` 的 `engines` 都寫了）。

```sh
npm ci
npm run dev                          # http://localhost:4321
npm run build                        # 輸出到 dist/
npm run preview                      # 預覽 dist/
node scripts/check-i18n.mjs          # 檢查 4 份 locale 的 key 是否一致、有無被禁用的宣稱
node scripts/check-i18n.mjs --dist   # 另外掃 build 完的 HTML
```

改文案或元件後，build 與兩個 check 都要通過。

## 結構

```
src/
├── i18n/            # index.ts 與 locales/{zh-Hant,en,ja,ko}.json
├── layouts/Layout.astro        # <head>、hreflang、OG；404 傳 noindex
├── components/      # Header、Footer、LanguageSwitcher
│   └── sections/    # Hero、Features、HowItWorks、CalibrationStrip、ChartDemo、FAQ、DownloadCTA
├── pages/           # index（zh-Hant）、en/、ja/、ko/、404
└── styles/global.css
public/              # _headers、site.webmanifest、圖示、og-default.png
scripts/check-i18n.mjs
```

## 文案與 i18n

- zh-Hant 是 schema 的唯一來源。其他三份 locale 必須有相同的 key，缺 key 時 `t()` 會丟錯，build 直接失敗，不會悄悄退回中文。
- 資訊句（功能說明、FAQ、按鈕、aria-label）一律走 locale JSON。`RECORDING`、`CALIBRATION` 這類儀表板風格標籤是刻意保留的英文，直接寫在元件裡。
- 頁面上的數字與波形都是**示意數據**，Hero 與 ChartDemo 有標籤。ChartDemo 的 Y 軸刻度、方案上限線、80% 接近線與峰值註記都由同一份取樣資料推算，不要分開手調。

## 部署

Cloudflare Pages 的 git integration，推到 `main` 自動部署。

- Pages 專案的環境變數 `NODE_VERSION`（Production 與 Preview 各一份）要大於等於 `22.23.4`，否則 Astro 7 build 會失敗。
- `public/_headers` 含 CSP。加新的第三方腳本、字型或 API 之前，要先把網域放進對應的指令。
- 404：Pages 對所有找不到的網址都回 `404.html`，所以 404 頁的「回到首頁」連結由頁面內的小 script 依網址前綴挑語系。
