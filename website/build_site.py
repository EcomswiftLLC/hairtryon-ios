"""Builds the static Lustra site into website/lustra/.

  python website/build_site.py
  (optional) LUSTRA_SUPPORT_EMAIL=<public support address>   overrides the address read from docs/legal
  (optional) LUSTRA_SITE_OUT=<folder>                        write the pages somewhere else (review builds)

The support address is read from the "Contact:" line of docs/legal/privacy-policy.md unless the environment
variable is set. It is shown on the pages as selectable text (no mailto link).

Writes index.html, support/, privacy/, terms/, licenses/ (index.html each), sitemap.xml, robots.txt.
The privacy and terms pages are generated from docs/legal/*.md. The draft notice block in those files (between the
DRAFT-NOTICE markers) is stripped from the web pages. The licences page reads docs/store/photo-credits.md (sample photo
credits) and docs/licences/hair-segmenter.md (Apache-2.0 text of the MediaPipe hair segmenter).
Assets (CSS, images) live in website/lustra/assets (images come from website/make_site_assets.py).
If website/lustra/assets/shots/*.jpg exist (real app captures) the home page shows them.
"""
import html
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

SRC_SITE = ROOT / "website" / "lustra"
OUT = Path(os.environ.get("LUSTRA_SITE_OUT") or SRC_SITE)
LEGAL = ROOT / "docs" / "legal"

BASE = "https://ecomswiftllc.github.io/lustra/"
UPDATED = "2026-11-25"
SITE_NAME = "Hair Color Changer: Lustra"


def read_support_email():
    env = os.environ.get("LUSTRA_SUPPORT_EMAIL", "").strip()
    if env:
        return env
    text = (LEGAL / "privacy-policy.md").read_text(encoding="utf-8")
    m = re.search(r"\*\*Contact:\*\*\s*(\S+@\S+)", text)
    if not m:
        sys.exit("No support address: set LUSTRA_SUPPORT_EMAIL or keep the Contact line in docs/legal/privacy-policy.md.")
    return m.group(1).strip()


SUPPORT_EMAIL = read_support_email()


# ----------------------------------------------------------------------------- shell
def head(title, description, path, extra_head="", root=""):
    canonical = BASE + path
    t = html.escape(title)
    d = html.escape(description)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{canonical}">
<meta name="theme-color" content="#0C0A0F">
<meta name="color-scheme" content="dark">
<link rel="icon" href="{root}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="{root}assets/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{root}assets/apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{html.escape(SITE_NAME)}">
<meta property="og:title" content="{t}">
<meta property="og:description" content="{d}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{BASE}assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Lustra app icon, a lock of hair drawn in rose-gold strands, next to the name Hair Color Changer: Lustra">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{t}">
<meta name="twitter:description" content="{d}">
<meta name="twitter:image" content="{BASE}assets/og-image.png">
<link rel="stylesheet" href="{root}assets/site.css">
{extra_head}</head>
<body>
<a class="skip" href="#main">Skip to content</a>
"""


def header(root, current=""):
    def a(href, text, key):
        cur = ' aria-current="page"' if key == current else ""
        return f'<a href="{href}"{cur}>{text}</a>'
    home = root or "./"
    return f"""<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{home}"><img src="{root}assets/lustra-mark.svg" alt="" width="34" height="34">Lustra</a>
    <nav class="nav" aria-label="Main">
      {a(home + '#colour', 'Colour', 'c')}
      {a(home + '#compare', 'Compare', 'm')}
      {a(home + '#private', 'Privacy', 'p')}
      {a(home + '#free', 'Free with ads', 'f')}
      {a(home + '#faq', 'FAQ', 'q')}
      {a(root + 'support/', 'Support', 'support')}
    </nav>
  </div>
</header>
"""


def footer(root):
    home = root or "./"
    return f"""<footer class="site-footer">
  <div class="wrap">
    <div>
      <h2>Hair Color Changer: Lustra</h2>
      <p>A free hair colour try-on for iPhone and iPad. Your photos are processed on your device. Not on the App Store yet.</p>
    </div>
    <nav aria-label="Footer">
      <h2>Pages</h2>
      <ul>
        <li><a href="{home}">Home</a></li>
        <li><a href="{root}support/">Support</a></li>
        <li><a href="{root}privacy/">Privacy policy</a></li>
        <li><a href="{root}terms/">Terms of use</a></li>
        <li><a href="{root}licenses/">Licences</a></li>
      </ul>
    </nav>
    <div>
      <h2>Ecom Swift LLC</h2>
      <p>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
      <p class="email">{html.escape(SUPPORT_EMAIL)}</p>
    </div>
    <p class="legalline">&copy; 2026 Ecom Swift LLC. Apple, iPhone, iPad and the App Store are trademarks of Apple Inc. Lustra is not affiliated with Apple or Google. Sample photos are from Pexels. The colour pictures on this site are illustrations.</p>
  </div>
