const { chromium } = require('playwright');
const path = require('path');

async function captureScreenshots() {
  const browser = await chromium.launch();

  const versions = [
    { name: 'v1-minimalist', port: 4321 },
    { name: 'v2-playful', port: 4322 },
    { name: 'v3-professional', port: 4323 }
  ];

  for (const version of versions) {
    const page = await browser.newPage();

    // Desktop (1440px)
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(`http://localhost:${version.port}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: path.join(__dirname, `${version.name}-desktop.png`),
      fullPage: true
    });
    console.log(`Captured ${version.name} desktop`);

    // Tablet (768px)
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(500);
    await page.screenshot({
      path: path.join(__dirname, `${version.name}-tablet.png`),
      fullPage: true
    });
    console.log(`Captured ${version.name} tablet`);

    // Mobile (375px)
    await page.setViewportSize({ width: 375, height: 812 });
    await page.waitForTimeout(500);
    await page.screenshot({
      path: path.join(__dirname, `${version.name}-mobile.png`),
      fullPage: true
    });
    console.log(`Captured ${version.name} mobile`);

    await page.close();
  }

  await browser.close();
  console.log('All screenshots captured!');
}

captureScreenshots().catch(console.error);
