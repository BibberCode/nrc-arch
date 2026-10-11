#!/usr/bin/env python3
"""Baut die Versionsmatrix: letzte N wichtige Upstream-Releases als Arch-Pakete.

Regel (Default N=5): neuestes finales Stable ist immer dabei,
aufgefüllt mit den neuesten Releases (inkl. Betas), die ein Asset
`NoRiskClient-Linux.deb` mit API-Digest haben. Kein hartcodierter Index.

- --check-only: gibt JSON-Liste aus (tag, upstreamver, pkgver, sha256,
  arch_tag, prerelease), ändert nichts. --matrix: gleiche Liste als
  kompakte JSON-Matrix für GitHub-Actions (strategy.matrix).
- --patch-pkgbuild DIR INDEX: patcht _upstreamver/pkgver/pkgrel/sha256
  in DIR/PKGBUILD auf Eintrag INDEX der Auswahl (für isolierte Builds).

Tag-Beispiel: v0.6.29-beta.6 -> pkgver 0.6.29_beta.6
-> arch_tag arch-v0.6.29_beta.6-1.
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


def gh_api(url: str, token: str | None) -> object:
    req = urllib.request.Request(
        url, headers={"Accept": "application/vnd.github+json"}
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def collect(token: str | None) -> list[dict]:
    import os

    token = token or os.environ.get("GITHUB_TOKEN")
    data = gh_api(
        f"https://api.github.com/repos/{UPSTREAM_REPO}/releases?per_page=30",
        token,
    )
    assert isinstance(data, list), f"unerwartete API-Antwort: {data!r:.200}"
    out = []
    for rel in data:
        if rel.get("draft"):
            continue
        assets = rel.get("assets") or []
        deb = next((a for a in assets if a.get("name") == ASSET_NAME), None)
        if not deb:
            continue
        tag = rel.get("tag_name", "")
        m = re.match(r"^v(.+)$", tag)
        if not m:
            continue
        upstreamver = m.group(1)
        digest = (deb.get("digest") or "").removeprefix("sha256:")
        if len(digest) != 64:
            print(f"::warning::kein API-digest für {tag}, überspringe",
                  file=sys.stderr)
            continue
        out.append({
            "tag": tag,
            "upstreamver": upstreamver,
            "pkgver": upstreamver.replace("-", "_"),
            "sha256": digest,
            "arch_tag": f"arch-v{upstreamver.replace('-', '_')}-1",
            "prerelease": bool(rel.get("prerelease")),
            "published_at": rel.get("published_at"),
        })
    return out


def select(entries: list[dict], count: int) -> list[dict]:
    """Neuestes Stable garantiert, Rest neueste zuerst, gesamt `count`."""
    stables = [e for e in entries if not e["prerelease"]]
    picked = [e for e in entries if e not in stables][: max(count - 1, 0)]
    if stables:
        picked.append(stables[0])
    return picked[:count]


def patch_pkgbuild(directory: str, entry: dict) -> None:
    pb = Path(directory) / "PKGBUILD"
    text = pb.read_text()
    text = re.sub(r"^_upstreamver=.*$",
                  f"_upstreamver={entry['upstreamver']}", text, flags=re.M)
    text = re.sub(r"^pkgver=.*$", f"pkgver={entry['pkgver']}", text,
                  flags=re.M)
    text = re.sub(r"^pkgrel=.*$", "pkgrel=1", text, flags=re.M)
    text = re.sub(r"^sha256sums=\('[0-9a-f]{64}'\)$",
                  f"sha256sums=('{entry['sha256']}')", text, flags=re.M)
    pb.write_text(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--check-only", action="store_true")
    ap.add_argument("--matrix", action="store_true")
    ap.add_argument("--patch-pkgbuild", default=None,
                    help="DIR, zusammen mit --index")
    ap.add_argument("--index", type=int, default=0)
    ap.add_argument("--token", default=None)
    args = ap.parse_args()

    entries = collect(args.token)
    if not entries:
        raise SystemExit("kein Release mit NoRiskClient-Linux.deb gefunden")
    picked = select(entries, args.count)

    if args.patch_pkgbuild is not None:
        patch_pkgbuild(args.patch_pkgbuild, picked[args.index])
        print(f"PKGBUILD in {args.patch_pkgbuild} -> {picked[args.index]['tag']}",
              file=sys.stderr)
        return 0

    print(json.dumps(picked if not args.matrix else {"version": picked}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
