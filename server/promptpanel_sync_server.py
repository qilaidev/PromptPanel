#!/usr/bin/env python3
"""
PromptPanel Open-Source Cloud Sync Server (v2.0)
Zero-dependency, high-performance, multi-tenant isolated sync service.

Features:
- Token-isolated namespaces: Each Bearer token maps via SHA-256 to an isolated
  SQLite WAL database file (`namespaces/<sha256_prefix>.db`). Raw tokens are
  never persisted to disk.
- Optional token allowlist (`PP_SYNC_ALLOWED_TOKENS`) with constant-time HMAC
  verification for private server deployments.
- Server-side Conflict-to-Version-History merge: Concurrent edits from macOS,
  Android, and iOS never overwrite each other silently—displaced text is
  automatically preserved as an immutable `EntryVersion` record.
- Automatic rolling backups per namespace (`backups/<namespace>/`).
"""

from __future__ import annotations

import datetime
import gzip
import hashlib
import hmac
import json
import os
import shutil
import sqlite3
import sys
import threading
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

SERVER_VERSION = "2.0.0"
SCHEMA_VERSION = 2

HOST = os.environ.get("PP_SYNC_HOST", "0.0.0.0")
PORT = int(os.environ.get("PP_SYNC_PORT", "18787"))
DATA_DIR = Path(os.environ.get("PP_SYNC_DATA_DIR", "/var/lib/promptpanel-sync"))
MAX_BODY_BYTES = int(os.environ.get("PP_SYNC_MAX_BODY_BYTES", str(16 * 1024 * 1024)))
MAX_BACKUPS_PER_NAMESPACE = int(os.environ.get("PP_SYNC_MAX_BACKUPS", "10"))
raw_allowed = os.environ.get("PP_SYNC_ALLOWED_TOKENS", "").strip()
ALLOWED_TOKENS = [t.strip() for t in raw_allowed.split(",") if t.strip()]

_NAMESPACE_LOCKS: dict[str, threading.Lock] = {}
_GLOBAL_LOCK = threading.Lock()


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def get_namespace_lock(namespace: str) -> threading.Lock:
    with _GLOBAL_LOCK:
        lock = _NAMESPACE_LOCKS.get(namespace)
        if lock is None:
            lock = threading.Lock()
            _NAMESPACE_LOCKS[namespace] = lock
        return lock


def verify_and_derive_namespace(auth_header: str | None) -> tuple[bool, str | None, str | None]:
    if not auth_header or not auth_header.lower().startswith("bearer "):
        return False, None, "Missing Authorization: Bearer <token> header"
    token = auth_header[7:].strip()
    if len(token) < 12:
        return False, None, "Bearer token must be at least 12 characters"

    if ALLOWED_TOKENS:
        matched = any(hmac.compare_digest(token.encode("utf-8"), allowed.encode("utf-8")) for allowed in ALLOWED_TOKENS)
        if not matched:
            return False, None, "Invalid or unauthorized Bearer token"

    digest = hashlib.sha256(f"promptpanel-v2:{token}".encode("utf-8")).hexdigest()[:32]
    return True, digest, None


