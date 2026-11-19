"""
CivicBuddy backup & storage management. Plan: backup_flowchart.png and
README.md in this folder.

Modes
-----
  weekly   Full backup (database + new photos) to Google Drive, verify,
           report, tidy old database exports, then handle the storage level.
  check    Quick storage check (every 6 hours):
             < 80%   nothing to do
             80-90%  warning (at most once a day)
             > 90%   run the full backup now, then free space

Freeing space (only above 90%, only after a verified backup in the same run):
  oldest surveys first, never surveys from the last PROTECT_DAYS days; each
  photo whose full-size original is confirmed in Drive (same size) is
  replaced in Supabase by a small preview with the same file name, until
  storage is below FREE_TO_PERCENT.

A run "fails" (non-zero exit) for warnings and errors, so GitHub emails you.

Environment
-----------
  SUPABASE_URL                https://<project>.supabase.co
  SUPABASE_SERVICE_ROLE_KEY   service-role (secret) key, never the anon key
  RCLONE_REMOTE               rclone remote for Google Drive (default unidrive)
  BACKUP_ROOT                 folder in Drive (default CivicBuddy-Backup)
  STORAGE_LIMIT_MB            Supabase storage limit in MB (default 1000 = free plan's
                              1 GB; Supabase counts 1 GB = 1,000,000,000 bytes)
  FREE_SPACE=1                allow freeing space above 90% (off by default:
                              the backup is rolled out first)
  DRY_RUN=1                   do everything except changing Supabase / Drive

Logs show counts and sizes only (no file paths or survey content), because
the app repository and its Actions logs are public.
"""

import argparse
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import requests
from PIL import Image, ImageOps

# ------------------------------------------------------------------
# Settings
# ------------------------------------------------------------------

def _secret(name: str) -> str:
    # Tolerate a pasted "NAME=value" line and stray spaces / line breaks.
    value = os.environ.get(name, "").strip()
    return value.split("=", 1)[1].strip() if value.startswith(f"{name}=") else value


SUPABASE_URL = _secret("SUPABASE_URL").rstrip("/")
SERVICE_KEY = _secret("SUPABASE_SERVICE_ROLE_KEY")
REMOTE = os.environ.get("RCLONE_REMOTE", "unidrive")
ROOT = os.environ.get("BACKUP_ROOT", "CivicBuddy-Backup")
# Supabase's dashboard counts decimal units: 1 GB = 1,000 MB = 10^9 bytes.
LIMIT_BYTES = int(os.environ.get("STORAGE_LIMIT_MB", "1000")) * 1_000_000
DRY_RUN = os.environ.get("DRY_RUN") == "1"
FREE_SPACE = os.environ.get("FREE_SPACE") == "1"

PHOTO_BUCKET = "survey-photos"
WARN_PERCENT = 80
CLEAN_PERCENT = 90
FREE_TO_PERCENT = 70
PROTECT_DAYS = 30
PREVIEW_SIDE = 480        # px, longest side of a preview
PREVIEW_QUALITY = 70
PREVIEW_MAX_BYTES = 150_000   # a photo this small is already a preview
KEEP_WEEKLY_EXPORTS = 12

DRIVE = f"{REMOTE}:{ROOT}"
NOW = datetime.now(timezone.utc)
TODAY = NOW.strftime("%Y-%m-%d")


class BackupError(Exception):
    """Stops the run; nothing after the failing step is done."""


def log(message: str) -> None:
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {message}", flush=True)


def mb(n: float) -> str:
    # Decimal MB, the same unit as Supabase's Usage page.
    return f"{n / 1_000_000:.1f} MB"


# ------------------------------------------------------------------
# Supabase (REST + Storage API with the service-role key)
# ------------------------------------------------------------------

def headers(extra=None) -> dict:
    h = {"apikey": SERVICE_KEY}
    # Legacy JWT keys also go in Authorization; new sb_secret_ keys must not.
    if SERVICE_KEY.startswith("eyJ"):
        h["Authorization"] = f"Bearer {SERVICE_KEY}"
    h.update(extra or {})
    return h


