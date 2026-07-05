#!/usr/bin/env python3
"""Parse LinkedIn post analytics XLSX exports and emit/load Postgres upserts.

No XLSX/PG dependencies: Python stdlib reads the workbook, and `--psql` pipes the
SQL to whatever psql command the caller supplies (local psql or kubectl exec).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shlex
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}

SCALARS = {
    "impressions": "impressions",
    "members reached": "members_reached",
    "profile viewers": "profile_viewers",
    "followers gained": "followers_gained",
    "social engagements": "social_engagements",
    "reactions": "reactions",
    "comments": "comments",
    "reposts": "reposts",
    "saves": "saves",
    "sends": "sends",
    "link engagements": "link_engagements",
    "premium button engagements": "premium_button_engagements",
}
CATEGORIES = {
    "job title": "Job title",
    "location": "Location",
    "seniority": "Seniority",
    "industry": "Industry",
    "company size": "Company size",
}
METRIC_COLS = list(SCALARS.values())


def norm(s: object) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(s or "").lower()).strip()


def text(el: ET.Element) -> str:
    return "".join(t.text or "" for t in el.findall(".//a:t", NS))


def colnum(ref: str) -> int:
    n = 0
    for ch in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(ch) - 64
    return n - 1


def rows(path: Path) -> list[list[str]]:
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            root = ET.fromstring(z.read("xl/sharedStrings.xml"))
            shared = [text(si) for si in root.findall("a:si", NS)]

        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
        out: list[list[str]] = []
        for r in sheet.findall(".//a:row", NS):
            vals: list[str] = []
            for c in r.findall("a:c", NS):
                idx = colnum(c.attrib["r"])
                vals.extend([""] * (idx - len(vals) + 1))
                if c.attrib.get("t") == "s":
                    raw = c.findtext("a:v", default="", namespaces=NS)
                    vals[idx] = shared[int(raw)] if raw else ""
                elif c.attrib.get("t") == "inlineStr":
                    vals[idx] = text(c)
                else:
                    vals[idx] = c.findtext("a:v", default="", namespaces=NS)
            out.append([v.strip() for v in vals])
        return out


def parse_int(v: str) -> int | None:
    s = re.sub(r"[^0-9-]", "", v or "")
    return int(s) if re.fullmatch(r"-?\d+", s) else None


def parse_pct(v: str) -> float | None:
    m = re.search(r"-?\d+(?:\.\d+)?", v or "")
    return float(m.group(0)) if m else None


def parse_date(v: str) -> str | None:
    v = (v or "").strip()
    if re.fullmatch(r"\d+(?:\.\d+)?", v):
        n = float(v)
        if 20000 < n < 80000:  # Excel serial date, ignoring Excel's 1900 leap bug well enough here.
            return (dt.date(1899, 12, 30) + dt.timedelta(days=n)).isoformat()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%b %d, %Y", "%B %d, %Y"):
        try:
            return dt.datetime.strptime(v, fmt).date().isoformat()
        except ValueError:
            pass
    return None


def first_after(row: list[str], i: int, fn):
    for v in row[i + 1 :]:
        got = fn(v)
        if got is not None:
            return got
    return None


def parse_file(path: Path, scraped_at: str) -> dict:
    rs = rows(path)
    metrics = {c: 0 for c in METRIC_COLS}
    post_url = post_date = publish_time = None
    demographics = []
    current_category = None

    for row in rs:
        for i, cell in enumerate(row):
            if not post_url and re.search(r"https?://", cell):
                post_url = cell
            label = norm(cell)
            if label in ("date", "post date", "published date"):
                post_date = first_after(row, i, parse_date) or post_date
            if label in ("time", "publish time", "published time"):
                publish_time = next((v for v in row[i + 1 :] if re.search(r"\d{1,2}:\d{2}", v)), publish_time)
            if label in SCALARS:
                metrics[SCALARS[label]] = first_after(row, i, parse_int) or 0
            if label in CATEGORIES:
                current_category = CATEGORIES[label]
                pct = first_after(row, i, parse_pct)
                val = next((v for v in row[i + 1 :] if v and parse_pct(v) is None), None)
                if val and pct is not None:
                    demographics.append({"category": current_category, "value": val, "pct": pct})

        if current_category:
            pct = next((parse_pct(v) for v in row if parse_pct(v) is not None), None)
            val = next((v for v in row if v and parse_pct(v) is None and norm(v) not in CATEGORIES), None)
            if val and pct is not None:
                demographics.append({"category": current_category, "value": val, "pct": pct})

    if not post_url:
        raise SystemExit(f"{path}: no post URL found")

    return {
        "post_url": post_url,
        "scraped_at": scraped_at,
        "post_date": post_date,
        "publish_time": publish_time,
        **metrics,
        "demographics": list({(d["category"], d["value"]): d for d in demographics}.values()),
    }


def lit(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def sql(records: list[dict]) -> str:
    metric_cols = ", ".join(METRIC_COLS)
    metric_updates = ", ".join(f"{c}=EXCLUDED.{c}" for c in ["post_date", "publish_time", *METRIC_COLS])
    parts = [
        "BEGIN;",
        """