</footer>
</body>
</html>
"""


# ----------------------------------------------------------------------------- home
EMAIL_TEXT = f'<span class="email">{html.escape(SUPPORT_EMAIL)}</span>'

FAQ = [
    ("Is Lustra really free?",
     "<p>Yes. There is no subscription, no in-app purchase, no paid version and no watermark. Ads from Google AdMob pay for the app: a banner on the Home screen, and one rewarded video that you choose to watch before you export.</p>"),
    ("Are my photos uploaded anywhere?",
     "<p>No. Finding the hair, changing the colour and saving the picture all happen on your device. We never receive your photos, and nothing is sent to an online editing service.</p>"),
    ("Do I need an account?",
     "<p>No. There is no sign-in and no sign-up.</p>"),
    ("Does Lustra change my haircut or hairstyle?",
     "<p>No. Lustra is for hair colour only: it changes the colour, the colour style and the finish of the hair that is already in your photo. It does not add a haircut, bangs, curls or a wig.</p>"),
    ("What colours and styles can I try?",
     "<p>Natural shades, fashion colours and a custom colour of your own. For each, you can choose a solid colour, ombre, balayage, highlights, two-tone, or a root shadow. Sliders set the intensity, shine and brightness, and a gray cover option shows colour over gray hair.</p>"),
    ("How does it find the hair?",
     "<p>Lustra uses a hair detection model and Apple's face detection, both running on your device. If the result misses a strand or adds too much, the refine brush lets you add or remove hair area. Lustra also tells you when a photo may be a problem, for example when it is blurry, dark, very small or has more than one face.</p>"),
    ("Will the colour look like this in real life?",
     "<p>Lustra shows a preview. Real dye depends on your starting colour, your hair's condition and the light, so treat the preview as inspiration and talk to your hairdresser before you colour your hair.</p>"),
    ("Why am I asked to watch an ad?",
     "<p>Before you export a picture, the app offers one short video that you choose to watch. One watched ad covers one export, and a comparison grid counts as one export. If you choose Not now, nothing is exported and you can try again any time. If no ad is available, for example when you are offline, the export goes ahead anyway. Editing never needs an ad.</p>"),
    ("What can I export?",
     "<p>The finished picture, a before and after view, or a comparison grid of several colours. You can save to Photos, save to Files, or share. There is no watermark.</p>"),
    ("Does it need photo library or camera access?",
     "<p>Not to edit. You pick a photo with the iOS photo picker, and Lustra sees only the ones you choose. To save a result, the app asks for add-only permission, which lets it add pictures and does not let it read your library. The camera is used only if you choose to take a photo.</p>"),
    ("What happens if I do not allow tracking?",
     "<p>The app works the same. The ads you see will be less personalised. You can change the choice any time in iOS Settings under Privacy and Security, then Tracking. Lustra itself runs no analytics. If you allow tracking, only Google's ad software may use your advertising identifier for ads.</p>"),
    ("Which devices does it run on?",
     "<p>iPhone and iPad with iOS 17 or iPadOS 17 or later.</p>"),
    ("When can I download it?",
     "<p>Lustra is not on the App Store yet, so there is no download link. This page will link to the App Store listing once the app is available.</p>"),
    ("Who makes Lustra?",
     "<p>Ecom Swift LLC, a company registered in Wyoming, United States. You can reach us on the <a href=\"support/\">support page</a>.</p>"),
]


def jsonld_app():
    data = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": SITE_NAME,
        "alternateName": "Lustra",
        "url": BASE,
        "applicationCategory": "MultimediaApplication",
        "operatingSystem": "iOS 17.0 or later",
        "description": "A free hair colour try-on for iPhone and iPad. Try natural and fashion colours, ombre, balayage, highlights, two-tone and root shadow on your own photo, compare colours in a grid and save your favourite looks. Hair is detected on the device. Supported by ads.",
        "image": BASE + "assets/icon-512.png",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "publisher": {"@type": "Organization", "name": "Ecom Swift LLC", "url": "https://www.ecomswiftllc.com/",
                      "address": {"@type": "PostalAddress", "streetAddress": "30 N Gould St #37906",
                                  "addressLocality": "Sheridan", "addressRegion": "WY", "postalCode": "82801",
                                  "addressCountry": "US"}},
        "featureList": [
            "Natural shades, fashion colours and a custom colour",
            "Solid, ombre, balayage, highlights, two-tone and root shadow",
            "Intensity, shine and brightness sliders and gray cover",
            "Refine brush to add or remove hair area",
            "Before and after slider",
            "Palette compare grid, exported as one picture",
            "Saved looks on your device",
            "Hair detection on the device, no account",
        ],
    }
    return '<script type="application/ld+json">\n' + json.dumps(data, indent=2) + "\n</script>\n"


def jsonld_faq():
    plain = lambda s: html.unescape(re.sub(r"<[^>]+>", "", s))
    data = {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q,
                            "acceptedAnswer": {"@type": "Answer", "text": plain(a)}} for q, a in FAQ]}
    return '<script type="application/ld+json">\n' + json.dumps(data, indent=2) + "\n</script>\n"


SAMPLE_ALTS = {
    "ombre-golden-back": "A woman seen from behind with dark roots fading into golden ombre waves, in a denim jacket",
    "blonde-wavy-back": "Long blonde wavy hair seen from behind",
    "balayage-wavy-back": "Long brown wavy hair with lighter sun-kissed ends, seen from behind",
    "silver-long-back": "A woman seen from behind with very long silver-gray hair, hands raised to her head",
    "auburn-straight-back": "Long straight auburn hair seen from behind against a city skyline",
    "copper-bob-back": "A short copper-coloured bob seen from behind",
    "long-black-back": "Long straight black hair with small white flowers, seen from behind",
    "dark-brown-straight-back": "Long straight dark brown hair seen from behind",
}
SAMPLE_CAPTIONS = {
    "ombre-golden-back": "Dark roots into gold. A natural place to try ombre.",
    "blonde-wavy-back": "Light and wavy. Try pastel and fashion colours.",
    "balayage-wavy-back": "Soft sun-kissed ends. Try balayage and highlights.",
    "silver-long-back": "Long and silver. Try cover and bold colour.",
    "auburn-straight-back": "Warm and straight. Try deeper or brighter shades.",
    "copper-bob-back": "Short and copper. Try a root shadow.",
    "long-black-back": "Sleek black. Try a rich fashion colour.",
    "dark-brown-straight-back": "Dark and straight. Try a two-tone look.",
}


def sample_data():
    p = SRC_SITE.parent.parent / "Sources" / "Resources" / "Samples" / "samples.json"
    return json.loads(p.read_text(encoding="utf-8"))["photos"]


def reel_html():
    items = []
    for ph in sample_data():
        n = Path(ph["file"]).stem
        if not (SRC_SITE / "assets" / "photos" / f"{n}.jpg").exists():
            continue
        items.append(
            f'        <li><figure><img src="assets/photos/{n}.jpg" alt="{html.escape(SAMPLE_ALTS.get(n, ph["title"]))}" width="1000" height="667" loading="lazy" decoding="async">'
            f'<figcaption><strong>{html.escape(ph["title"])}</strong><span>{html.escape(SAMPLE_CAPTIONS.get(n, ph["blurb"]))}</span></figcaption></figure></li>')
    return f"""  <section class="reel-section" aria-labelledby="h-reel">
    <div class="wrap">
      <div class="reel-head">
        <h2 id="h-reel">Start from your own photo, or one of ours</h2>
        <p>Lustra comes with sample photos so you can try it right away. These are some of them. Each one shows hair from behind, so nobody can be identified.</p>
      </div>
      <ul class="reel">
{chr(10).join(items)}
      </ul>
      <p class="small reel-note">Sample photos are by Pexels photographers and are used under the Pexels License. See the <a href="licenses/">licences page</a> for credits.</p>
    </div>
  </section>
