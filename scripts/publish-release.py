#!/usr/bin/env python3
"""Stellt sicher, dass TAG ein VOLLSTÄNDIGES Release mit .pkg.tar.zst hat.

- Release vollständig (Tag da + .pkg.tar.zst-Asset) -> SKIP, nichts tun.
- Release unvollständig (Tag ohne Paket, z.B. nach abgebrochenem Lauf)
  -> löschen + neu anlegen.
- Kein Release -> anlegen (Tag, Titel, Notes, Assets hochladen).

Nur Standardbibliothek + GitHub-REST-API. Braucht weder `gh` noch `git`.
Token via --token oder GH_TOKEN/GITHUB_TOKEN.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PKG_SUFFIX = ".pkg.tar.zst"


def api(base: str, method: str, path: str, token: str,
        data: bytes | None = None, ctype: str = "application/json") -> tuple[int, object]:
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read()
            return resp.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, None


def ensure_release(base: str, repo: str, token: str, tag: str,
                   title: str, notes: str, assets: list[Path]) -> str:
    status, rel = api(base, "GET",
                      f"/repos/{repo}/releases/tags/{urllib.parse.quote(tag, safe='')}",
                      token)
    if status == 200 and isinstance(rel, dict):
        names = [a.get("name", "") for a in rel.get("assets", [])]
        if any(n.endswith(PKG_SUFFIX) for n in names):
            print(f"Release {tag} vollständig, überspringe")
            return "SKIP"
        print(f"Release {tag} unvollständig, lege neu an")
        api(base, "DELETE", f"/repos/{repo}/releases/{rel['id']}", token)
        api(base, "DELETE",
            f"/repos/{repo}/git/refs/tags/{urllib.parse.quote(tag, safe='')}",
            token)
    elif status != 404:
        raise SystemExit(f"GET release {tag}: HTTP {status}: {rel!r:.200}")
    else:
        print(f"Erstelle Release {tag}")

    status, rel = api(base, "POST", f"/repos/{repo}/releases", token,
                      json.dumps({"tag_name": tag, "name": title,
                                  "body": notes, "draft": False,
                                  "prerelease": False}).encode())
    if status != 201 or not isinstance(rel, dict):
        raise SystemExit(f"POST release {tag}: HTTP {status}: {rel!r:.200}")
    upload_tpl = rel.get("upload_url", "")
    upload_base = upload_tpl.split("{")[0]
    for asset in assets:
        name = asset.name
        ctype, _ = mimetypes.guess_type(name)
        up = upload_base + "?" + urllib.parse.urlencode({"name": name})
        req = urllib.request.Request(up, data=asset.read_bytes(), method="POST")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Content-Type", ctype or "application/octet-stream")
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                if resp.status not in (200, 201):
                    raise SystemExit(f"Upload {name}: HTTP {resp.status}")
        except urllib.error.HTTPError as e:
            raise SystemExit(f"Upload {name}: HTTP {e.code}: {e.read()[:200]!r}")
        print(f"  Asset {name} hochgeladen")
    return "CREATED"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--notes", default="")
    ap.add_argument("--assets", nargs="+", required=True)
    ap.add_argument("--token", default=None)
    ap.add_argument("--api-base", default="https://api.github.com")
    args = ap.parse_args()
    token = args.token or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise SystemExit("kein Token (GH_TOKEN/GITHUB_TOKEN oder --token)")
    print(ensure_release(args.api_base, args.repo, token, args.tag,
                         args.title, args.notes, [Path(a) for a in args.assets]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
