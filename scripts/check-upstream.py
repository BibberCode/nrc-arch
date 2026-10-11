#!/usr/bin/env python3
"""Prüft Upstream-Releases inkl. Betas, mappt Tag -> Arch-pkgver.

- Nimmt das neueste nicht-Draft-Release, das ein Asset
  `NoRiskClient-Linux.deb` hat (kein hartcodierter Index).
- Vergleicht mit no-risk-launcher/PKGBUILD (_upstreamver, pkgver, sha256).
- --check-only: gibt nur JSON aus, ändert nichts.
- --apply: aktualisiert PKGBUILD (_upstreamver, pkgver, pkgrel=1, sha256).
  .SRCINFO wird im CI per `makepkg --printsrcinfo` neu erzeugt, nicht hier.

Tag-Beispiel: v0.6.29-beta.6 -> _upstreamver=0.6.29-beta.6
-> pkgver=0.6.29_beta.6 (Arch: kein Bindestrich).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

UPSTREAM_REPO = "NoRiskClient/noriskclient-launcher"
ASSET_NAME = "NoRiskClient-Linux.deb"
ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / "no-risk-launcher" / "PKGBUILD"


def gh_api(url: str, token: str | None) -> object:
    req = urllib.request.Request(
        url, headers={"Accept": "application/vnd.github+json"}
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def pick_latest(token: str | None) -> dict:
    import os

    token = token or os.environ.get("GITHUB_TOKEN")
    data = gh_api(
        f"https://api.github.com/repos/{UPSTREAM_REPO}/releases?per_page=20",
        token,
    )
    assert isinstance(data, list), f"unerwartete API-Antwort: {data!r:.200}"
    for rel in data:
        if rel.get("draft"):
            continue
        assets = rel.get("assets") or []
        deb = next(
            (a for a in assets if a.get("name") == ASSET_NAME), None
        )
        if not deb:
            continue
        tag = rel.get("tag_name", "")
        m = re.match(r"^v(.+)$", tag)
        if not m:
            continue
        upstreamver = m.group(1)
        digest = (deb.get("digest") or "").removeprefix("sha256:")
        if len(digest) != 64:
            print(
                f"::warning::kein API-digest für {tag}, überspringe",
                file=sys.stderr,
            )
            continue
        return {
            "tag": tag,
            "upstreamver": upstreamver,
            "pkgver": upstreamver.replace("-", "_"),
            "sha256": digest,
            "prerelease": bool(rel.get("prerelease")),
            "published_at": rel.get("published_at"),
            "browser_download_url": deb.get("browser_download_url"),
        }
    raise SystemExit("kein Release mit NoRiskClient-Linux.deb gefunden")


def read_pkgbuild() -> dict:
    text = PKGBUILD.read_text()
    def grab(pat: str) -> str:
        mm = re.search(pat, text, re.M)
        return mm.group(1) if mm else ""
    return {
        "_upstreamver": grab(r"^_upstreamver=(.+)$"),
        "pkgver": grab(r"^pkgver=(.+)$"),
        "sha256": grab(r"^sha256sums=\('([0-9a-f]{64})'\)"),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-only", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--token", default=None)
    args = ap.parse_args()

    latest = pick_latest(args.token)
    current = read_pkgbuild()
    needs_update = (
        current["_upstreamver"] != latest["upstreamver"]
        or current["pkgver"] != latest["pkgver"]
        or current["sha256"] != latest["sha256"]
    )
    out = {"current": current, "latest": latest, "needs_update": needs_update}
    print(json.dumps(out, indent=2))

    if args.apply and needs_update:
        text = PKGBUILD.read_text()
        text = re.sub(
            r"^_upstreamver=.*$",
            f"_upstreamver={latest['upstreamver']}",
            text,
            flags=re.M,
        )
        text = re.sub(
            r"^pkgver=.*$", f"pkgver={latest['pkgver']}", text, flags=re.M
        )
        text = re.sub(r"^pkgrel=.*$", "pkgrel=1", text, flags=re.M)
        text = re.sub(
            r"^sha256sums=\('[0-9a-f]{64}'\)$",
            f"sha256sums=('{latest['sha256']}')",
            text,
            flags=re.M,
        )
        PKGBUILD.write_text(text)
        print(f"PKGBUILD aktualisiert auf {latest['tag']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
