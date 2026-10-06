#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d /tmp/playwright-smoke/node_modules/playwright ]]; then
  npm install --prefix /tmp/playwright-smoke --no-audit --no-fund playwright@1.63.0
fi
# A project's cleanup must leave the installer-owned shared browsers intact.
node /tmp/playwright-smoke/node_modules/playwright/cli.js uninstall
node <<'JS'
const { chromium } = require('/tmp/playwright-smoke/node_modules/playwright');
(async () => {
  for (const options of [{}, { channel: 'chromium' }]) {
    const browser = await chromium.launch(options);
    try {
      const page = await browser.newPage();
      await page.setContent('<h1>Playwright Chromium ready</h1>');
      if (await page.locator('h1').textContent() !== 'Playwright Chromium ready')
        throw new Error('Browser content mismatch');
    } finally {
      await browser.close();
    }
  }
})().catch(error => { console.error(error); process.exit(1); });
JS