"""


def palette_html():
    tiles = [("original", "Original", "#3A2626"), ("rose", "Rose gold", "#B0685C"), ("plum", "Plum", "#6230 86"), ("copper", "Copper", "#B65826")]
    tiles[2] = ("plum", "Plum", "#623086")
    alts = {
        "original": "Long dark brown hair seen from behind, the unchanged sample photo",
        "rose": "The same photo with a rose-gold colour overlay on the hair",
        "plum": "The same photo with a plum colour overlay on the hair",
        "copper": "The same photo with a copper colour overlay on the hair",
    }
    items = "\n".join(
        f'        <li><figure><img src="assets/recolour/{k}.jpg" alt="{alts[k]}" width="720" height="926" loading="lazy" decoding="async">'
        f'<figcaption><i style="background:{c}" aria-hidden="true"></i>{label}</figcaption></figure></li>' for k, label, c in tiles)
    return f"""  <section class="palette-section" aria-labelledby="h-palette">
    <div class="wrap">
      <div class="palette-head">
        <h2 id="h-palette">One photo, as many colours as you like</h2>
        <p>Lustra's compare grid shows several colours on the same photo at once, so you can choose before you export. One grid is one picture and one ad.</p>
      </div>
      <ul class="palette">
{items}
      </ul>
      <p class="small palette-note">Illustration: a plain colour overlay added to one sample photo for this page. These are not screenshots from the app, and the app's result will differ.</p>
    </div>
  </section>
