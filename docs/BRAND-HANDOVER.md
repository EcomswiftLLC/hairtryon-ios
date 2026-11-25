# Lustra brand handover (BRAND agent, 2026-11-25)

All six brand tasks are done and pushed to `main`. Nothing here touches Sources/Engine, Features, App, Ads, Tests/*.swift, project.yml or workflows.

## 1. Photos

- CI test portraits: 23 JPEGs in `Tests/Fixtures/portraits/` (16 normal hair types and colours, 7 edge cases: beanie, hood and scarf, group of three, from behind, nearly bald, no person, low light).
- Bundled in-app samples: 8 hair-from-behind JPEGs in `Sources/Resources/Samples/` plus `samples.json` (`file`, `title`, `blurb`, `credit`). Nobody is identifiable.
- All from Pexels (Pexels License), credited per photo in `docs/store/photo-credits.md`.
- Use only these samples in store slides and the website.

## 2. AdMob (account pub-8621573128492952)

| Item | Id |
|---|---|
| iOS app "Lustra" | `ca-app-pub-8621573128492952~5003586562` |
| Banner "Lustra Home Banner" | `ca-app-pub-8621573128492952/9761089220` |
| Rewarded "Lustra Export Rewarded" (reward 1 Export) | `ca-app-pub-8621573128492952/1072527528` |

Written to `Config/Release.xcconfig` and `docs/store/admob.md`. Debug keeps Google's test ids. The app shows "Requires review" in AdMob until it is linked to the App Store listing after launch (owner step).

## 3. Icon

`tools/make_icon.py` draws a lock of hair as 73 fine rose-gold strands with a bent sheen. It writes AppIcon-1024, -dark and -tinted (RGB, no alpha) and `design/icon/preview.png`. No text, no scissors, comb or silhouette. The asset-catalog `Contents.json` was already correct. The same geometry feeds the website favicon and mark.

## 4. Website

Live, all HTTP 200: https://ecomswiftllc.github.io/lustra/ , /support/ , /privacy/ , /terms/ , /licenses/ , /sitemap.xml , /robots.txt.

- Rebuild: `python website/make_site_assets.py && python website/build_site.py`. Output is `website/lustra/`. Publish by copying that folder to `lustra/` in EcomswiftLLC/ecomswiftllc.github.io.
- Privacy and terms are generated from `docs/legal/*.md` (draft-notice block stripped). They are drafts for lawyer review.
- Licences page: MediaPipe hair segmenter (Apache-2.0, full text from `docs/licences/hair-segmenter.md`), Google Mobile Ads and UMP notices, Pexels credits.
- The colour pictures on the home page are an honest illustration (plain colour overlay on one real sample photo) and are labelled as not coming from the app.
- When real app slides exist in `design/store/6.9/*.png`, `make_site_assets.py` adds the first six to the home page ("See it in the app") automatically.
- Checked at 1440 and 390 px: no horizontal scroll, one h1 per page, all images have alt text, contrast 7:1 or better for text, 3 px focus ring, skip link, 44 px targets for nav and summaries. The three design reviews were applied (hero order on mobile, image heights, disclaimer measure, exact licence wording).

## 5. Store copy

`docs/store/listing/*.txt` is the single source. `python tools/build_store_metadata.py` checks every limit and rule (keywords-first name, 99-char keywords, no competitor names, no hairstyle, haircut, bangs or wig claims, no "AI", no superlatives) and writes `docs/store/metadata.md`. Also done: `docs/store/app-privacy.md`, `docs/legal/privacy-policy.md`, `docs/legal/terms-of-use.md`.

- Name: Hair Color Changer: Lustra. Subtitle: Try On Dye, Ombre & Highlights.

## 6. Store slide tooling

- `tools/store_shots_common.py`, `make_store_shots.py` (iPhone 6.9 in, 1320x2868) and `make_store_shots_ipad.py` (iPad 13 in, 2064x2752). Rose-gold-on-ink background.
- Capture names, in slide order: home-filled, editor-colour, editor-ombre, editor-balayage, editor-highlights, compare-grid, refine, before-after, looks, export. They match `Sources/App/StoreScreens.swift`.
- Run: `python tools/make_store_shots.py <CI screenshots folder> design/store/6.9` and `python tools/make_store_shots_ipad.py <CI screenshots-ipad folder> design/store/ipad13`.
- Tested on dummy captures at both sizes (all 10 slides rendered, no clipping), dummies deleted. Missing captures are skipped and listed, never invented.

## Open items for the owner or main session

1. Main session: supply the CI screenshot artifacts, then run the two slide scripts and `make_site_assets.py` again.
2. Owner: App Store Connect record, then link the app in AdMob (clears "Requires review"), add app-ads.txt entry if needed.
3. Owner: lawyer review of the privacy policy and terms before submission.
4. Owner: confirm support@ecomswiftllc.com is monitored.
