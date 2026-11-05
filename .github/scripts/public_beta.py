"""Share Tiny Airways through a TestFlight public link.

Sets up everything App Store Connect needs before anyone outside the team
can install a build, then hands the newest build to the public group:

1. Test information (beta description, feedback email, privacy policy URL).
2. Beta App Review contact details.
3. An external beta group named "Public" with a public link turned on.
4. The build: "What to Test" notes, added to the group, and submitted for
   Beta App Review if it hasn't been yet.

Every step checks what is already there first, so running it again is safe.
The public link is printed (and written to the job summary). Testers can join
through it once Apple approves the first build, usually within a day; later
builds of the same version are normally approved within minutes.

Environment:
  KEY_ID, ISSUER, ASC_KEY_PATH   App Store Connect API key (as for signing).
  BUNDLE_ID                      The app's bundle ID.
  BUILD_NUMBER                   Optional. Wait for this build (it may still
                                 be processing) instead of using the newest.
  PRIVACY_URL                    Privacy policy URL for the test information.
  CONTACT_FIRST, CONTACT_LAST, CONTACT_EMAIL, CONTACT_PHONE
                                 Optional Beta App Review contact. Name and
                                 email default to the team's Account Holder.
                                 Only fields empty in App Store Connect are
                                 filled.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
GROUP_NAME = "Public"
LOCALE = "en-US"
DESCRIPTION = (
    "Tiny Airways is a cartoon airline-management game. Buy small planes, "
    "open airports around the world, and fly passengers and cargo between "
    "them to grow your airline.")
WHATS_NEW = (
    "Thanks for testing Tiny Airways! Play as much as you like and tell us "
    "about anything that feels off: confusing screens, crashes, or balance "
    "that's too easy or too hard. Shake the phone or use the TestFlight app "
    "to send feedback with a screenshot.")
REVIEW_NOTES = (
    "Single-player offline game. No account or sign-in is needed: open the "
    "app and tap to play. Progress is saved on the device and synced through "
    "iCloud key-value storage.")


class ApiError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


_token = {"value": None, "at": 0}


def token():
    now = int(time.time())
    if _token["value"] is None or now - _token["at"] > 900:
        with open(os.environ["ASC_KEY_PATH"]) as f:
            key = f.read()
        _token["value"] = jwt.encode(
            {"iss": os.environ["ISSUER"], "iat": now, "exp": now + 1200,
             "aud": "appstoreconnect-v1"},
            key, algorithm="ES256", headers={"kid": os.environ["KEY_ID"]})
        _token["at"] = now
    return _token["value"]


def call(method, path, body=None, params=None):
    url = path if path.startswith("http") else f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode(errors="replace")) from None
    return json.loads(raw) if raw else None


def rel(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def find_app(bundle_id):
    apps = call("GET", "/apps", params={"filter[bundleId]": bundle_id})["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {bundle_id} in App Store Connect.")
    return apps[0]["id"]


def fill_contact_defaults():
    """Default the contact name and email to the team's Account Holder."""
    if all(os.environ.get(k) for k in ("CONTACT_FIRST", "CONTACT_LAST",
                                       "CONTACT_EMAIL")):
        return
    try:
        users = call("GET", "/users", params={"limit": 200})["data"]
    except ApiError as e:
        print(f"::warning::Could not list team users: {e}")
        return
    holder = next((u for u in users
                   if "ACCOUNT_HOLDER" in (u["attributes"].get("roles") or [])),
                  users[0] if users else None)
    if holder is None:
        return
    a = holder["attributes"]
    for env, value in (("CONTACT_FIRST", a.get("firstName")),
                       ("CONTACT_LAST", a.get("lastName")),
                       ("CONTACT_EMAIL", a.get("username"))):
        if value and not os.environ.get(env):
            os.environ[env] = value


