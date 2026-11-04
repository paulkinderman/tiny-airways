"""Revoke the team's development certificates before an archive.

Each CI run starts on a fresh Mac, so Xcode's automatic signing makes a new
development certificate every time (the private key of the last one is
gone with the old runner). Apple caps how many a team can hold, and once the
cap is reached the archive fails with "Your account has reached the maximum
number of certificates". The old ones can never be used again, so revoke
them. TestFlight builds already uploaded are not affected: they are signed
with the cloud-managed distribution certificate.

Needs KEY_ID, ISSUER and ASC_KEY_PATH in the environment.
"""

import json
import os
import time
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER"], "iat": now, "exp": now + 600,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["KEY_ID"]})


def call(method, url, auth):
    req = urllib.request.Request(
        url, method=method, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
    return json.loads(body) if body else None


def main():
    auth = token()
    certs = call(
        "GET",
        f"{API}/certificates"
        "?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200",
        auth)["data"]
    print(f"Found {len(certs)} development certificate(s).")
    for cert in certs:
        attrs = cert["attributes"]
        name = attrs.get("name") or attrs.get("displayName")
        call("DELETE", f"{API}/certificates/{cert['id']}", auth)
        print(f"Revoked {name} ({cert['id']}).")


if __name__ == "__main__":
    main()