def sb(method: str, path: str, **kwargs) -> requests.Response:
    try:
        response = requests.request(method, f"{SUPABASE_URL}{path}",
                                    headers=headers(kwargs.pop("headers", None)),
                                    timeout=kwargs.pop("timeout", 60), **kwargs)
    except requests.RequestException as e:
        raise BackupError(f"Cannot reach Supabase ({type(e).__name__}). "
                          "Check SUPABASE_URL and the internet connection.") from None
    if response.status_code >= 400:
        raise BackupError(f"Supabase {method} {path.split('?')[0]} -> "
                          f"{response.status_code}: {response.text[:200]}")
    return response


def fetch_surveys() -> list:
    rows, page = [], 1000
    while True:
        batch = sb("GET", f"/rest/v1/surveys?select=*&order=created_at.asc"
                          f"&limit={page}&offset={len(rows)}").json()
        rows.extend(batch)
        if len(batch) < page:
            return rows


def list_bucket(bucket: str, prefix: str = "") -> dict:
    """{path: size} of every file in a bucket (folders walked recursively)."""
    files, offset = {}, 0
    while True:
        items = sb("POST", f"/storage/v1/object/list/{bucket}", json={
            "prefix": prefix, "limit": 1000, "offset": offset,
            "sortBy": {"column": "name", "order": "asc"},
        }).json()
        for item in items:
            path = f"{prefix}/{item['name']}" if prefix else item["name"]
            if item.get("id") is None:          # a folder
                files.update(list_bucket(bucket, path))
            else:
                files[path] = int((item.get("metadata") or {}).get("size") or 0)
        if len(items) < 1000:
            return files
        offset += 1000


def storage_usage() -> tuple:
    """(bytes used in all buckets, {path: size} of survey photos)."""
    buckets = [b["name"] for b in sb("GET", "/storage/v1/bucket").json()]
    total, photos = 0, {}
    for bucket in buckets:
        files = list_bucket(bucket)
        total += sum(files.values())
        if bucket == PHOTO_BUCKET:
            photos = files
    return total, photos


def object_url(path: str) -> str:
    return f"/storage/v1/object/{PHOTO_BUCKET}/{quote(path)}"


# ------------------------------------------------------------------
# Google Drive via rclone
# ------------------------------------------------------------------

def rclone(*args, capture=False) -> str:
    cmd = ["rclone", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise BackupError(f"rclone {args[0]} failed: {result.stderr.strip()[-300:]}")
    return result.stdout if capture else ""


def drive_files(folder: str) -> dict:
    """{path: size} under a Drive folder (empty if it does not exist yet)."""
    try:
        out = rclone("lsjson", "-R", "--files-only", f"{DRIVE}/{folder}", capture=True)
    except BackupError as e:
        if "directory not found" in str(e).lower():
            return {}
        raise
    return {f["Path"]: int(f["Size"]) for f in json.loads(out or "[]")}


def drive_read_json(name: str, default):
    try:
        return json.loads(rclone("cat", f"{DRIVE}/{name}", capture=True) or "null") or default
    except BackupError:
        return default


def drive_write_text(name: str, text: str) -> None:
    if DRY_RUN:
        log(f"(dry run) would write {name}")
        return
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".tmp", encoding="utf-8") as f:
        f.write(text)
    rclone("copyto", f.name, f"{DRIVE}/{name}")
    os.unlink(f.name)


# ------------------------------------------------------------------
# Database export (same column layout as the website's Download data)
# ------------------------------------------------------------------

def topic_of(question: str) -> str:
    text = str(question).replace("`", "'").replace("’", "'").strip()
    return text.split(":", 1)[0].strip()


def question_columns(answer_maps) -> list:
    columns = {}
    for answers in answer_maps:
        for question in (answers or {}):
            columns.setdefault(topic_of(question), question.strip())
    return list(columns.items())


def answer_for(answers, topic) -> str:
    for question, answer in (answers or {}).items():
        if topic_of(question) == topic:
            return answer
    return ""


def citizens_of(data: dict) -> list:
    if isinstance(data.get("citizens"), list):
        return data["citizens"]
    return [data["citizen"]] if data.get("citizen") else []


def to_csv(header, rows) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(header)
    writer.writerows(rows)
    return "﻿" + buf.getvalue()   # BOM: Excel shows Bengali correctly


