# ASSETS.md — Ruxel asset licenses

## QA portrait sources (public domain only)

| Portrait | URL used | License | Notes |
|----------|----------|---------|-------|
| Albert Einstein, head portrait (1947) | https://upload.wikimedia.org/wikipedia/commons/d/d3/Albert_Einstein_Head.jpg | **Public domain (US)** — photograph by Oren Jack Turner, 1947 | File page: https://commons.wikimedia.org/wiki/File:Albert_Einstein_Head.jpg — 3250×4333, grayscale. Default portrait in `tools/qa_harness.py`. |
| Vincent van Gogh, Self-Portrait (1889) | https://upload.wikimedia.org/wikipedia/commons/b/b2/Vincent_van_Gogh_-_Self-Portrait_-_Google_Art_Project.jpg | **Public domain** — artist died 1890 | File page: https://commons.wikimedia.org/wiki/File:Vincent_van_Gogh_-_Self-Portrait_-_Google_Art_Project.jpg — 3142×3820. Use with `--portrait vangogh`. |

Both URLs were verified live on 2026-11-12 (HTTP 200, valid JPEGs).
No copyrighted images are hotlinked anywhere in this repo. If a new QA
portrait is ever added, it must be CC0 or public domain, and its exact
URL + license must be added to this table first.

## App icon

- **Built (P7, 2026-11-12):** original artwork, generated programmatically
  by `tools/generate_icon.py` (Python/Pillow) — rounded square, violet ->
  magenta diagonal gradient, soft glass highlight, white pixel-face motif
  (two pixel-square eyes + smile arc; nods to "RUXEL" = RUX + EL, EL
  hinting at "pixel"). No copied assets, no trademarks, no third-party
  images, no text in the icon.
- Sizes in `App/Resources/Assets.xcassets/AppIcon.appiconset/`:
  1024, 180, 120, 87, 80, 60, 58, 40 px (LANCZOS downscales from 1024);
  `Contents.json` lists all filenames. Re-generate with
  `python3 tools/generate_icon.py`. Not yet reviewed on a real device
  home screen (needs a green CI build + install).

## Third-party code / models

- **Zero third-party dependencies** in the app (decision). No
  third-party assets, fonts, or ML models are bundled unless their
  license is MIT/Apache and the size is under ~50 MB — and any such
  addition must be logged here with its license before use.
- The 7 reference screenshots from another app are FUNCTION/FLOW
  reference only. No pixels, icons, names, colors or copy from them are
  used in Ruxel.
