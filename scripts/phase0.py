#!/usr/bin/env python3
"""Run staged, read-only Phase 0 probes with the installed Databricks CLI.

No third-party Python dependencies. SQL stays in sql/setup; each named probe is
sent as a separate statement. Raw outputs are local, Git-ignored evidence.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
STAGES = {
    "inspect": "00_inspect_samples.sql",
    "dates": "01_date_candidates.sql",
    "profile": "02_profile_window.sql",
    "capabilities": "03_capabilities.sql",
}
READ_ONLY_PREFIX = re.compile(r"^(SELECT|WITH|SHOW|DESCRIBE)\b", re.I)
FORBIDDEN = re.compile(r"\b(INSERT|UPDATE|DELETE|MERGE|CREATE|DROP|ALTER|TRUNCATE|COPY|GRANT|REVOKE|CALL)\b", re.I)


def load_probes(path: Path) -> list[tuple[str, str]]:
    """Read our constrained SQL files, not arbitrary SQL or a general SQL parser."""
    probes: list[tuple[str, str]] = []
    chunks = re.split(r"^-- probe: ([a-z0-9_]+)\s*$", path.read_text(), flags=re.M)
    for index in range(1, len(chunks), 2):
        name, block = chunks[index:index + 2]
        # Project probes use whole-line comments, no semicolons inside literals.
        sql = "\n".join(line for line in block.splitlines()
                        if not line.lstrip().startswith("--")).strip()
        sql = sql.removesuffix(";").strip()
        if not READ_ONLY_PREFIX.match(sql) or ";" in sql or FORBIDDEN.search(sql):
            raise ValueError(f"{name}: expected a single read-only statement")
        if name in {existing for existing, _ in probes}:
            raise ValueError(f"duplicate probe name: {name}")
        probes.append((name, sql))
    if not probes:
        raise ValueError(f"no named probes in {path.name}")
    return probes


def validate_window(start: str | None, end: str | None) -> tuple[date, date]:
    if not start or not end:
        raise ValueError("profile requires --start and --end chosen from the date results")
    first, last = date.fromisoformat(start), date.fromisoformat(end)
    if ((first.month, first.day) != (1, 1) or (last.month, last.day) != (1, 1)
            or last.year - first.year not in (1, 2)):
        raise ValueError("choose one or two calendar years: inclusive Jan 1 to exclusive Jan 1")
    return first, last


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("stage", choices=STAGES)
    result.add_argument("--profile", default="sameed-dbx", help="previously selected CLI profile")
    result.add_argument("--warehouse", help="inspected warehouse ID; otherwise CLI discovers one")
    result.add_argument("--start", help="inclusive order date, YYYY-01-01")
    result.add_argument("--end", help="exclusive order date, YYYY-01-01")
    result.add_argument("--allow-order-date-scan", action="store_true",
                        help="explicitly permit the all-time order-date aggregation")
    result.add_argument("--dry-run", action="store_true", help="print commands; do not connect or write evidence")
    return result


def commands(args: argparse.Namespace) -> list[tuple[str, list[str]]]:
    if args.stage == "dates" and not args.allow_order_date_scan:
        raise ValueError("inspect source size first, then opt in with --allow-order-date-scan")
    if args.stage == "profile":
        first, last = validate_window(args.start, args.end)
    elif args.start or args.end:
        raise ValueError("date parameters apply only to the profile stage")
    common = ["--profile", args.profile, "--output", "json"]
    plan = [("current_user", ["databricks", "current-user", "me", *common])]
    if args.stage == "inspect":
        plan.append(("warehouses", ["databricks", "warehouses", "list", *common]))
    for name, sql in load_probes(ROOT / "sql" / "setup" / STAGES[args.stage]):
        command = ["databricks", "experimental", "aitools", "tools", "query", sql, *common]
        if args.warehouse:
            command.extend(["--warehouse", args.warehouse])
        if args.stage == "profile":
            command.extend(["--param", f"start_date:DATE={first.isoformat()}",
                            "--param", f"end_date:DATE={last.isoformat()}"])
        plan.append((name, command))
    return plan


def main(argv: list[str] | None = None) -> int:
    arg_parser = parser()
    args = arg_parser.parse_args(argv)
    try:
        plan = commands(args)
    except ValueError as exc:
        arg_parser.error(str(exc))
    if args.dry_run:
        for name, command in plan:
            print(f"# {name}\n{shlex.join(command)}\n")
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = ROOT / "evidence" / "runs" / f"{stamp}_{args.stage}_{uuid4().hex[:8]}"
    output_dir.mkdir(parents=True, mode=0o700)
    summary = {"stage": args.stage, "profile": args.profile, "warehouse": args.warehouse,
               "start": args.start, "end": args.end, "probes": []}
    failed = False
    for name, command in plan:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            record = {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        except subprocess.TimeoutExpired:
            record = {"exit_code": 124, "stdout": "", "stderr": "CLI timed out after 180 seconds; check query history before retrying. Remote query may still be running."}
        except OSError as exc:
            record = {"exit_code": 127, "stdout": "", "stderr": str(exc)}
        success = record["exit_code"] == 0
        # The query CLI normally exits nonzero on failure. Also reject explicit
        # incomplete/failed statement states if an older CLI returns exit zero.
        try:
            payload = json.loads(record["stdout"])
            records = payload if isinstance(payload, list) else [payload]
            for item in records:
                if isinstance(item, dict):
                    state = item.get("state", item.get("status", {}).get("state")
                                     if isinstance(item.get("status"), dict) else None)
                    if name not in ("current_user", "warehouses") and state and state != "SUCCEEDED":
                        success = False
        except (ValueError, TypeError):
            if success:
                success = False  # Requested JSON is missing: this is not proof.
        evidence_file = output_dir / f"{name}.json"
        evidence_file.write_text(json.dumps(record, indent=2) + "\n")
        evidence_file.chmod(0o600)
        summary["probes"].append({"name": name, "status": "PASS" if success else "BLOCKED"})
        print(f"{name}: {'PASS' if success else 'BLOCKED'}", flush=True)
        if not success:
            failed = True
            # Identity failure or an unknown remote query state must stop all
            # further SQL. Capability permission failures are independent.
            if args.stage != "capabilities" or name == "current_user" or record["exit_code"] == 124:
                break
    summary["complete"] = not failed and len(summary["probes"]) == len(plan)
    manifest = output_dir / "manifest.json"
    manifest.write_text(json.dumps(summary, indent=2) + "\n")
    manifest.chmod(0o600)
    print(f"Evidence: {output_dir.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
