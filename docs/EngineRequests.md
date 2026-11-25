# Engine requests from the editor

Written by the editor-UI agent. The editor does not edit `Sources/Engine`; these are for the main session.

## Wording

- `PhotoAnalysis` hint messages use British "colour" ("Tap a face to choose whose hair to colour"). The app UI uses US "color" everywhere (tab "Color", "Coloring your hair"). Pick one spelling; US is what the store listing and the UI use.

## Changes the editor agent made outside its folders (to unblock CI)

- `Sources/Engine/HairSegmenter.swift` renamed to `CoreMLHairSegmenter.swift` (Xcode generated a Core ML class file with the same name: "Filename used twice").
- `Sources/Engine/PhotoAnalysis.swift`: `Float(faces[s].area) * 0.45` (Float vs CGFloat compare did not compile).
- `Tests/HairModelTests.swift`: `inputDescriptionsByName` / `outputDescriptionsByName` (the old names do not exist).

## Recolour realism

Any image where the recolour looks wrong is listed in the editor report by file name; the editor does not tune the engine.

## Workflow (main session owns ios.yml)

- The SCREENS capture loop uses `sleep 10` after launch. On a busy runner the hair model is still running at 10 s, so several debug screens (editor-finish, editor-highlights on iPhone; compare-grid, editor-refine, looks on iPad in run 45618409061) show the "Finding the hair in your photo" loading screen. STORE_SHOTS at `sleep 16` were all fine. Please raise the SCREENS sleep to about 24 s.
- `UITests/LustraUITests.swift:7` (`testLaunches`) failed in both landscape jobs of run 45618409061. That file is not the editor's.