def export_database(surveys: list, out_dir: str) -> None:
    newest_first = sorted(surveys, key=lambda s: s.get("created_at") or "", reverse=True)

    with open(os.path.join(out_dir, "surveys.json"), "w", encoding="utf-8") as f:
        json.dump(surveys, f, ensure_ascii=False, indent=1)

    def write(name, header, rows):
        with open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="") as f:
            f.write(to_csv(header, rows))

    write("surveys.csv",
          ["survey_id", "status", "started_at", "ended_at", "submitted_at",
           "points", "photos", "citizen_interviews", "surveyor_id"],
          [[s.get("survey_id"), s.get("status"), s.get("started_at"), s.get("ended_at"),
            s.get("created_at"), len((s.get("survey_data") or {}).get("points") or []),
            sum(len(p.get("photos") or []) for p in (s.get("survey_data") or {}).get("points") or []),
            len(citizens_of(s.get("survey_data") or {})), s.get("user_id")]
           for s in newest_first])

    points = [(s, p) for s in newest_first for p in (s.get("survey_data") or {}).get("points") or []]
    pq = question_columns(p.get("surveyor_answers") for _, p in points)
    write("points.csv",
          ["survey_id", "point_number", "latitude", "longitude", "gps_accuracy_m", "area",
           "captured_at", "photo_paths", *[f"Q{i + 1}: {h}" for i, (_, h) in enumerate(pq)]],
          [[s.get("survey_id"), p.get("point_number"), p.get("latitude"), p.get("longitude"),
            p.get("accuracy_m"), p.get("area"), p.get("captured_at"),
            " | ".join(x.get("storage_path", "") for x in p.get("photos") or []),
            *[answer_for(p.get("surveyor_answers"), t) for t, _ in pq]]
           for s, p in points])

    citizens = [(s, c) for s in newest_first for c in citizens_of(s.get("survey_data") or {})]
    cq = question_columns(c.get("answers") for _, c in citizens)
    write("citizen_interviews.csv",
          ["survey_id", "interview_number", "occupation", "gender", "age", "latitude",
           "longitude", "gps_accuracy_m", "area", "location_captured_at",
           *[f"Q{i + 1}: {h}" for i, (_, h) in enumerate(cq)]],
          [[s.get("survey_id"), c.get("interview_number"), c.get("occupation"), c.get("gender"),
            c.get("age"), c.get("latitude"), c.get("longitude"), c.get("accuracy_m"),
            c.get("area"), c.get("location_captured_at"),
            *[answer_for(c.get("answers"), t) for t, _ in cq]]
           for s, c in citizens])


def tidy_exports() -> None:
    """Keep the newest KEEP_WEEKLY_EXPORTS exports plus the first of each month."""
    try:
        out = rclone("lsjson", "--dirs-only", f"{DRIVE}/db", capture=True)
    except BackupError:
        return
    dates = sorted(d["Path"] for d in json.loads(out or "[]") if len(d["Path"]) == 10)
    keep = set(dates[-KEEP_WEEKLY_EXPORTS:])
    first_of_month = {}
    for d in dates:
        first_of_month.setdefault(d[:7], d)
    keep |= set(first_of_month.values())
    for d in dates:
        if d not in keep:
            log(f"Removing old database export db/{d}")
            if not DRY_RUN:
                rclone("purge", f"{DRIVE}/db/{d}")


# ------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------

def check_settings() -> None:
    placeholder = "YOUR-PROJECT" in SUPABASE_URL.upper() or SERVICE_KEY.startswith("paste-")
    if not SUPABASE_URL or not SERVICE_KEY or placeholder:
        raise BackupError("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set "
                          "(fill in BackUp/.env, or the GitHub secrets).")
    if not SUPABASE_URL.startswith("https://"):
        raise BackupError("SUPABASE_URL should look like https://<project>.supabase.co")


def health_check() -> None:
    check_settings()
    sb("GET", "/rest/v1/surveys?select=id&limit=1")
    rclone("mkdir", DRIVE)
    rclone("lsjson", "--max-depth", "1", DRIVE, capture=True)
    log("Health check: Supabase and Google Drive reachable")


