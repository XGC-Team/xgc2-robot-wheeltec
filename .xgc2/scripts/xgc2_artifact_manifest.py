#!/usr/bin/env python3
"""Create and verify trusted XGC2 build artifact manifests."""

from __future__ import print_function

import argparse
import hashlib
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


BUILD_SCHEMA = "xgc2.build-artifact.v1"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deb_metadata(path):
    values = []
    for field in ("Package", "Version", "Architecture"):
        values.append(
            subprocess.check_output(
                ["dpkg-deb", "-f", str(path), field],
                universal_newlines=True,
            ).strip()
        )
    if not all(values):
        raise ValueError("cannot read Debian metadata from {}".format(path))
    return {
        "package": values[0],
        "version": values[1],
        "architecture": values[2],
        "filename": path.name,
        "sha256": sha256(path),
        "size_bytes": path.stat().st_size,
    }


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def build_manifest(args):
    debs = sorted(Path(args.deb_dir).rglob("*.deb"))
    if not debs:
        raise ValueError("no Debian packages found below {}".format(args.deb_dir))

    entries = []
    for deb in debs:
        metadata = deb_metadata(deb)
        if metadata["architecture"] not in (args.architecture, "all"):
            raise ValueError(
                "{} is not compatible with {}".format(deb, args.architecture)
            )
        entries.append(
            {
                "file": metadata["filename"],
                "package": metadata["package"],
                "version": metadata["version"],
                "architecture": metadata["architecture"],
                "sha256": metadata["sha256"],
                "size": metadata["size_bytes"],
            }
        )

    payload = {
        "schema": BUILD_SCHEMA,
        "product": args.product,
        "source_sha": args.source_sha,
        "version": args.product_version,
        "distribution": args.distribution,
        "architecture": args.architecture,
        "ci": {
            "run_id": str(args.ci_run_id),
            "workflow": args.ci_workflow,
            "workflow_ref": args.ci_workflow_ref,
        },
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "debs": entries,
    }
    name = "{}_{}_{}.build.json".format(
        args.product, args.distribution, args.architecture
    )
    write_json(Path(args.output_dir) / name, payload)


def find_deb(root, filename):
    if not filename or Path(filename).name != filename:
        raise ValueError("unsafe Debian filename {!r}".format(filename))
    matches = sorted(path for path in root.rglob(filename) if path.is_file())
    if len(matches) != 1:
        raise ValueError(
            "expected one {} below {}, found {}".format(filename, root, len(matches))
        )
    return matches[0]


def validate_deb(path, declared):
    metadata = deb_metadata(path)
    expected = {
        "file": metadata["filename"],
        "package": metadata["package"],
        "version": metadata["version"],
        "architecture": metadata["architecture"],
        "sha256": metadata["sha256"],
        "size": metadata["size_bytes"],
    }
    for key, value in expected.items():
        if declared.get(key) != value:
            raise ValueError("{}: {} mismatch".format(path, key))


def verify_build(args):
    root = Path(args.artifact_dir)
    deb_output = Path(args.deb_output_dir)
    manifest_output = Path(args.manifest_output_dir)
    deb_output.mkdir(parents=True, exist_ok=True)
    manifest_output.mkdir(parents=True, exist_ok=True)

    selected = []
    for manifest_path in sorted(root.rglob("*.json")):
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if manifest.get("schema") != BUILD_SCHEMA:
            continue
        if manifest.get("product") != args.product:
            continue
        if manifest.get("source_sha") != args.source_sha:
            continue
        if manifest.get("distribution") != args.distribution:
            continue
        if args.product_version and manifest.get("version") != args.product_version:
            continue
        if args.architecture and manifest.get("architecture") != args.architecture:
            continue
        ci = manifest.get("ci", {})
        if not all(ci.get(key) for key in ("run_id", "workflow", "workflow_ref")):
            continue
        if args.ci_run_id and str(ci.get("run_id")) != str(args.ci_run_id):
            continue
        entries = manifest.get("debs")
        if not isinstance(entries, list) or not entries:
            raise ValueError("{}: debs must be non-empty".format(manifest_path))
        for entry in entries:
            deb = find_deb(root, entry.get("file", ""))
            validate_deb(deb, entry)
            selected.append((manifest_path, deb))

    if not selected:
        raise ValueError("no matching trusted build manifest found")

    copied_manifests = set()
    for manifest_path, deb in selected:
        shutil.copy2(str(deb), str(deb_output / deb.name))
        if manifest_path not in copied_manifests:
            shutil.copy2(
                str(manifest_path),
                str(manifest_output / manifest_path.name),
            )
            copied_manifests.add(manifest_path)


def make_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command")
    subparsers.required = True

    build = subparsers.add_parser("build")
    build.add_argument("--deb-dir", required=True)
    build.add_argument("--output-dir", required=True)
    build.add_argument("--product", required=True)
    build.add_argument("--product-version", required=True)
    build.add_argument("--distribution", required=True)
    build.add_argument("--architecture", required=True)
    build.add_argument("--source-sha", required=True)
    build.add_argument("--ci-run-id", required=True)
    build.add_argument("--ci-workflow", required=True)
    build.add_argument("--ci-workflow-ref", required=True)
    build.set_defaults(func=build_manifest)

    verify = subparsers.add_parser("verify-build")
    verify.add_argument("--artifact-dir", required=True)
    verify.add_argument("--deb-output-dir", required=True)
    verify.add_argument("--manifest-output-dir", required=True)
    verify.add_argument("--product", required=True)
    verify.add_argument("--product-version")
    verify.add_argument("--distribution", required=True)
    verify.add_argument("--architecture")
    verify.add_argument("--source-sha", required=True)
    verify.add_argument("--ci-run-id")
    verify.set_defaults(func=verify_build)

    return parser


def main():
    parser = make_parser()
    args = parser.parse_args()
    if not getattr(args, "command", None):
        parser.error("a subcommand is required")
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