"""


SHOT_ALTS = [
    "Lustra on iPhone: the Home screen with sample photos",
    "Lustra on iPhone: choosing a hair colour",
    "Lustra on iPhone: an ombre colour style",
    "Lustra on iPhone: a balayage colour style",
    "Lustra on iPhone: a highlights colour style",
    "Lustra on iPhone: the palette compare grid",
]


def shots_html():
    shots = sorted((SRC_SITE / "assets" / "shots").glob("*.jpg")) if (SRC_SITE / "assets" / "shots").exists() else []
    if not shots:
        return ""
    items = "\n".join(f'        <li><img src="assets/shots/{p.name}" alt="{html.escape(SHOT_ALTS[i - 1] if i <= len(SHOT_ALTS) else "Lustra on iPhone")}" width="660" loading="lazy" decoding="async"></li>'
                      for i, p in enumerate(shots, 1))
    return f"""  <section class="reel-section" aria-labelledby="h-shots">
    <div class="wrap">
      <div class="reel-head"><h2 id="h-shots">See it in the app</h2></div>
      <ul class="shots">
{items}
      </ul>
    </div>
  </section>
"""


def build_index():
    title = "Hair Color Changer: Lustra | Try on dye, ombre and highlights"
    desc = "Free hair colour try-on for iPhone and iPad. Try natural and fashion colours, ombre, balayage and highlights on your own photo, compare colours in a grid and save your favourite looks. Made on your device, with no account."
    faq_html = "\n".join(
        f'        <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in FAQ)

    body = head(title, desc, "", jsonld_app() + jsonld_faq(), root="") + header("", "") + f"""
<main id="main">
  <section class="hero" aria-labelledby="h1">
    <div class="wrap">
      <div>
        <h1 id="h1">Try a new hair colour before you commit.</h1>
        <p class="lede">Lustra finds the hair in your photo, then lets you test natural shades, bold colours, ombre, balayage and highlights. It is free, there is no account, and your photos never leave your device.</p>
        <p class="status">Not on the App Store yet</p>
        <p class="small hero-note">There is no download link yet. Questions are welcome on the <a href="support/">support page</a>.</p>
      </div>
      <figure class="compare">
        <div class="frame">
          <img src="assets/recolour/split.jpg" width="900" height="1157" alt="A sample photo of long dark hair seen from behind. The left half is the original photo. The right half has a rose-gold colour overlay on the hair.">
          <span class="tag l">Original</span><span class="tag r">Colour overlay</span>
        </div>
        <figcaption>Illustration: a plain colour overlay added to a Pexels sample photo. Not a screenshot from the app.</figcaption>
      </figure>
    </div>
  </section>

