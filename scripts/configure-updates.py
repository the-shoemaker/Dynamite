#!/usr/bin/env python3
"""Embed public release configuration only. No keys are generated or exported."""
import base64
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit


def configure(info, env):
    feed = env.get("DYNOMITE_FEED_URL", "")
    public_key = env.get("DYNOMITE_UPDATE_PUBLIC_KEY", "")
    if bool(feed) != bool(public_key):
        raise ValueError("Set both DYNOMITE_FEED_URL and DYNOMITE_UPDATE_PUBLIC_KEY.")
    if feed:
        url = urlsplit(feed)
        if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
            raise ValueError("The update feed must be an HTTPS URL without credentials or a fragment.")
        if len(base64.b64decode(public_key, validate=True)) != 32:
            raise ValueError("Sparkle's public Ed25519 key must contain 32 bytes.")
        info.update(SUFeedURL=feed, SUPublicEDKey=public_key,
                    SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=False,
                    SUSendProfileInfo=False)
    for variable, key in [("DYNOMITE_VERSION", "CFBundleShortVersionString"),
                          ("DYNOMITE_BUILD_NUMBER", "CFBundleVersion")]:
        if variable in env:
            value = env[variable]
            if not value or not all(part.isdigit() for part in value.split(".")):
                raise ValueError(f"{variable} must be a numeric version, for example 1.2.3.")
            info[key] = value
    return info


if __name__ == "__main__":
    path = Path(sys.argv[1])
    with path.open("rb") as file:
        info = plistlib.load(file)
    try:
        configure(info, os.environ)
    except (ValueError, TypeError) as error:
        sys.exit(str(error))
    with path.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)