def backup_photos(supabase_photos: dict, state: dict, work: str) -> int:
    """Copies photos missing from Drive (or changed ones). Never deletes."""
    previews = state.setdefault("previews", {})
    in_drive = drive_files("photos")
    todo = [p for p, size in supabase_photos.items()
            if p not in in_drive or (in_drive[p] != size and p not in previews)]
    log(f"Photos: {len(supabase_photos)} in Supabase, {len(in_drive)} in Drive, "
        f"{len(todo)} to copy")
    if not todo:
        return 0

    total = sum(supabase_photos[p] for p in todo)
    if DRY_RUN:
        # Downloading would use Supabase's free egress for nothing.
        log(f"(dry run) would copy {len(todo)} photos ({mb(total)}) to Drive")
        return 0

    staging = os.path.join(work, "photos")
    done = {"files": 0, "bytes": 0}

    def download(path: str) -> None:
        for attempt in range(3):
            try:
                data = sb("GET", object_url(path), timeout=120).content
                break
            except BackupError:
                if attempt == 2:
                    raise
                time.sleep(2 * (attempt + 1))
        target = os.path.join(staging, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as f:
            f.write(data)
        done["files"] += 1
        done["bytes"] += len(data)
        if done["files"] % 50 == 0 or done["files"] == len(todo):
            log(f"  downloaded {done['files']}/{len(todo)} ({mb(done['bytes'])} of {mb(total)})")

    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(download, todo))

    rclone("copy", staging, f"{DRIVE}/photos", "--transfers", "8")
    log(f"Uploaded {len(todo)} photos ({mb(done['bytes'])}) to Drive")
    shutil.rmtree(staging, ignore_errors=True)
    return done["bytes"]


def verify(surveys: list, supabase_photos: dict, state: dict, export_dir: str) -> None:
    previews = state.get("previews", {})
    in_drive = {} if DRY_RUN else drive_files("photos")
    missing = []
    for path, size in supabase_photos.items():
        if DRY_RUN:
            break
        if path in previews:
            ok = path in in_drive and in_drive[path] == previews[path]["original_size"]
        else:
            ok = in_drive.get(path) == size
        if not ok:
            missing.append(path)
    if missing:
        raise BackupError(f"Verify failed: {len(missing)} photo(s) not safely in Drive. "
                          "Nothing was freed; the next run copies the missing ones.")
    with open(os.path.join(export_dir, "surveys.json"), encoding="utf-8") as f:
        exported = len(json.load(f))
    if exported != len(surveys):
        raise BackupError(f"Verify failed: exported {exported} of {len(surveys)} surveys.")
    if DRY_RUN:
        log(f"(dry run) verify: {len(surveys)} surveys exported; photo check skipped")
    else:
        log(f"Verify: {len(supabase_photos)} photos and {len(surveys)} surveys safely backed up")


def append_log(row: dict) -> None:
    try:
        existing = rclone("cat", f"{DRIVE}/backup_log.csv", capture=True)
    except BackupError:
        existing = ""
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=list(row))
    if not existing.strip():
        writer.writeheader()
    writer.writerow(row)
    drive_write_text("backup_log.csv", existing + buf.getvalue())


def make_preview(original: bytes) -> bytes:
    image = ImageOps.exif_transpose(Image.open(io.BytesIO(original))).convert("RGB")
    image.thumbnail((PREVIEW_SIDE, PREVIEW_SIDE))
    out = io.BytesIO()
    image.save(out, "JPEG", quality=PREVIEW_QUALITY, optimize=True)
    return out.getvalue()


def free_space(surveys: list, supabase_photos: dict, used: int, state: dict, work: str) -> int:
    """Replace full photos of the oldest surveys with previews until below
    FREE_TO_PERCENT. Returns the new usage in bytes."""
    previews = state.setdefault("previews", {})
    in_drive = drive_files("photos")
    target = LIMIT_BYTES * FREE_TO_PERCENT / 100
    cutoff = NOW - timedelta(days=PROTECT_DAYS)
    freed, replaced, skipped = 0, 0, 0

    for survey in sorted(surveys, key=lambda s: s.get("created_at") or ""):
        if used - freed <= target:
            break
        created = datetime.fromisoformat(str(survey.get("created_at")).replace("Z", "+00:00"))
        if created > cutoff:
            log(f"Reached surveys newer than {PROTECT_DAYS} days: stopping")
            break
        for point in (survey.get("survey_data") or {}).get("points") or []:
            for photo in point.get("photos") or []:
                path = photo.get("storage_path")
                size = supabase_photos.get(path)
                if not path or size is None or path in previews or size <= PREVIEW_MAX_BYTES:
                    continue
                if in_drive.get(path) != size:      # original not safely in Drive
                    skipped += 1
                    continue
                local = os.path.join(work, "original.jpg")
                rclone("copyto", f"{DRIVE}/photos/{path}", local)   # from Drive, not Supabase
                with open(local, "rb") as f:
                    preview = make_preview(f.read())
                if not DRY_RUN:
                    sb("POST", object_url(path), data=preview, timeout=120,
                       headers={"x-upsert": "true", "Content-Type": "image/jpeg",
                                "Cache-Control": "max-age=3600"})
                    previews[path] = {"original_size": size, "preview_size": len(preview),
                                      "date": TODAY}
                freed += size - len(preview)
                replaced += 1
                if used - freed <= target:
                    break
            if used - freed <= target:
                break

    log(f"{'(dry run) would free' if DRY_RUN else 'Freed'} {mb(freed)} by replacing "
        f"{replaced} photo(s) with previews; skipped {skipped} not yet in Drive")
    return used - freed


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

