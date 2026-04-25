#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
from pathlib import Path
from email.utils import formatdate

ROOT = Path(__file__).resolve().parent.parent
HOMEBREW_CASK = ROOT / "homebrew-tap" / "Casks" / "notchera.rb"
APPCAST_PATH = ROOT / "website-repo" / "apps" / "www" / "public" / "appcast.xml"
APP_PATH = ROOT / ".derived-data-release-dist" / "Build" / "Products" / "Release" / "Notchera.app"
DMG_PATH = ROOT / "Notchera.dmg"
BREW_ZIP_PATH = ROOT / "Notchera-brew.zip"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_size(path: Path) -> int:
    return path.stat().st_size


def read_signature() -> str:
    signature = os.environ.get("SPARKLE_ED_SIGNATURE", "").strip()
    if not signature:
        raise SystemExit("missing SPARKLE_ED_SIGNATURE")
    return signature


def write_cask(marketing_version: str) -> None:
    HOMEBREW_CASK.parent.mkdir(parents=True, exist_ok=True)
    HOMEBREW_CASK.write_text(
        f'''cask "notchera" do
  version "{marketing_version}"
  sha256 "{sha256(BREW_ZIP_PATH)}"

  url "https://github.com/berkinory/Notchera/releases/download/v#{{version}}/Notchera-brew.zip"
  name "Notchera"
  desc "Dynamic notch companion for macOS"
  homepage "https://notchera.app"

  app "Notchera.app"
end
'''
    )


def minimum_system_version() -> str:
    info_plist = APP_PATH / "Contents" / "Info.plist"
    with info_plist.open("rb") as file:
        info = plistlib.load(file)
    return str(info.get("LSMinimumSystemVersion") or "14.0")


def write_appcast(marketing_version: str, build_version: str) -> None:
    APPCAST_PATH.parent.mkdir(parents=True, exist_ok=True)
    APPCAST_PATH.write_text(
        f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Notchera</title>
    <link>https://notchera.app</link>
    <description>Notchera updates</description>
    <language>en</language>
    <item>
      <title>Version {marketing_version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <description><![CDATA[
        <p>Notchera {marketing_version} is now available.</p>
      ]]></description>
      <sparkle:version>{build_version}</sparkle:version>
      <sparkle:shortVersionString>{marketing_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum_system_version()}</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/berkinory/Notchera/releases/download/v{marketing_version}/Notchera.dmg"
        sparkle:version="{build_version}"
        sparkle:shortVersionString="{marketing_version}"
        sparkle:edSignature="{read_signature()}"
        length="{file_size(DMG_PATH)}"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
'''
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-version", required=True)
    parser.add_argument("--target", choices=["cask", "appcast", "all"], default="all")
    args = parser.parse_args()

    if args.target in {"cask", "all"}:
        write_cask(args.marketing_version)
    if args.target in {"appcast", "all"}:
        write_appcast(args.marketing_version, args.build_version)


if __name__ == "__main__":
    main()