{palette_html()}
{reel_html()}
{shots_html()}
  <section class="section" id="colour" aria-labelledby="h-colour">
    <div class="wrap">
      <h2 id="h-colour">Colour you can direct</h2>
      <div class="section-body">
        <dl class="defs">
          <div><dt>Natural shades, fashion colours, or your own</dt><dd>Start from a natural shade, go bold with a fashion colour, or pick any colour yourself. The colour keeps the light, shadow and shine of your photo, so it looks like hair and not like paint.</dd></div>
          <div><dt>Solid, ombre, balayage, highlights</dt><dd>Colour all of the hair, blend one colour into another from roots to ends, add a hand-painted balayage with lighter ends, or add lighter streaks through your colour.</dd></div>
          <div><dt>Two-tone and root shadow</dt><dd>Split the hair into two colours, or add a darker root that grows into your colour.</dd></div>
          <div><dt>Intensity, shine and brightness</dt><dd>Go from a soft tint to a bold change, add or remove shine, and lift or deepen the colour.</dd></div>
          <div><dt>Gray cover</dt><dd>See how colour looks over gray roots and gray hair.</dd></div>
          <div><dt>Finishing touches</dt><dd>Soften frizz and bring out strand definition. These edits apply to the hair only, not to the rest of your photo.</dd></div>
        </dl>
        <p class="disclaimer">Lustra is for hair colour only. It does not add a haircut, bangs, curls or a wig.</p>
      </div>
    </div>
  </section>

  <section class="section band" id="compare" aria-labelledby="h-compare">
    <div class="wrap">
      <h2 id="h-compare">Compare, refine, keep</h2>
      <div class="section-body">
        <p>Decide with your eyes. Drag the before and after slider, or put several colours side by side in the compare grid.</p>
        <ul class="checks">
          <li>Before and after slider on the same photo</li>
          <li>Compare grid: several colours at once, exported as one picture</li>
          <li>Refine brush: add hair the detection missed, or remove colour from the wrong spot</li>
          <li>Hints when a photo may be blurry, dark, very small, or has a hat or scarf over the hair</li>
          <li>A choice of faces when more than one person is in the photo</li>
          <li>Undo and redo for every edit</li>
          <li>Saved looks: keep the colours you love on your device and open them again on another photo</li>
          <li>Save to Photos, save to Files, or share. No watermark</li>
        </ul>
      </div>
    </div>
  </section>

  <section class="section" id="private" aria-labelledby="h-private">
    <div class="wrap">
      <h2 id="h-private">Your photos never leave your device</h2>
      <div class="section-body">
        <p>Lustra has no account and no server that stores your pictures. Hair detection and every colour change are made on your phone or iPad. We do not run analytics of our own.</p>
        <ul class="checks">
          <li>You pick photos with the iOS photo picker, so Lustra sees only what you choose</li>
          <li>Saving to your library uses add-only permission</li>
          <li>Hair detection runs on the device with an open model and Apple's face detection</li>
          <li>Saved looks stay on your device and can be deleted in the app</li>
          <li>No account, no sign-in, no subscription</li>
        </ul>
        <p>The only outside service is the ad network. The <a href="privacy/">privacy policy</a> explains what it collects.</p>
      </div>
    </div>
  </section>

  <section class="section band" id="free" aria-labelledby="h-free">
    <div class="wrap">
      <h2 id="h-free">Free, and paid for by ads</h2>
      <div class="section-body">
        <p>Lustra has no subscription and no in-app purchase. Ads from Google AdMob pay for it, and they appear in two places.</p>
        <div class="split">
          <div>
            <h3>Where you will see ads</h3>
            <ul>
              <li>A banner on the Home screen. Never over the editing controls.</li>
              <li>One short rewarded video before each export. You choose whether to watch it, and a comparison grid counts as one export.</li>
            </ul>
          </div>
          <div>
            <h3>When no ad is available</h3>
            <ul>
              <li>The export goes ahead for free.</li>
              <li>This happens, for example, when you are offline.</li>
            </ul>
          </div>
        </div>
        <p>Where the law asks for it, the app shows a consent form from Google before personalised ads, and iOS may ask whether the app may track you. Lustra itself runs no analytics, and the only tracking that can happen is through Google's ad software, and only if you allow it. You can say no to the iOS prompt and still use everything.</p>
      </div>
    </div>
  </section>

  <section class="section faq" id="faq" aria-labelledby="h-faq">
    <div class="wrap">
      <h2 id="h-faq">Questions</h2>
      <div class="section-body">
{faq_html}
      </div>
    </div>
  </section>
