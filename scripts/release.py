#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from enum import Enum
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Notchera.xcodeproj"
PBXPROJ = PROJECT / "project.pbxproj"
INFO_PLIST = ROOT / "Notchera" / "Info.plist"
SCHEME = "Notchera"
DESTINATION = "platform=macOS"
DERIVED_DATA = ROOT / ".derived-data-release-dist"
SOURCE_PACKAGES = DERIVED_DATA / "SourcePackages"
APP_PATH = DERIVED_DATA / "Build" / "Products" / "Release" / "Notchera.app"
CLI_PROJECT = ROOT / "cli" / "notcherahud"
CLI_BINARY = CLI_PROJECT / ".build" / "release" / "notcherahud"
DMG_OUTPUT = ROOT / "Notchera.dmg"
BREW_ZIP_OUTPUT = ROOT / "Notchera-brew.zip"
VOLUME_NAME = "Notchera"
NOTARY_PROFILE = "notary-profile"
REQUIREMENTS = ROOT / "scripts" / "requirements-release.txt"
APP_ENTITLEMENTS = ROOT / "Notchera" / "Notchera.entitlements"
HELPER_ENTITLEMENTS = ROOT / "NotcheraXPCHelper" / "NotcheraXPCHelper.entitlements"
USER_PYTHON_BINS = [
    Path.home() / "Library/Python/3.12/bin",
    Path.home() / "Library/Python/3.11/bin",
    Path.home() / "Library/Python/3.10/bin",
    Path.home() / "Library/Python/3.9/bin",
]

class ReleaseKind(str, Enum):
    direct = "direct"
    brew = "brew"


class BuildProfile(str, Enum):
    dev = "dev"
    distribution = "distribution"


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(*args: str, capture: bool = False, env: dict[str, str] | None = None, cwd: str | Path | None = None) -> str:
    cmd = [str(arg) for arg in args]
    print("$", " ".join(cmd))
    completed = subprocess.run(
        cmd,
        cwd=str(cwd or ROOT),
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


def ask_choice(title: str, options: list[tuple[str, str]]) -> str:
    print()
    print(title)
    for index, (_, label) in enumerate(options, start=1):
        print(f"  {index}. {label}")
    while True:
        raw = input("select: ").strip()
        if raw.isdigit():
            selected = int(raw)
            if 1 <= selected <= len(options):
                return options[selected - 1][0]
        print("invalid selection")


def ask_yes_no(title: str, default: bool) -> bool:
    suffix = "Y/n" if default else "y/N"
    while True:
        raw = input(f"{title} [{suffix}]: ").strip().lower()
        if not raw:
            return default
        if raw in {"y", "yes"}:
            return True
        if raw in {"n", "no"}:
            return False
        print("invalid selection")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=[item.value for item in ReleaseKind])
    parser.add_argument("--profile", choices=[item.value for item in BuildProfile])
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--reuse-build", action="store_true")
    parser.add_argument("--skip-notarize", action="store_true")
    return parser.parse_args()


def prompt_build_plan() -> tuple[ReleaseKind, BuildProfile]:
    kind = ReleaseKind.direct
    profile = BuildProfile(
        ask_choice(
            "which local release mode do you want?",
            [
                (BuildProfile.dev.value, "dev. local direct build only. no sign or notarize"),
                (BuildProfile.distribution.value, "distribution. local direct dmg with sign and notarize"),
            ],
        )
    )
    print()
    print(f"kind: {kind.value}")
    print(f"profile: {profile.value}")
    if not ask_yes_no("continue", True):
        raise SystemExit(0)
    return kind, profile


def build_release() -> None:
    if DERIVED_DATA.exists():
        shutil.rmtree(DERIVED_DATA, ignore_errors=True)
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


def build_cli() -> None:
    run("swift", "build", "-c", "release", cwd=CLI_PROJECT)
    ensure_file(CLI_BINARY)