CREATE TABLE IF NOT EXISTS post_metrics (
  post_url text NOT NULL,
  scraped_at timestamptz NOT NULL,
  post_date date,
  publish_time text,
  impressions int NOT NULL DEFAULT 0,
  members_reached int NOT NULL DEFAULT 0,
  profile_viewers int NOT NULL DEFAULT 0,
  followers_gained int NOT NULL DEFAULT 0,
  social_engagements int NOT NULL DEFAULT 0,
  reactions int NOT NULL DEFAULT 0,
  comments int NOT NULL DEFAULT 0,
  reposts int NOT NULL DEFAULT 0,
  saves int NOT NULL DEFAULT 0,
  sends int NOT NULL DEFAULT 0,
  link_engagements int NOT NULL DEFAULT 0,
  premium_button_engagements int NOT NULL DEFAULT 0,
  PRIMARY KEY (post_url, scraped_at)
);
CREATE TABLE IF NOT EXISTS post_demographics (
  post_url text NOT NULL,
  scraped_at timestamptz NOT NULL,
  category text NOT NULL,
  value text NOT NULL,
  pct numeric NOT NULL,
  PRIMARY KEY (post_url, scraped_at, category, value)
);
""".strip(),
    ]
    for r in records:
        vals = [r["post_url"], r["scraped_at"], r["post_date"], r["publish_time"], *[r[c] for c in METRIC_COLS]]
        parts.append(
            f"INSERT INTO post_metrics (post_url, scraped_at, post_date, publish_time, {metric_cols})\n"
            f"VALUES ({', '.join(lit(v) for v in vals)})\n"
            f"ON CONFLICT (post_url, scraped_at) DO UPDATE SET {metric_updates};"
        )
        parts.append(
            f"DELETE FROM post_demographics WHERE post_url={lit(r['post_url'])} AND scraped_at={lit(r['scraped_at'])};"
        )
        for d in r["demographics"]:
            parts.append(
                "INSERT INTO post_demographics (post_url, scraped_at, category, value, pct) "
                f"VALUES ({lit(r['post_url'])}, {lit(r['scraped_at'])}, {lit(d['category'])}, {lit(d['value'])}, {lit(d['pct'])});"
            )
    parts.append("COMMIT;")
    return "\n".join(parts) + "\n"


def write_test_xlsx(path: Path) -> None:
    def c(ref: str, v: object) -> str:
        return f'<c r="{ref}" t="inlineStr"><is><t>{v}</t></is></c>'

    labels = [
        ("A1", "Post URL"), ("B1", "https://www.linkedin.com/feed/update/urn:li:activity:1/"),
        ("A2", "Date"), ("B2", "2026-07-01"), ("A3", "Time"), ("B3", "8:30 AM"),
        ("A5", "Impressions"), ("B5", 1234), ("A6", "Members reached"), ("B6", 1000),
        ("A7", "Profile viewers"), ("B7", 9), ("A8", "Followers gained"), ("B8", 2),
        ("A9", "Social engagements"), ("B9", 77), ("A10", "Reactions"), ("B10", 70),
        ("A11", "Comments"), ("B11", 3), ("A12", "Reposts"), ("B12", 1),
        ("A13", "Saves"), ("B13", 2), ("A14", "Sends"), ("B14", 1),
        ("A15", "Link engagements"), ("B15", 4), ("A16", "Premium button engagements"), ("B16", 5),
        ("A18", "Job title"), ("A19", "Engineer"), ("B19", "75%"),
        ("A20", "Founder"), ("B20", "25%"), ("A22", "Location"), ("A23", "Spain"), ("B23", "60%"),
    ]
    cells_by_row = {}
    for ref, value in labels:
        cells_by_row.setdefault(int(re.search(r"\d+", ref).group(0)), []).append(c(ref, value))
    sheet = "<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetData>" + "".join(
        f"<row r='{r}'>" + "".join(cells) + "</row>" for r, cells in sorted(cells_by_row.items())
    ) + "</sheetData></worksheet>"
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("xl/worksheets/sheet1.xml", sheet)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "example-data.xlsx"
        write_test_xlsx(p)
        rec = parse_file(p, "2026-07-06T00:00:00Z")
        assert rec["impressions"] == 1234
        assert rec["post_date"] == "2026-07-01"
        assert {x["value"] for x in rec["demographics"]} >= {"Engineer", "Founder", "Spain"}
        assert "ON CONFLICT (post_url, scraped_at)" in sql([rec])
    print("self-test ok")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--scraped-at", default=dt.datetime.now(dt.timezone.utc).isoformat())
    ap.add_argument("--json", action="store_true", help="print parsed rows instead of SQL")
    ap.add_argument("--psql", help="psql command to pipe SQL into, e.g. 'kubectl exec -i -n dev deploy/dev-postgres -- psql -U postgres -d linkedin -v ON_ERROR_STOP=1'")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.files:
        ap.error("provide at least one XLSX file")

    records = []
    for p in args.files:
        if not zipfile.is_zipfile(p):
            print(f"skip {p}: not an XLSX file (probably LinkedIn returned HTML/debug output)", file=sys.stderr)
            continue
        records.append(parse_file(p, args.scraped_at))
    if not records:
        raise SystemExit("no valid XLSX files parsed")

    if args.json:
        print(json.dumps(records, indent=2))
        return

    statement = sql(records)
    if args.psql:
        subprocess.run(shlex.split(args.psql), input=statement.encode(), check=True)
    else:
        print(statement, end="")


if __name__ == "__main__":
    main()