</main>
""" + footer("")
    (OUT / "index.html").write_text(body, encoding="utf-8", newline="\n")


# ----------------------------------------------------------------------------- support
def build_support():
    title = "Support | Hair Color Changer: Lustra"
    desc = "Get help with Lustra: contact details, and answers about trying a hair colour, photos the app cannot read well, exporting, ads and your saved looks."
    items = [
        ("How do I try a hair colour?",
         "<ol><li>Choose a photo, or one of the sample photos, on the Home screen. A photo of one person where the hair is clearly visible works best.</li><li>Wait a moment while Lustra finds the hair on your device.</li><li>Pick a colour, then pick a style: solid, ombre, balayage, highlights, two-tone or root shadow.</li><li>Use the intensity, shine and brightness sliders to adjust it.</li><li>Drag the before and after slider to check the change, then save or share.</li></ol>"),
        ("The colour went onto the wrong place, or missed some hair",
         "<p>Use the refine brush. Choose Add to paint hair that was missed, or Remove to take colour off a spot that is not hair, such as a scarf or the background. You can undo any stroke. Photos that are sharp, evenly lit and show the hair clearly give the cleanest result. Hats, scarves, hoods, strong shadows and busy backgrounds make detection harder.</p>"),
        ("Lustra shows a hint about my photo",
         "<p>The app tells you when a photo is blurry, dark, very small, or has no clear face, and when a hat or scarf may cover the hair. You can still continue. If the photo has more than one person, choose the one you want to edit. For the best result, try a brighter photo with the hair in full view.</p>"),
        ("Why am I asked to watch an ad?",
         "<p>Lustra is free, and ads pay for it. Before you export, the app offers one short video that you choose to watch. One watched ad covers one export, and a comparison grid counts as one export. If you choose Not now, nothing is exported and you can try again any time. If no ad is available, for example when you are offline or your ad privacy choice does not allow ads, the export goes ahead without one. Editing never needs an ad.</p>"),
        ("Where are my saved looks?",
         "<p>Saved looks are kept on your device only. You can open them again on another photo and delete them in the app. If you delete the app, they cannot be recovered by us. Pictures you exported to Photos or Files are not affected. A full backup of your device may still contain the app's data if you made one before deleting it.</p>"),
        ("Can Lustra change my hairstyle or haircut?",
         "<p>No. Lustra changes the colour of hair that is already in your photo. It does not add bangs, curls, a haircut or a wig.</p>"),
        ("I saw an ad that seems wrong",
         "<p>Write to us at the address above. Tell us roughly when and where in the app you saw it and what it showed. A screenshot helps. We block ad categories and advertisers through Google AdMob where we can.</p>"),
        ("I want to change my ad or tracking choice",
         "<p>Open Settings in the app and look for the Ad privacy choices row, which appears where the law requires it. You can also change tracking in iOS Settings under Privacy and Security, then Tracking, and reset your advertising identifier there.</p>"),
        ("I have an idea for a colour or a style",
         "<p>Send it. We read every message, though we cannot promise to build every idea.</p>"),
    ]
    faq_html = "\n".join(f'          <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in items)
    body = head(title, desc, "support/", root="../") + header("../", "support") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <div class="doc">
        <h1>Support</h1>
        <p class="lede">Write to us and a person will read it.</p>
        <p class="contact-line">{EMAIL_TEXT}</p>
        <p class="small">Select the address to copy it into your mail app.</p>
        <p>We reply by email. A message gets answered faster when it includes:</p>
        <ul>
          <li>your iPhone or iPad model and iOS or iPadOS version</li>
          <li>what you were doing and what happened</li>
          <li>a screenshot, if it helps</li>
        </ul>
        <p>Lustra is not on the App Store yet, so support right now covers questions about the app before it is available.</p>
        <h2>Common questions</h2>
        <div class="faq">
{faq_html}
        </div>
        <h2>Company</h2>
        <p>Ecom Swift LLC<br>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
        <p>Read the <a href="../privacy/">privacy policy</a>, the <a href="../terms/">terms of use</a> and the <a href="../licenses/">licences</a>.</p>
      </div>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / "support").mkdir(exist_ok=True)
    (OUT / "support" / "index.html").write_text(body, encoding="utf-8", newline="\n")


# ----------------------------------------------------------------------------- legal (markdown -> html)
URL_RE = re.compile(r"(https?://[^\s<)]+)")
MAIL_RE = re.compile(r"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})")


def inline(text):
    t = html.escape(text, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)

    def url(m):
        u = m.group(1)
        trail = ""
        while u and u[-1] in ".,;":
            trail = u[-1] + trail
            u = u[:-1]
        return f'<a href="{u}" rel="noopener">{u}</a>{trail}'

    t = URL_RE.sub(url, t)
    parts = re.split(r"(<a .*?</a>)", t)
    parts = [p if p.startswith("<a ") else MAIL_RE.sub(r'<span class="email">\1</span>', p) for p in parts]
    return "".join(parts)


def md_to_html(md):
    md = re.sub(r"<!-- DRAFT-NOTICE-START -->.*?<!-- DRAFT-NOTICE-END -->", "", md, flags=re.S)
    out, para, items = [], [], []
    title = ""
    meta_open = False
    seen_h2 = False

    def flush_para():
        nonlocal para
        if para:
            out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>")
            para = []

    def flush_list():
        nonlocal items
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items = []

    for raw in md.splitlines():
        line = raw.rstrip()
        if line.startswith("# "):
            flush_para(); flush_list()
            title = line[2:].strip()
            out.append(f"<h1>{html.escape(title)}</h1>")
        elif line.startswith("## "):
            flush_para(); flush_list()
            if meta_open:
                out.append("</div>"); meta_open = False
            seen_h2 = True
            out.append(f"<h2>{inline(line[3:].strip())}</h2>")
        elif line.startswith("- "):
            flush_para()
            items.append(line[2:].strip())
        elif not line.strip():
            flush_para(); flush_list()
        elif line.startswith("**") and title and not seen_h2:
            if not meta_open:
                out.append('<div class="meta">'); meta_open = True
            out.append("<p>" + inline(line) + "</p>")
        else:
            flush_list()
            if meta_open:
                out.append("</div>"); meta_open = False
            para.append(line.strip())
    flush_para(); flush_list()
    if meta_open:
        out.append("</div>")
    return title, "\n".join(out)


def build_legal(src, folder, current_title, desc):
    md = (LEGAL / src).read_text(encoding="utf-8")
    title, content = md_to_html(md)
    page_title = f"{current_title} | {SITE_NAME}"
    body = head(page_title, desc, folder + "/", root="../") + header("../", "") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <article class="doc">
{content}
      </article>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / folder).mkdir(exist_ok=True)
    (OUT / folder / "index.html").write_text(body, encoding="utf-8", newline="\n")


# ----------------------------------------------------------------------------- licences
def credits_rows():
    p = ROOT / "docs" / "store" / "photo-credits.md"
    if not p.exists():
        return []
    text = p.read_text(encoding="utf-8")
    a = text.index("## Bundled sample photos")
    b = text.index("## CI test portraits") if "## CI test portraits" in text else len(text)
    rows = []
    for line in text[a:b].splitlines():
        if line.startswith("|") and not line.startswith("|---") and not line.startswith("| File"):
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            rows.append((c[0], c[2], c[1]))
    return rows


def apache_text():
    p = ROOT / "docs" / "licences" / "hair-segmenter.md"
    if not p.exists():
        return ""
    t = p.read_text(encoding="utf-8")
    m = re.search(r"## Apache License 2\.0.*?```text\n(.*?)\n```", t, flags=re.S)
    return m.group(1) if m else ""


def build_licenses():
    title = "Licences | Hair Color Changer: Lustra"
    desc = "Open-source and third-party notices for Lustra: the MediaPipe hair segmenter (Apache License 2.0), Google Mobile Ads and the sample photo credits from Pexels."
    rows = credits_rows()
    table = "\n".join(
        f'<tr><td>{html.escape(f)}</td><td>{html.escape(ph)}</td><td><a href="{html.escape(u)}" rel="noopener">Pexels page</a></td></tr>' for f, ph, u in rows)
    apache = apache_text()
    apache_block = (f'<details class="fold"><summary>Apache License 2.0, full text</summary><pre class="licence-text" tabindex="0">{html.escape(apache)}</pre></details>'
                    if apache else '<p>The full text is at <a href="https://www.apache.org/licenses/LICENSE-2.0.txt" rel="noopener">https://www.apache.org/licenses/LICENSE-2.0.txt</a>.</p>')
    body = head(title, desc, "licenses/", root="../") + header("../", "") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <article class="doc">
        <h1>Licences</h1>
        <p class="lede">Lustra uses a few things made by others. Here is what they are and under which terms.</p>

        <h2>MediaPipe hair segmenter</h2>
        <p>Lustra finds hair with a Core ML conversion of the MediaPipe hair segmenter, made by Google LLC and released under the Apache License, Version 2.0. The model runs on your device. We changed only its file format and made mathematically exact simplifications: the three custom layers were rebuilt from standard operations, an unused input channel was dropped, and the two output classes were merged into one. We did not retrain or fine-tune it. The changes are listed in <a href=\"https://github.com/EcomswiftLLC/hairtryon-ios/blob/main/docs/licences/hair-segmenter.md\" rel=\"noopener\">our public licence notes</a>. The weights are used under the Apache License, Version 2.0.</p>
        <p>Source: <a href="https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter" rel="noopener">developers.google.com/edge/mediapipe</a>. The model card asks to cite: A. Tkachenka, G. Karpushin, A. Vakunov and V. Tkachenka, "Real-time Hair Segmentation and Recoloring on Mobile GPUs", CVPR Workshop on Computer Vision for Augmented and Virtual Reality, 2019.</p>
        <p>The model was built for single-person selfies. It can be less reliable with several people, hats and scarves, thin or braided hair, low light and motion blur, which is why Lustra offers a refine brush.</p>
        {apache_block}

        <h2>Google Mobile Ads SDK and User Messaging Platform</h2>
        <p>Lustra shows ads with the Google Mobile Ads SDK (Google AdMob) and asks for consent where required with Google's User Messaging Platform SDK. Both are provided by Google LLC under Google's own terms, not as open-source software. They include third-party notices that Google publishes with the SDKs. See the <a href="https://developers.google.com/admob/terms" rel="noopener">Google AdMob terms</a>, the <a href="https://developers.google.com/admob/ios/quick-start" rel="noopener">Google Mobile Ads SDK for iOS</a> pages and the <a href="https://policies.google.com/privacy" rel="noopener">Google Privacy Policy</a>. What the SDK collects is explained in our <a href="../privacy/">privacy policy</a>.</p>

        <h2>Apple frameworks</h2>
        <p>Lustra uses system frameworks from Apple, such as Vision for face detection, Core ML, the photo picker and the share sheet, under Apple's developer terms.</p>

        <h2>Sample photos</h2>
        <p>The photos built into the app are from <a href="https://www.pexels.com" rel="noopener">Pexels</a> and are used under the <a href="https://www.pexels.com/license/" rel="noopener">Pexels License</a>, which allows free use including commercial use and modification. Attribution is not required, and we credit the photographers here. The photos were resized and recompressed, with no other edits. The coloured pictures on the home page are illustrations made from one of these photos with a simple colour overlay.</p>
        <table>
          <thead><tr><th>File</th><th>Photographer</th><th>Source</th></tr></thead>
          <tbody>
{table}
          </tbody>
        </table>

        <h2>Questions</h2>
        <p>If you think a notice is missing or wrong, write to {EMAIL_TEXT}.</p>
      </article>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / "licenses").mkdir(exist_ok=True)
    (OUT / "licenses" / "index.html").write_text(body, encoding="utf-8", newline="\n")


def build_misc():
    urls = ["", "support/", "privacy/", "terms/", "licenses/"]
    xml = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for u in urls:
        xml.append(f"  <url><loc>{BASE}{u}</loc><lastmod>{UPDATED}</lastmod></url>")
    xml.append("</urlset>")
    (OUT / "sitemap.xml").write_text("\n".join(xml) + "\n", encoding="utf-8", newline="\n")
    (OUT / "robots.txt").write_text(
        "# Hosted on GitHub Pages as a project path under /lustra/.\n"
        "User-agent: *\nAllow: /\n\n"
        f"Sitemap: {BASE}sitemap.xml\n", encoding="utf-8", newline="\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if OUT != SRC_SITE:  # review build elsewhere: bring the assets along
        shutil.copytree(SRC_SITE / "assets", OUT / "assets", dirs_exist_ok=True)
    build_index()
    build_support()
    build_legal("privacy-policy.md", "privacy", "Privacy Policy",
                "How Hair Color Changer: Lustra handles information: photos are processed on your device and never uploaded, there is no account, and ads come from Google AdMob with your consent where required.")
    build_legal("terms-of-use.md", "terms", "Terms of Use",
                "The terms for using Hair Color Changer: Lustra, a free hair colour try-on supported by ads.")
    build_licenses()
    build_misc()
    print("site built in", OUT)


if __name__ == "__main__":
    main()
