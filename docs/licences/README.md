# Third-party licences

One file per bundled third-party component. The in-app screen Settings > Open-source licences is built from these files
(component name, source URL, version / hash, full licence text). Add a file here for every new component before it ships.

| Component | File | Licence | Where it is used |
|---|---|---|---|
| MediaPipe Hair Segmenter (Core ML conversion) | [hair-segmenter.md](hair-segmenter.md) | Apache-2.0 | Sources/Resources/Models/HairSegmenter.mlpackage |

Structure of each file: Identity table (name, author, source URL, size, SHA-256, licence), licence wording from the source, model or library summary,
what we changed, full licence text.

Not listed here on purpose: Google Mobile Ads SDK and Google User Messaging Platform (Swift Package Manager, listed by their own licence screens / Apple
frameworks need no notice).
