#!/usr/bin/env python3
"""Plan and preflight a VCF 9.1 VKS air-gapped deployment.

This tool never accepts credentials and does not change VCF, vCenter, or Depot.
It emits commands for Broadcom's oci_image_depot_migrator.py.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import shutil
import socket
import ssl
import sys
from pathlib import Path
from urllib.request import Request, urlopen

FQDN_RE = re.compile(r"^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$")
FORBIDDEN_KEYS = {"password", "token", "secret", "username", "credential", "credentials"}


class ConfigError(ValueError):
    pass


def load_config(path: str | Path) -> dict:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def _walk_forbidden(value, path="config") -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                found.append(f"{path}.{key}")
            found.extend(_walk_forbidden(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(_walk_forbidden(child, f"{path}[{index}]"))
    return found


def validate(config: dict) -> list[str]:
    errors: list[str] = []
    forbidden = _walk_forbidden(config)
    if forbidden:
        errors.append("credentials are forbidden in config: " + ", ".join(forbidden))

    depot = config.get("depot_fqdn", "")
    try:
        ipaddress.ip_address(depot)
        depot_is_ip = True
    except ValueError:
        depot_is_ip = False
    if depot_is_ip or not FQDN_RE.fullmatch(depot):
        errors.append("depot_fqdn must be a resolvable FQDN, not an IP or placeholder")
    if not config.get("work_dir"):
        errors.append("work_dir is required")

    bundles = config.get("bundles")
    if not isinstance(bundles, list) or not bundles:
        errors.append("at least one bundle is required")
    else:
        names: set[str] = set()
        for index, bundle in enumerate(bundles):
            name = bundle.get("name", "") if isinstance(bundle, dict) else ""
            source = bundle.get("source", "") if isinstance(bundle, dict) else ""
            if not name or name in names:
                errors.append(f"bundles[{index}].name is missing or duplicated")
            names.add(name)
            if not source.startswith("projects.packages.broadcom.com/") or ":" not in source.rsplit("/", 1)[-1]:
                errors.append(f"bundles[{index}].source must be a tagged Broadcom OCI image")

    for index, endpoint in enumerate(config.get("tcp_endpoints", [])):
        if not endpoint.get("host") or not isinstance(endpoint.get("port"), int):
            errors.append(f"tcp_endpoints[{index}] requires host and integer port")
    return errors


def plan(config: dict, action: str) -> list[str]:
    migrator = "./oci_image_depot_migrator.py"
    work_dir = config["work_dir"]
    depot = config["depot_fqdn"]
    commands = []
    for bundle in config["bundles"]:
        source = bundle["source"]
        command = f"{migrator} --work-dir '{work_dir}' {action} -s '{source}'"
        if action in {"upload", "copy", "map-target-repo"}:
            command += f" -t '{depot}'"
        commands.append(command)
    return commands


def preflight(config: dict, timeout: float) -> list[tuple[str, bool, str]]:
    results: list[tuple[str, bool, str]] = []
    for binary in ("python3", "imgpkg"):
        location = shutil.which(binary)
        results.append((f"binary:{binary}", bool(location), location or "not found"))

    for endpoint in config.get("tcp_endpoints", []):
        host, port = endpoint["host"], endpoint["port"]
        label = f"tcp:{host}:{port}"
        try:
            addresses = sorted({item[4][0] for item in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)})
            with socket.create_connection((host, port), timeout=timeout):
                pass
            results.append((label, True, ",".join(addresses)))
        except OSError as exc:
            results.append((label, False, str(exc)))

    depot = config["depot_fqdn"]
    try:
        request = Request(f"https://{depot}/v2/", method="GET")
        with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
            status = response.status
        results.append(("depot:/v2/", status in {200, 401}, f"HTTP {status}"))
    except Exception as exc:  # reports TLS, DNS and HTTP failures without hiding context
        status = getattr(exc, "code", None)
        ok = status == 401
        results.append(("depot:/v2/", ok, f"HTTP {status}" if status else str(exc)))
    return results


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="config.json")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    plan_parser = sub.add_parser("plan")
    plan_parser.add_argument("action", choices=("download", "upload", "copy", "map-target-repo"))
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args(argv)

    try:
        config = load_config(args.config)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    errors = validate(config)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if args.command == "validate":
        print("OK: configuration is valid and contains no credential fields")
        return 0
    if args.command == "plan":
        print("\n".join(plan(config, args.action)))
        return 0

    results = preflight(config, args.timeout)
    for label, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'} {label}: {detail}")
    return 0 if all(item[1] for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
