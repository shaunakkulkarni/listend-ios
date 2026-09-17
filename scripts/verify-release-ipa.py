#!/usr/bin/env python3
"""Inspect a Listend IPA without installing or uploading it.

Usage: python3 scripts/verify-release-ipa.py /path/Listend.ipa --build 7
Checks package metadata and privacy declarations; does not certify device behavior.
"""

import argparse
import plistlib
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--build", required=True)
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as archive:
        def read(path):
            return plistlib.loads(archive.read(path))

        app = "Payload/Listend.app/"
        extension = app + "PlugIns/ListendShareExtension.appex/"
        info = read(app + "Info.plist")
        ext = read(extension + "Info.plist")
        assert info["CFBundleIdentifier"] == "com.shaunakkulkarni.Listend"
        assert ext["CFBundleIdentifier"] == "com.shaunakkulkarni.Listend.ShareExtension"
        assert info["CFBundleVersion"] == ext["CFBundleVersion"] == args.build
        assert info["CFBundleShortVersionString"] == ext["CFBundleShortVersionString"]
        assert info.get("NSAppleMusicUsageDescription", "").strip()
        for root in (app, extension):
            privacy = read(root + "PrivacyInfo.xcprivacy")
            assert privacy["NSPrivacyTracking"] is False
            assert privacy["NSPrivacyTrackingDomains"] == []
            assert privacy["NSPrivacyCollectedDataTypes"] == []
            assert root + "embedded.mobileprovision" in archive.namelist()
        reasons = read(app + "PrivacyInfo.xcprivacy")["NSPrivacyAccessedAPITypes"]
        assert any(x["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults"
                   and "CA92.1" in x["NSPrivacyAccessedAPITypeReasons"] for x in reasons)
        assert not any("Listend Sandbox.app/" in n for n in archive.namelist())
        print(f"PASS: Listend {info['CFBundleShortVersionString']} ({args.build}), "
              f"minimum iOS {info['MinimumOSVersion']}, matching extension, usage text, "
              "provisioning files, and privacy manifests.")


if __name__ == "__main__":
    main()