def bundle_cli() -> None:
    resources_dir = APP_PATH / "Contents" / "Resources"
    target = resources_dir / "notcherahud"
    ensure_dir(resources_dir)
    shutil.copy2(CLI_BINARY, target)
    target.chmod(0o755)


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
    cli_binary = APP_PATH / "Contents" / "Resources" / "notcherahud"

    ensure_file(info_plist)
    ensure_dir(helper)
    ensure_dir(mediaremote)
    ensure_file(cli_binary)

    if mediaremote_test_client.exists():
        mediaremote_test_client.unlink()

    bundle_id = plist_value(info_plist, "CFBundleIdentifier")

    with tempfile.TemporaryDirectory() as tmp:
        entitlements = Path(tmp) / "app.entitlements"
        render_app_entitlements(bundle_id, entitlements)
        sign(identity, mediaremote)
        sign(identity, cli_binary)

        sparkle = APP_PATH / "Contents" / "Frameworks" / "Sparkle.framework"
        ensure_dir(sparkle)

        versions_dir = sparkle / "Versions"
        if versions_dir.exists() and (versions_dir / "Current").exists():
            current_version = os.readlink(versions_dir / "Current")
            sparkle_version = versions_dir / current_version
        else:
            sparkle_version = sparkle

        autoupdate = sparkle_version / "Autoupdate"
        downloader = sparkle_version / "XPCServices" / "Downloader.xpc"
        installer = sparkle_version / "XPCServices" / "Installer.xpc"
        updater = sparkle_version / "Updater.app"

        ensure_file(autoupdate)
        ensure_dir(downloader)
        ensure_dir(installer)
        ensure_dir(updater)

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

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        settings_lines = [
            f"volume_name = {VOLUME_NAME!r}",
            f"filename = {str(DMG_OUTPUT)!r}",
            "format = 'UDZO'",
            "filesystem = 'HFS+'",
            "compression_level = 9",
            f"files = [{str(app_path)!r}]",
            "symlinks = {'Applications': '/Applications'}",
            "window_rect = ((0, 0), (660, 400))",
            "default_view = 'icon-view'",
            "show_status_bar = False",
            "show_tab_view = False",
            "show_toolbar = False",
            "show_pathbar = False",
            "show_sidebar = False",
            "show_icon_preview = False",
            "include_icon_view_settings = True",
            "arrange_by = None",
            "grid_spacing = 96",
            "label_pos = 'bottom'",
            "text_size = 14",
            "icon_size = 128",
            "icon_locations = {",
            f"    {app_path.name!r}: (150, 180),",
            "    'Applications': (510, 180),",
            "}",
        ]
        if badge_icon:
            settings_lines.append(f"badge_icon = {str(badge_icon)!r}")

        settings_path = tmp_dir / "dmgbuild_settings.py"
        settings_path.write_text("\n".join(settings_lines) + "\n")
        if DMG_OUTPUT.exists():
            DMG_OUTPUT.unlink()
        run(dmgbuild, "-s", str(settings_path), VOLUME_NAME, str(DMG_OUTPUT))
    ensure_file(DMG_OUTPUT)


def smoke_test_dmg() -> None:
    mount_point = ROOT / ".dmg-smoke-test"
    if mount_point.exists():
        shutil.rmtree(mount_point)
    mount_point.mkdir()
    mounted = False
    try:
        run("hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", str(mount_point), str(DMG_OUTPUT))
        mounted = True
        ensure_dir(mount_point / APP_PATH.name)
        ensure_file(mount_point / ".DS_Store")
        print(f"smoke: mounted={mount_point}")
    finally:
        if mounted:
            run("hdiutil", "detach", str(mount_point))
        shutil.rmtree(mount_point, ignore_errors=True)


def set_release_channel(kind: ReleaseKind) -> None:
    info_plist = APP_PATH / "Contents" / "Info.plist"
    with info_plist.open("rb") as file:
        info = plistlib.load(file)
    info["NotcheraReleaseChannel"] = kind.value
    with info_plist.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)


def create_brew_zip() -> None:
    if BREW_ZIP_OUTPUT.exists():
        BREW_ZIP_OUTPUT.unlink()
    run("ditto", "-c", "-k", "--keepParent", str(APP_PATH), str(BREW_ZIP_OUTPUT))
    ensure_file(BREW_ZIP_OUTPUT)


def notarize_dmg() -> None:
    run("xcrun", "notarytool", "submit", str(DMG_OUTPUT), "--keychain-profile", NOTARY_PROFILE, "--wait")
    run("xcrun", "stapler", "staple", str(DMG_OUTPUT))
    run("xcrun", "stapler", "validate", str(DMG_OUTPUT))


def notarize_app_for_brew() -> None:
    run("xcrun", "notarytool", "submit", str(BREW_ZIP_OUTPUT), "--keychain-profile", NOTARY_PROFILE, "--wait")
    run("xcrun", "stapler", "staple", str(APP_PATH))
    run("xcrun", "stapler", "validate", str(APP_PATH))


def validate_prerequisites(kind: ReleaseKind) -> None:
    ensure_dir(PROJECT)
    ensure_file(APP_ENTITLEMENTS)
    ensure_file(HELPER_ENTITLEMENTS)
    ensure_file(REQUIREMENTS)


def main() -> None:
    read_env_file()
    args = parse_args()

    if args.profile:
        kind = ReleaseKind(args.kind or ReleaseKind.direct.value)
        profile = BuildProfile(args.profile)
        if not args.yes:
            print(f"kind: {kind.value}")
            print(f"profile: {profile.value}")
    else:
        kind, profile = prompt_build_plan()

    validate_prerequisites(kind)

    if not args.reuse_build:
        build_release()
        build_cli()
        bundle_cli()
    else:
        ensure_dir(APP_PATH)

    set_release_channel(kind)

    identity: str | None = None
    if profile is BuildProfile.distribution:
        team_id = require_env("TEAM_ID")
        apple_id = require_env("APPLE_ID")
        app_password = require_env("APPLE_APP_PASSWORD")
        identity = resolve_developer_id_identity(team_id)
        ensure_notary_profile(team_id, apple_id, app_password)
        sign_app(identity)

    if kind is ReleaseKind.direct:
        create_dmg(APP_PATH)
        smoke_test_dmg()
        if profile is BuildProfile.distribution and not args.skip_notarize:
            notarize_dmg()
        print(f"ready: {DMG_OUTPUT}")
        return

    if profile is BuildProfile.distribution and not args.skip_notarize:
        create_brew_zip()
        notarize_app_for_brew()
        print(f"ready: {APP_PATH}")
        print(f"archive: {BREW_ZIP_OUTPUT}")
        return

    if kind is ReleaseKind.brew:
        create_brew_zip()

    print(f"ready: {APP_PATH}")


if __name__ == "__main__":
    main()