def full_run(trigger: str) -> int:
    work = tempfile.mkdtemp(prefix="civicbuddy-backup-")
    try:
        health_check()
        state = drive_read_json("state.json", {})

        surveys = fetch_surveys()
        export_dir = os.path.join(work, "db", TODAY)
        os.makedirs(export_dir)
        export_database(surveys, export_dir)
        if DRY_RUN:
            log(f"(dry run) would upload database export db/{TODAY}")
        else:
            rclone("copy", export_dir, f"{DRIVE}/db/{TODAY}")
        log(f"Database: {len(surveys)} surveys exported to db/{TODAY}")

        used, photos = storage_usage()
        copied = backup_photos(photos, state, work)
        verify(surveys, photos, state, export_dir)
        tidy_exports()

        percent = used / LIMIT_BYTES * 100
        log(f"Supabase storage: {mb(used)} of {mb(LIMIT_BYTES)} ({percent:.0f}%)")

        freed_to = None
        if percent > CLEAN_PERCENT and not FREE_SPACE:
            raise BackupError(f"URGENT: storage {percent:.0f}% full. Freeing space is "
                              "switched off (FREE_SPACE=0); turn it on or free space by hand.")
        if percent > CLEAN_PERCENT:
            log(f"Above {CLEAN_PERCENT}%: freeing space until below {FREE_TO_PERCENT}%")
            freed_to = free_space(surveys, photos, used, state, work)

        drive_write_text("state.json", json.dumps(state, indent=1))
        append_log({
            "date": NOW.strftime("%Y-%m-%d %H:%M UTC"), "trigger": trigger,
            "surveys": len(surveys), "photos": len(photos),
            "photos_copied_mb": f"{copied / 1e6:.1f}",
            "storage_used_mb": f"{used / 1e6:.1f}",
            "storage_percent": f"{percent:.0f}",
            "after_freeing_mb": "" if freed_to is None else f"{freed_to / 1e6:.1f}",
        })

        if freed_to is not None:
            after = freed_to / LIMIT_BYTES * 100
            if after > CLEAN_PERCENT:
                raise BackupError(f"URGENT: storage still {after:.0f}% after freeing space. "
                                  "Archive more surveys or upgrade Supabase.")
            log(f"Storage now {after:.0f}%")
        elif percent > WARN_PERCENT:
            return warn(state, percent)
        log("Backup finished")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def warn(state: dict, percent: float) -> int:
    """Warning at most once a day (a failed run = an email from GitHub)."""
    if state.get("last_warning") == TODAY:
        log(f"Storage {percent:.0f}% full (already warned today)")
        return 0
    state["last_warning"] = TODAY
    drive_write_text("state.json", json.dumps(state, indent=1))
    print(f"::warning::Storage {percent:.0f}% full")
    log(f"WARNING: Supabase storage {percent:.0f}% full")
    return 2


def check_run() -> int:
    check_settings()
    used, _ = storage_usage()
    percent = used / LIMIT_BYTES * 100
    log(f"Storage check: {mb(used)} of {mb(LIMIT_BYTES)} ({percent:.0f}%)")
    if percent > CLEAN_PERCENT:
        log(f"Above {CLEAN_PERCENT}%: starting the backup now")
        return full_run("storage-check")
    if percent > WARN_PERCENT:
        rclone("mkdir", DRIVE)
        return warn(drive_read_json("state.json", {}), percent)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("mode", choices=["weekly", "check"])
    args = parser.parse_args()
    if DRY_RUN:
        log("DRY RUN: nothing will be changed")
    try:
        return full_run("weekly") if args.mode == "weekly" else check_run()
    except BackupError as e:
        print(f"::error::{e}")
        log(f"FAILED: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
