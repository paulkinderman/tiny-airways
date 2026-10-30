// Renders tool/art/app_icon.svg into the iOS and Android app icons and the
// iOS launch image.
//
//   NODE_PATH=$(npm root -g) node tool/art/build_icons.js
//
// Needs Playwright with Chromium. iOS icons are flattened to RGB by
// tool/art/flatten_icons.py afterwards (the App Store refuses alpha).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../..');
const svg = fs.readFileSync(path.join(__dirname, 'app_icon.svg'), 'utf8');
const ios = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const contents = JSON.parse(fs.readFileSync(path.join(ios, 'Contents.json')));
const android = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  async function render(px, file) {
    await page.setViewportSize({ width: px, height: px });
    await page.setContent(
      `<body style="margin:0">${svg.replace('width="1024" height="1024"', `width="${px}" height="${px}"`)}</body>`,
    );
    await page.screenshot({ path: file, clip: { x: 0, y: 0, width: px, height: px } });
  }
  for (const image of contents.images) {
    const px = Math.round(parseFloat(image.size) * parseInt(image.scale));
    await render(px, path.join(ios, image.filename));
  }
  // The launch screen shows the icon at 128 points on the board's dark ground.
  const launch = path.join(root, 'ios/Runner/Assets.xcassets/LaunchImage.imageset');
  for (const [suffix, px] of [['', 128], ['@2x', 256], ['@3x', 384]]) {
    await render(px, path.join(launch, `LaunchImage${suffix}.png`));
  }
  for (const [dir, px] of Object.entries(android)) {
    await render(px, path.join(root, 'android/app/src/main/res', dir, 'ic_launcher.png'));
  }
  await browser.close();
})();
