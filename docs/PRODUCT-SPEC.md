# Lustra - Hair Color Changer & Try-On (iOS app 8)

Owner: Ecom Swift LLC (Apple team N84NGN3KSH). Repo EcomswiftLLC/hairtryon-ios (public), local C:\Users\Pc\Downloads\HairTryOn-iOS.
Bundle id com.ecomswift.lustra. Home-screen name "Lustra". Site slug https://ecomswiftllc.github.io/lustra/.

## Store text (keywords first, brand last, max 30 chars each)
- Name: "Hair Color Changer: Lustra" (26)
- Subtitle: "Try On Dye, Ombre & Highlights" (30)
- Honest scope: v1 = hair COLOUR try-on plus credible finishing tools. No hairstyle swapping (needs generative model or licensed hair assets). Never claim "hairstyle", "haircut", "bangs" or "wig" features. Do not use the word "AI" for features unless true (the on-device segmentation model is a neural network: say "on-device hair detection").

## Product
Free iPhone + iPad app (iOS 17+, universal). Everything on device: photos never leave the phone (state it in the listing, privacy policy and Settings).
- Pick a photo (Photos picker, camera, bundled samples). Hair is found by an on-device Core ML segmentation model (MediaPipe hair segmenter, Apache-2.0, converted on CI) plus Vision face detection, with a soft feathered matte refined by a guided filter.
- Recolour keeps natural lighting, strands and highlights (Lab: new a/b, remapped L with a detail layer, lift step for dark to light).
- Colours: natural shades, fashion colours, custom colour. Styles: solid, ombre, balayage, highlights, two-tone (split), root shadow. Sliders: intensity, shine, brightness. Gray cover. Gradient tool. Manual refine brush (add/remove hair area). Before/after slider. Undo/redo. Detection hints (blurry, hat/covered hair, multiple faces, no face, small face, low light). Multi-face choice. Palette grid compare (one export = one ad). Favourite looks (saved on device).
- Finishing tools (real image edits on the hair matte only): smooth/frizz soften, strand definition.

## Monetisation (owner order)
Free. AdMob banner on Home. Every Save to Photos / Save to Files / Share goes through ONE AdMob rewarded ad (grid or comparison = one ad); show the finished result and before/after first; if no ad can load the export proceeds free. No IAP, no StoreKit purchases.
Review prompt: Apple `requestReview` only, after the 3rd successful save/export, once per version, >=120 days apart, >=2 days or 3 sessions since install, not within 60 s of an ad, never while an ad/share sheet is up, not after error/cancel. Settings "Rate Lustra" row opens https://apps.apple.com/app/id<ID>?action=write-review once the App Store id is known.

## Rules
Universal "1,2" at TARGETED_DEVICE_FAMILY (target level). CI-only on GitHub Actions macos-26, free tools only. Privacy manifest NSPrivacyTracking=false, no domains (ITMS-91064). Privacy labels in ASC say tracking Yes because ATT is shown. Real licensed photos only (Pexels/CC0), licence note per photo in docs/store/photo-credits.md; no sexualised imagery; no placeholders.

## Code layout
Sources/Engine (pure Swift hair engine, unit-testable), Sources/Features (SwiftUI screens), Sources/Ads, Sources/Review, Sources/Theme, Sources/Resources (Models/HairSegmenter.mlpackage, Samples, Info.plist, PrivacyInfo.xcprivacy), Tests, UITests, tools (python), website, docs.
