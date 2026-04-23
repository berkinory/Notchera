#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "Notchera.xcodeproj"
SCHEME = "Notchera"
DESTINATION = "platform=macOS"
DERIVED_DATA = ROOT / ".derived-data-release-dist"
SOURCE_PACKAGES = DERIVED_DATA / "SourcePackages"
APP_PATH = DERIVED_DATA / "Build" / "Products" / "Release" / "Notchera.app"
DMG_OUTPUT = ROOT / "Notchera.dmg"
VOLUME_NAME = "Notchera"
NOTARY_PROFILE = "notary-profile"
BACKGROUND_TIFF = ROOT / "Configuration" / "dmg" / ".background" / "background.tiff"
REQUIREMENTS = ROOT / "Configuration" / "dmg" / "requirements.txt"
APP_ENTITLEMENTS = ROOT / "Notchera" / "Notchera.entitlements"
HELPER_ENTITLEMENTS = ROOT / "NotcheraXPCHelper" / "NotcheraXPCHelper.entitlements"
TEAM_ID = os.environ.get("TEAM_ID", "")
APPLE_ID = os.environ.get("APPLE_ID", "")
APPLE_APP_PASSWORD = os.environ.get("APPLE_APP_PASSWORD", "")

USER_PYTHON_BINS = [
    Path.home() / "Library/Python/3.12/bin",
    Path.home() / "Library/Python/3.11/bin",
    Path.home() / "Library/Python/3.10/bin",
    Path.home() / "Library/Python/3.9/bin",
]


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(*args: str, capture: bool = False, env: dict[str, str] | None = None) -> str:
    cmd = [str(arg) for arg in args]
    print("$", " ".join(cmd))
    completed = subprocess.run(
        cmd,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if completed.returncode != 0:
        if capture and completed.stdout:
            print(completed.stdout, end="", file=sys.stderr)
        raise SystemExit(completed.returncode)
    return completed.stdout or ""


def read_env_file() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for raw_line in env_file.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        die(f"missing {name} in .env")
    return value


def resolve_developer_id_identity(team_id: str) -> str:
    output = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
    matches = []
    for line in output.splitlines():
        if "Developer ID Application:" not in line:
            continue
        if team_id and f"({team_id})" not in line:
            continue
        start = line.find('"')
        end = line.rfind('"')
        if start != -1 and end > start:
            matches.append(line[start + 1 : end])
    if not matches:
        die(f"Developer ID Application certificate not found for team {team_id}")
    if len(matches) > 1:
        die("multiple Developer ID Application certificates found")
    return matches[0]


def ensure_file(path: Path) -> None:
    if not path.exists():
        die(f"missing file: {path}")


def ensure_dir(path: Path) -> None:
    if not path.is_dir():
        die(f"missing directory: {path}")


def find_dmgbuild() -> str:
    binary = shutil.which("dmgbuild")
    if binary:
        return binary
    for bin_dir in USER_PYTHON_BINS:
        candidate = bin_dir / "dmgbuild"
        if candidate.exists():
            os.environ["PATH"] = f"{bin_dir}:{os.environ.get('PATH', '')}"
            return str(candidate)
    die(f"dmgbuild not found. install with: python3 -m pip install --require-hashes -r {REQUIREMENTS}")


def ensure_notary_profile(team_id: str, apple_id: str, app_password: str) -> None:
    check = subprocess.run(
        ["xcrun", "notarytool", "history", "--keychain-profile", NOTARY_PROFILE],
        cwd=ROOT,
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if check.returncode == 0:
        return
    run(
        "xcrun",
        "notarytool",
        "store-credentials",
        NOTARY_PROFILE,
        "--apple-id",
        apple_id,
        "--team-id",
        team_id,
        "--password",
        app_password,
    )


def build_release() -> None:
    if DERIVED_DATA.exists():
        shutil.rmtree(DERIVED_DATA)
    run(
        "xcodebuild",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-configuration",
        "Release",
        "-destination",
        DESTINATION,
        "-derivedDataPath",
        str(DERIVED_DATA),
        "-clonedSourcePackagesDirPath",
        str(SOURCE_PACKAGES),
        "CODE_SIGNING_ALLOWED=NO",
        "build",
    )
    ensure_dir(APP_PATH)


def plist_value(path: Path, key: str) -> str:
    with path.open("rb") as fh:
        data = plistlib.load(fh)
    value = data.get(key)
    if not value:
        die(f"missing {key} in {path}")
    return str(value)


def render_app_entitlements(bundle_id: str, target: Path) -> None:
    content = APP_ENTITLEMENTS.read_text()
    target.write_text(content.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", bundle_id))


def sign(identity: str, path: Path, entitlements: Path | None = None) -> None:
    args = [
        "codesign",
        "--force",
        "--sign",
        identity,
        "--timestamp",
        "--options",
        "runtime",
    ]
    if entitlements is not None:
        args += ["--entitlements", str(entitlements)]
    args.append(str(path))
    run(*args)


def sign_app(identity: str) -> None:
    info_plist = APP_PATH / "Contents" / "Info.plist"
    helper = APP_PATH / "Contents" / "XPCServices" / "NotcheraXPCHelper.xpc"
    mediaremote = APP_PATH / "Contents" / "Frameworks" / "MediaRemoteAdapter.framework"
    mediaremote_test_client = APP_PATH / "Contents" / "Resources" / "MediaRemoteAdapterTestClient"
    sparkle = APP_PATH / "Contents" / "Frameworks" / "Sparkle.framework"
    current_version = os.readlink(sparkle / "Versions" / "Current")
    sparkle_version = sparkle / "Versions" / current_version
    autoupdate = sparkle_version / "Autoupdate"
    downloader = sparkle_version / "XPCServices" / "Downloader.xpc"
    installer = sparkle_version / "XPCServices" / "Installer.xpc"
    updater = sparkle_version / "Updater.app"

    ensure_file(info_plist)
    ensure_dir(helper)
    ensure_dir(mediaremote)
    ensure_dir(sparkle)
    ensure_file(autoupdate)
    ensure_dir(downloader)
    ensure_dir(installer)
    ensure_dir(updater)

    if mediaremote_test_client.exists():
        mediaremote_test_client.unlink()

    bundle_id = plist_value(info_plist, "CFBundleIdentifier")

    with tempfile.TemporaryDirectory() as tmp:
        entitlements = Path(tmp) / "app.entitlements"
        render_app_entitlements(bundle_id, entitlements)
        sign(identity, mediaremote)
        sign(identity, autoupdate)
        sign(identity, downloader)
        sign(identity, installer)
        sign(identity, updater)
        sign(identity, sparkle)
        sign(identity, helper, HELPER_ENTITLEMENTS)
        sign(identity, APP_PATH, entitlements)

    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(APP_PATH))


def find_app_icon(app_path: Path) -> Path | None:
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.exists():
        return None
    with info_plist.open("rb") as fh:
        data = plistlib.load(fh)
    icon_name = data.get("CFBundleIconFile") or data.get("CFBundleIconName")
    resources = app_path / "Contents" / "Resources"
    if icon_name:
        icon_name = str(icon_name)
        if not icon_name.endswith(".icns"):
            icon_name += ".icns"
        candidate = resources / icon_name
        if candidate.exists():
            return candidate
    matches = sorted(resources.glob("*.icns"))
    return matches[0] if matches else None


def create_dmg(app_path: Path) -> None:
    dmgbuild = find_dmgbuild()
    badge_icon = find_app_icon(app_path)
    settings = f'''
import os
volume_name = {VOLUME_NAME!r}
format = 'UDZO'
compression_level = 9
files = [{str(app_path)!r}]
symlinks = {{'Applications': '/Applications'}}
background = {str(BACKGROUND_TIFF)!r}
window_rect = ((0, 0), (660, 400))
icon_size = 128
icon_locations = {{
    {app_path.name!r}: (150, 180),
    'Applications': (510, 180),
}}
show_statusbar = False
show_tabview = False
show_toolbar = False
'''
    if badge_icon:
        settings += f"badge_icon = {str(badge_icon)!r}\n"

    with tempfile.TemporaryDirectory() as tmp:
        settings_path = Path(tmp) / "dmgbuild_settings.py"
        settings_path.write_text(settings)
        if DMG_OUTPUT.exists():
            DMG_OUTPUT.unlink()
        run(dmgbuild, "-s", str(settings_path), VOLUME_NAME, str(DMG_OUTPUT))
    ensure_file(DMG_OUTPUT)


def notarize() -> None:
    run("xcrun", "notarytool", "submit", str(DMG_OUTPUT), "--keychain-profile", NOTARY_PROFILE, "--wait")
    run("xcrun", "stapler", "staple", str(DMG_OUTPUT))
    run("xcrun", "stapler", "validate", str(DMG_OUTPUT))


def main() -> None:
    read_env_file()
    team_id = require_env("TEAM_ID")
    apple_id = require_env("APPLE_ID")
    app_password = require_env("APPLE_APP_PASSWORD")

    ensure_file(PROJECT)
    ensure_file(BACKGROUND_TIFF)
    ensure_file(REQUIREMENTS)
    ensure_file(APP_ENTITLEMENTS)
    ensure_file(HELPER_ENTITLEMENTS)

    identity = resolve_developer_id_identity(team_id)
    ensure_notary_profile(team_id, apple_id, app_password)
    build_release()
    sign_app(identity)
    create_dmg(APP_PATH)
    notarize()
    print(f"ready: {DMG_OUTPUT}")


if __name__ == "__main__":
    main()