def init_namespace_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=15.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS kv_records (
            kind TEXT NOT NULL,
            id TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            PRIMARY KEY (kind, id)
        );
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_kv_kind_updated
        ON kv_records (kind, updated_at);
        """
    )
    return conn


def load_envelope_from_db(conn: sqlite3.Connection, device_id: str = "promptpanel-sync-server") -> dict[str, Any]:
    projects = [
        json.loads(row["payload_json"])
        for row in conn.execute("SELECT payload_json FROM kv_records WHERE kind = 'project' ORDER BY updated_at ASC")
    ]
    entries = [
        json.loads(row["payload_json"])
        for row in conn.execute("SELECT payload_json FROM kv_records WHERE kind = 'entry' ORDER BY updated_at ASC")
    ]
    versions = [
        json.loads(row["payload_json"])
        for row in conn.execute("SELECT payload_json FROM kv_records WHERE kind = 'version' ORDER BY updated_at ASC")
    ]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "deviceId": device_id,
        "exportedAt": utc_now_iso(),
        "projects": projects,
        "entries": entries,
        "versions": versions,
    }


def count_namespace_stats(db_path: Path) -> tuple[int, int, int]:
    if not db_path.exists():
        return 0, 0, 0
    conn = init_namespace_db(db_path)
    try:
        p_count = conn.execute("SELECT COUNT(*) FROM kv_records WHERE kind = 'project'").fetchone()[0]
        e_count = conn.execute("SELECT COUNT(*) FROM kv_records WHERE kind = 'entry'").fetchone()[0]
        v_count = conn.execute("SELECT COUNT(*) FROM kv_records WHERE kind = 'version'").fetchone()[0]
        return int(p_count), int(e_count), int(v_count)
    finally:
        conn.close()


def rotate_namespace_backup(db_path: Path, namespace: str) -> None:
    if not db_path.exists():
        return
    backup_dir = DATA_DIR / "backups" / namespace
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
    target = backup_dir / f"sync-{stamp}.db"
    if not target.exists():
        shutil.copy2(db_path, target)
    backups = sorted(backup_dir.glob("sync-*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for stale in backups[MAX_BACKUPS_PER_NAMESPACE:]:
        try:
            stale.unlink()
        except OSError:
            pass


def _get_field(obj: dict[str, Any], camel_key: str, snake_key: str, default: Any = None) -> Any:
    val = obj.get(camel_key)
    if val is not None:
        return val
    val = obj.get(snake_key)
    if val is not None:
        return val
    return default


def merge_envelope_into_db(conn: sqlite3.Connection, incoming: dict[str, Any]) -> dict[str, int]:
    stats = {
        "projectsCreated": 0,
        "projectsUpdated": 0,
        "entriesCreated": 0,
        "entriesUpdated": 0,
        "conflictsPreserved": 0,
    }
    remote_device = str(_get_field(incoming, "deviceId", "device_id") or "remote-client")

    with conn:
        # 1. Merge Projects
        for proj in incoming.get("projects", []):
            if not isinstance(proj, dict) or not proj.get("id"):
                continue
            pid = str(proj["id"])
            inc_updated = str(_get_field(proj, "updatedAt", "updated_at") or "")
            row = conn.execute(
                "SELECT updated_at, payload_json FROM kv_records WHERE kind = 'project' AND id = ?",
                (pid,),
            ).fetchone()
            if row is None:
                conn.execute(
                    "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('project', ?, ?, ?)",
                    (pid, inc_updated, json.dumps(proj, ensure_ascii=False)),
                )
                stats["projectsCreated"] += 1
            elif inc_updated > str(row["updated_at"]):
                conn.execute(
                    "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                    (inc_updated, json.dumps(proj, ensure_ascii=False), pid),
                )
                stats["projectsUpdated"] += 1

        # Load existing versions index for conflict preservation
        existing_versions_by_entry: dict[str, list[dict[str, Any]]] = {}
        for v_row in conn.execute("SELECT payload_json FROM kv_records WHERE kind = 'version'"):
            v_obj = json.loads(v_row["payload_json"])
            eid = str(_get_field(v_obj, "entryId", "entry_id") or "")
            existing_versions_by_entry.setdefault(eid, []).append(v_obj)

        def insert_version_obj(v_obj: dict[str, Any]) -> None:
            vid = str(v_obj.get("id") or uuid.uuid4())
            v_obj["id"] = vid
            eid_val = str(_get_field(v_obj, "entryId", "entry_id") or "")
            vnum_val = int(_get_field(v_obj, "versionNumber", "version_number", 1))
            note_val = _get_field(v_obj, "changeNote", "change_note")
            v_created = str(_get_field(v_obj, "createdAt", "created_at") or utc_now_iso())
            v_obj["entryId"] = eid_val
            v_obj["entry_id"] = eid_val
            v_obj["versionNumber"] = vnum_val
            v_obj["version_number"] = vnum_val
            if note_val is not None:
                v_obj["changeNote"] = note_val
                v_obj["change_note"] = note_val
            v_obj["createdAt"] = v_created
            v_obj["created_at"] = v_created
            conn.execute(
                "INSERT OR IGNORE INTO kv_records (kind, id, updated_at, payload_json) VALUES ('version', ?, ?, ?)",
                (vid, v_created, json.dumps(v_obj, ensure_ascii=False)),
            )
            existing_versions_by_entry.setdefault(eid_val, []).append(v_obj)

        # 2. Merge Entries with automatic Conflict-to-Version-History preservation
        for entry in incoming.get("entries", []):
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            eid = str(entry["id"])
            inc_updated = str(_get_field(entry, "updatedAt", "updated_at") or "")
            inc_created = str(_get_field(entry, "createdAt", "created_at") or inc_updated or utc_now_iso())
            row = conn.execute(
                "SELECT updated_at, payload_json FROM kv_records WHERE kind = 'entry' AND id = ?",
                (eid,),
            ).fetchone()

            if row is None:
                conn.execute(
                    "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('entry', ?, ?, ?)",
                    (eid, inc_updated, json.dumps(entry, ensure_ascii=False)),
                )
                stats["entriesCreated"] += 1
                if not existing_versions_by_entry.get(eid):
                    insert_version_obj(
                        {
                            "id": f"{eid}-v1",
                            "entryId": eid,
                            "versionNumber": 1,
                            "title": entry.get("title", ""),
                            "content": entry.get("content", ""),
                            "changeNote": f"初始同步 ({remote_device})",
                            "createdAt": inc_created,
                        }
                    )
            else:
                server_entry = json.loads(row["payload_json"])
                srv_updated = str(row["updated_at"])
                has_diff = (
                    server_entry.get("content") != entry.get("content")
                    or server_entry.get("title") != entry.get("title")
                )

                if inc_updated > srv_updated:
                    if has_diff:
                        vers = existing_versions_by_entry.get(eid, [])
                        max_ver = max((int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0)
                        latest_snap = max(vers, key=lambda v: int(_get_field(v, "versionNumber", "version_number", 0)), default=None)
                        if (
                            latest_snap is None
                            or latest_snap.get("content") != server_entry.get("content")
                            or latest_snap.get("title") != server_entry.get("title")
                        ):
                            max_ver += 1
                            insert_version_obj(
                                {
                                    "id": str(uuid.uuid4()),
                                    "entryId": eid,
                                    "versionNumber": max_ver,
                                    "title": server_entry.get("title", ""),
                                    "content": server_entry.get("content", ""),
                                    "changeNote": "服务端合并前版本自动留存",
                                    "createdAt": srv_updated or utc_now_iso(),
                                }
                            )
                            stats["conflictsPreserved"] += 1

                    # Preserve max useCount and latest lastUsedAt across snake_case and camelCase
                    srv_use_count = int(_get_field(server_entry, "useCount", "use_count", 0))
                    inc_use_count = int(_get_field(entry, "useCount", "use_count", 0))
                    merged_use_count = max(srv_use_count, inc_use_count)
                    if "use_count" in entry or "useCount" not in entry:
                        entry["use_count"] = merged_use_count
                    if "useCount" in entry:
                        entry["useCount"] = merged_use_count

                    srv_used = _get_field(server_entry, "lastUsedAt", "last_used_at")
                    inc_used = _get_field(entry, "lastUsedAt", "last_used_at")
                    merged_used = max(str(srv_used), str(inc_used)) if (srv_used and inc_used) else (srv_used or inc_used)
                    if merged_used is not None:
                        if "last_used_at" in entry or "lastUsedAt" not in entry:
                            entry["last_used_at"] = merged_used
                        if "lastUsedAt" in entry:
                            entry["lastUsedAt"] = merged_used

                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                        (inc_updated, json.dumps(entry, ensure_ascii=False), eid),
                    )
                    stats["entriesUpdated"] += 1
                elif inc_updated < srv_updated and has_diff:
                    # Incoming is older than server state, but has different text -> save incoming as historical version
                    vers = existing_versions_by_entry.get(eid, [])
                    already_recorded = any(
                        v.get("content") == entry.get("content") and v.get("title") == entry.get("title")
                        for v in vers
                    )
                    if not already_recorded:
                        max_ver = max((int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0) + 1
                        insert_version_obj(
                            {
                                "id": str(uuid.uuid4()),
                                "entryId": eid,
                                "versionNumber": max_ver,
                                "title": entry.get("title", ""),
                                "content": entry.get("content", ""),
                                "changeNote": f"并发历史版本自动留存 ({remote_device})",
                                "createdAt": inc_updated or utc_now_iso(),
                            }
                        )
                        stats["conflictsPreserved"] += 1

        # 3. Merge Explicit Incoming Versions
        for ver in incoming.get("versions", []):
            if not isinstance(ver, dict) or not ver.get("id"):
                continue
            eid = str(_get_field(ver, "entryId", "entry_id") or "")
            if not eid:
                continue
            vnum = int(_get_field(ver, "versionNumber", "version_number", 1))
            vers = existing_versions_by_entry.get(eid, [])
            if any(v.get("id") == ver["id"] for v in vers):
                continue
            has_num_collision = any(int(_get_field(v, "versionNumber", "version_number", 0)) == vnum for v in vers)
            if not has_num_collision:
                insert_version_obj(dict(ver))
            else:
                already_has_same_text = any(
                    v.get("content") == ver.get("content") and v.get("title") == ver.get("title")
                    for v in vers
                )
                if not already_has_same_text:
                    max_ver = max((int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0)
                    renumbered = dict(ver)
                    renumbered["versionNumber"] = max_ver + 1
                    renumbered["version_number"] = max_ver + 1
                    insert_version_obj(renumbered)

    return stats


class SyncRequestHandler(BaseHTTPRequestHandler):
    server_version = f"PromptPanelSync/{SERVER_VERSION}"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write(f"[{utc_now_iso()}] {self.address_string()} {fmt % args}\n")

    def _send_json(self, status: int, payload: dict[str, Any], extra_headers: dict[str, str] | None = None) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        accept_encoding = self.headers.get("Accept-Encoding", "")
        use_gzip = "gzip" in accept_encoding and len(raw) > 1024
        body = gzip.compress(raw) if use_gzip else raw

        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-PromptPanel-Schema", str(SCHEMA_VERSION))
        if use_gzip:
            self.send_header("Content-Encoding", "gzip")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path in ("/health", "/v1/health"):
            ok, namespace, _ = verify_and_derive_namespace(self.headers.get("Authorization"))
            p_count, e_count, v_count = (0, 0, 0)
            if ok and namespace:
                db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
                p_count, e_count, v_count = count_namespace_stats(db_path)
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "service": "promptpanel-sync-server",
                    "version": SERVER_VERSION,
                    "schemaVersion": SCHEMA_VERSION,
                    "authenticated": ok,
                    "namespace": namespace[:12] if namespace else None,
                    "projectCount": p_count,
                    "entryCount": e_count,
                    "versionCount": v_count,
                    "serverTime": utc_now_iso(),
                },
            )
            return

        if path not in ("/", "/sync", "/v1/sync", "/v1/promptpanel"):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        ok, namespace, err = verify_and_derive_namespace(self.headers.get("Authorization"))
        if not ok or not namespace:
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": err or "Unauthorized"})
            return

        lock = get_namespace_lock(namespace)
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            conn = init_namespace_db(db_path)
            try:
                envelope = load_envelope_from_db(conn)
            finally:
                conn.close()

        self._send_json(
            HTTPStatus.OK,
            envelope,
            extra_headers={"X-PromptPanel-Namespace": namespace[:12]},
        )

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if path not in ("/", "/sync", "/v1/sync", "/v1/promptpanel"):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        ok, namespace, err = verify_and_derive_namespace(self.headers.get("Authorization"))
        if not ok or not namespace:
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": err or "Unauthorized"})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length <= 0 or content_length > MAX_BODY_BYTES:
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"Invalid Content-Length (max {MAX_BODY_BYTES} bytes)"},
            )
            return

        raw_body = self.rfile.read(content_length)
        if self.headers.get("Content-Encoding", "").lower() == "gzip":
            try:
                raw_body = gzip.decompress(raw_body)
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Invalid gzip payload: {exc}"})
                return

        try:
            incoming = json.loads(raw_body.decode("utf-8"))
        except Exception as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Invalid JSON payload: {exc}"})
            return

        lock = get_namespace_lock(namespace)
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            conn = init_namespace_db(db_path)
            try:
                stats = merge_envelope_into_db(conn, incoming)
                merged_envelope = load_envelope_from_db(conn)
            finally:
                conn.close()
            rotate_namespace_backup(db_path, namespace)

        self._send_json(
            HTTPStatus.OK,
            merged_envelope,
            extra_headers={
                "X-PromptPanel-Namespace": namespace[:12],
                "X-PromptPanel-Merge-Stats": json.dumps(stats),
            },
        )


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "namespaces").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "backups").mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), SyncRequestHandler)
    print(
        f"PromptPanel Sync Server v{SERVER_VERSION} listening on {HOST}:{PORT} "
        f"(data_dir={DATA_DIR}, allowlist_count={len(ALLOWED_TOKENS)})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
