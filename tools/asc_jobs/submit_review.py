"""Sets manual release and submits version 1.0 for App Review. Owner approved 2026-11-25 ("submit now").

Guards: build must be VALID and attached, both screenshot sets COMPLETE, no review submission already open.
"""
import sys

from asc import api, pages

APP_ID = "6839164457"
versions = list(pages(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS"))
v = versions[0]
vid = v["id"]
print("version", vid, v["attributes"]["versionString"], v["attributes"]["appStoreState"])
if v["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
    sys.exit("not in PREPARE_FOR_SUBMISSION, stopping")

st, data = api("GET", f"/v1/appStoreVersions/{vid}/build")
b = (data or {}).get("data")
if not b or b["attributes"].get("processingState") != "VALID" or b["attributes"].get("expired"):
    sys.exit("no valid attached build, stopping")
print("build", b["attributes"]["version"], "VALID")

for loc in pages(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"):
    for s in pages(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
        shots = list(pages(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"))
        if len(shots) != 10 or any(x["attributes"].get("assetDeliveryState", {}).get("state") != "COMPLETE" for x in shots):
            sys.exit("screenshots not complete in " + s["attributes"]["screenshotDisplayType"])

st, subs = api("GET", f"/v1/apps/{APP_ID}/reviewSubmissions?limit=20")
open_subs = [r for r in (subs or {}).get("data", []) if r["attributes"].get("state") not in ("COMPLETE", "CANCELING")]
print("existing submissions", [(r["id"], r["attributes"].get("state")) for r in (subs or {}).get("data", [])])

# Manual release after approval.
st, _ = api("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "MANUAL"}}})
print("releaseType MANUAL", st)
if st not in (200, 201):
    sys.exit("could not set manual release, stopping")

reuse = [r for r in open_subs if r["attributes"].get("state") == "READY_FOR_REVIEW"]
if open_subs and not reuse:
    sys.exit("a review submission is already in progress, stopping")
if reuse:
    sid = reuse[0]["id"]
    print("reusing empty submission", sid)
else:
    st, d = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    print("create submission", st)
    if st not in (200, 201):
        sys.exit(str(d)[:600])
    sid = d["data"]["id"]
print("submission", sid)

st, d = api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
    "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                      "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
print("add item", st)
if st not in (200, 201):
    sys.exit(str(d)[:1500])

st, d = api("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
print("submit", st)
if st not in (200, 201):
    sys.exit(str(d)[:1500])

st, d = api("GET", f"/v1/reviewSubmissions/{sid}")
print("submission state", (d or {}).get("data", {}).get("attributes", {}).get("state"), (d or {}).get("data", {}).get("attributes", {}).get("submittedDate"))
v2 = api("GET", f"/v1/appStoreVersions/{vid}")[1]["data"]["attributes"]
print("version state", v2.get("appStoreState"), v2.get("releaseType"))
print("done")
