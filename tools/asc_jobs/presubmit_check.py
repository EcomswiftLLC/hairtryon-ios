"""Read-only pre-submit check: version state, attached build, screenshots, existing review submissions."""
from asc import api, pages

APP_ID = "6839164457"
versions = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))
for v in versions:
    print("version", v["id"], v["attributes"].get("versionString"), v["attributes"].get("appStoreState"), v["attributes"].get("releaseType"))
vid = versions[0]["id"]

st, data = api("GET", f"/v1/appStoreVersions/{vid}/build")
b = (data or {}).get("data")
if b:
    a = b["attributes"]
    print("attached build", a.get("version"), a.get("processingState"), "expired" if a.get("expired") else "not expired", "nonExemptEncryption=", a.get("usesNonExemptEncryption"))
else:
    print("NO BUILD ATTACHED", st)

for loc in pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"):
    print("locale", loc["attributes"]["locale"], "desc chars", len(loc["attributes"].get("description") or ""), "keywords", len(loc["attributes"].get("keywords") or ""))
    for s in pages(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
        shots = list(pages(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"))
        states = [x["attributes"].get("assetDeliveryState", {}).get("state") for x in shots]
        print("  set", s["attributes"]["screenshotDisplayType"], len(shots), sorted(set(states)))

print("-- review submissions")
st, data = api("GET", f"/v1/apps/{APP_ID}/reviewSubmissions?limit=20")
print("status", st)
for r in (data or {}).get("data", []):
    print("submission", r["id"], r["attributes"].get("state"), r["attributes"].get("platform"), r["attributes"].get("submittedDate"))
print("done")