def ensure_test_info(app_id):
    wanted = {
        "description": DESCRIPTION,
        "feedbackEmail": os.environ.get("CONTACT_EMAIL", ""),
        "privacyPolicyUrl": os.environ["PRIVACY_URL"],
    }
    locs = call("GET", f"/apps/{app_id}/betaAppLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if loc is None:
        call("POST", "/betaAppLocalizations", {"data": {
            "type": "betaAppLocalizations",
            "attributes": {"locale": LOCALE,
                           **{k: v for k, v in wanted.items() if v}},
            "relationships": {"app": rel("apps", app_id)},
        }})
        print("Added test information.")
        return
    missing = {k: v for k, v in wanted.items()
               if v and not loc["attributes"].get(k)}
    if missing:
        call("PATCH", f"/betaAppLocalizations/{loc['id']}", {"data": {
            "type": "betaAppLocalizations", "id": loc["id"],
            "attributes": missing,
        }})
        print(f"Filled test information: {', '.join(missing)}.")
    else:
        print("Test information already complete.")


def ensure_review_details(app_id):
    """Fill the Beta App Review contact. Returns False if it's incomplete.

    Apple rejects any change to these details without a contact phone, so
    with no phone known nothing is sent and the build isn't submitted.
    """
    detail = call("GET", f"/apps/{app_id}/betaAppReviewDetail")["data"]
    attrs = detail["attributes"]
    contact = {
        "contactFirstName": os.environ.get("CONTACT_FIRST", ""),
        "contactLastName": os.environ.get("CONTACT_LAST", ""),
        "contactEmail": os.environ.get("CONTACT_EMAIL", ""),
        "contactPhone": os.environ.get("CONTACT_PHONE", ""),
    }
    merged = {k: attrs.get(k) or v for k, v in contact.items()}
    gaps = [k for k, v in merged.items() if not v]
    if gaps:
        print(f"::warning::Beta App Review contact is missing {', '.join(gaps)},"
              " so the build can't be submitted for review yet. Add a"
              " BETA_CONTACT_PHONE repository secret (see docs/release.md).")
        return False
    update = {k: v for k, v in merged.items() if attrs.get(k) != v}
    if not attrs.get("notes"):
        update["notes"] = REVIEW_NOTES
    if attrs.get("demoAccountRequired") is not False:
        update["demoAccountRequired"] = False
    if update:
        # Apple wants the phone on every change, even when it's already set.
        update["contactPhone"] = merged["contactPhone"]
        call("PATCH", f"/betaAppReviewDetails/{detail['id']}", {"data": {
            "type": "betaAppReviewDetails", "id": detail["id"],
            "attributes": update,
        }})
        print(f"Filled review details: {', '.join(sorted(update))}.")
    else:
        print("Review details already complete.")
    return True


def ensure_group(app_id):
    groups = call("GET", f"/apps/{app_id}/betaGroups",
                  params={"limit": 200})["data"]
    group = next((g for g in groups if g["attributes"]["name"] == GROUP_NAME
                  and not g["attributes"].get("isInternalGroup")), None)
    if group is None:
        group = call("POST", "/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "publicLinkEnabled": True,
                           "publicLinkLimitEnabled": False,
                           "feedbackEnabled": True},
            "relationships": {"app": rel("apps", app_id)},
        }})["data"]
        print(f'Created the "{GROUP_NAME}" group.')
    attrs = group["attributes"]
    if not attrs.get("publicLinkEnabled") or attrs.get("publicLinkLimitEnabled"):
        group = call("PATCH", f"/betaGroups/{group['id']}", {"data": {
            "type": "betaGroups", "id": group["id"],
            "attributes": {"publicLinkEnabled": True,
                           "publicLinkLimitEnabled": False},
        }})["data"]
        print("Turned the public link on.")
    return group


def pick_build(app_id):
    wanted = os.environ.get("BUILD_NUMBER", "").strip()
    deadline = time.time() + (45 * 60 if wanted else 0)
    while True:
        params = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 20,
                  "filter[expired]": "false"}
        if wanted:
            params["filter[version]"] = wanted
        builds = call("GET", "/builds", params=params)["data"]
        for b in builds:
            state = b["attributes"]["processingState"]
            if state == "VALID":
                print(f"Using build {b['attributes']['version']}.")
                return b
            if wanted and state in ("FAILED", "INVALID"):
                sys.exit(f"Build {wanted} failed processing ({state}).")
        if time.time() > deadline:
            sys.exit(f"No processed build {wanted or ''} found yet.".replace("  ", " "))
        print(f"Build {wanted} is still processing; checking again in a minute.")
        time.sleep(60)


def ensure_whats_new(build_id):
    locs = call("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if loc is None:
        call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": LOCALE, "whatsNew": WHATS_NEW},
            "relationships": {"build": rel("builds", build_id)},
        }})
    elif not loc["attributes"].get("whatsNew"):
        call("PATCH", f"/betaBuildLocalizations/{loc['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": loc["id"],
            "attributes": {"whatsNew": WHATS_NEW},
        }})


def add_and_submit(group_id, build_id, can_submit):
    call("POST", f"/betaGroups/{group_id}/relationships/builds",
         {"data": [{"type": "builds", "id": build_id}]})
    detail = call("GET", f"/builds/{build_id}/buildBetaDetail")["data"]
    state = detail["attributes"].get("externalBuildState")
    print(f"Build is in the group; external state {state}.")
    if state != "READY_FOR_BETA_SUBMISSION" or not can_submit:
        return state
    try:
        call("POST", "/betaAppReviewSubmissions", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": rel("builds", build_id)},
        }})
    except ApiError as e:
        print(f"::warning::Beta App Review submission was refused: {e.body}")
        return state
    print("Submitted the build for Beta App Review.")
    return "WAITING_FOR_BETA_REVIEW"


def main():
    app_id = find_app(os.environ["BUNDLE_ID"])
    fill_contact_defaults()
    ensure_test_info(app_id)
    can_submit = ensure_review_details(app_id)
    group = ensure_group(app_id)
    build = pick_build(app_id)
    ensure_whats_new(build["id"])
    state = add_and_submit(group["id"], build["id"], can_submit)

    group = call("GET", f"/betaGroups/{group['id']}")["data"]
    link = group["attributes"].get("publicLink")
    summary = [f"**Public TestFlight link:** {link}",
               f"Build {build['attributes']['version']}: {state}"]
    print("\n".join(summary))
    out = os.environ.get("GITHUB_STEP_SUMMARY")
    if out:
        with open(out, "a") as f:
            f.write("\n\n".join(summary) + "\n")
    if not link:
        sys.exit("The group has no public link yet.")
    if not can_submit:
        sys.exit("Public link is set up, but the build wasn't submitted for"
                 " review: the review contact needs a phone number.")


if __name__ == "__main__":
    try:
        main()
    except ApiError as e:
        sys.exit(f"App Store Connect refused a request: {e}")
