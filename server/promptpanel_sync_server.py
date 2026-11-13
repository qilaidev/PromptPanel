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

import base64
import datetime
import gzip
import hashlib
import hmac
import io
import json
import os
import signal
import sqlite3
import sys
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError as _crypto_exc:  # pragma: no cover
    AESGCM = None  # type: ignore[assignment,misc]

SERVER_VERSION = "2.1.0"
SCHEMA_VERSION = 2
MAX_NAMESPACE_LOCK_CACHE = 1024
HKDF_SALT_V2 = b"PromptPanel-HKDF-Salt-v2"
HKDF_INFO_AEAD_V2 = b"promptpanel-v2-aes256gcm-key\x01"
WIRE_AAD_V2 = b"promptpanel-aead-v2"
DB_ENC_PREFIX = "enc:v2:"


def _parse_env_int(name: str, default: int, minimum: int, maximum: int | None = None) -> int:
    raw = os.environ.get(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"Environment variable {name}={raw!r} must be an integer") from exc
    if value < minimum or (maximum is not None and value > maximum):
        bound_desc = f"between {minimum} and {maximum}" if maximum is not None else f">= {minimum}"
        raise ValueError(f"Environment variable {name}={value} must be {bound_desc}")
    return value


HOST = os.environ.get("PP_SYNC_HOST", "0.0.0.0").strip() or "0.0.0.0"
PORT = _parse_env_int("PP_SYNC_PORT", 18787, minimum=1, maximum=65535)
DATA_DIR = Path(os.environ.get("PP_SYNC_DATA_DIR", "/var/lib/promptpanel-sync"))
MAX_BODY_BYTES = _parse_env_int("PP_SYNC_MAX_BODY_BYTES", 16 * 1024 * 1024, minimum=65536)
MAX_BACKUPS_PER_NAMESPACE = _parse_env_int("PP_SYNC_MAX_BACKUPS", 10, minimum=1, maximum=500)
MAX_GUARD_BACKUPS_PER_NAMESPACE = _parse_env_int("PP_SYNC_MAX_GUARD_BACKUPS", 5, minimum=1, maximum=100)
BACKUP_MIN_INTERVAL_SEC = _parse_env_int("PP_SYNC_BACKUP_MIN_INTERVAL_SEC", 600, minimum=0, maximum=86400)
GUARD_BACKUP_MIN_INTERVAL_SEC = 60
MASS_DELETE_MIN_COUNT = 3
MASS_DELETE_RATIO_THRESHOLD = 0.25
raw_allowed = os.environ.get("PP_SYNC_ALLOWED_TOKENS", "").strip()
ALLOWED_TOKENS = [t.strip() for t in raw_allowed.split(",") if t.strip()]

_NAMESPACE_LOCKS: dict[str, threading.Lock] = {}
_GLOBAL_LOCK = threading.Lock()
_SERVER_START_MONOTONIC = time.monotonic()
_METRICS: dict[str, int] = {
    "requestsTotal": 0,
    "syncGetTotal": 0,
    "syncPostTotal": 0,
    "syncErrorsTotal": 0,
    "conflictsPreservedTotal": 0,
    "massDeletionsProtectedTotal": 0,
}


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _record_metric(key: str, delta: int = 1) -> None:
    if delta == 0:
        return
    with _GLOBAL_LOCK:
        _METRICS[key] = _METRICS.get(key, 0) + delta


def _snapshot_metrics() -> dict[str, int]:
    with _GLOBAL_LOCK:
        return dict(_METRICS)


def get_namespace_lock(namespace: str) -> threading.Lock:
    with _GLOBAL_LOCK:
        lock = _NAMESPACE_LOCKS.get(namespace)
        if lock is None:
            if len(_NAMESPACE_LOCKS) >= MAX_NAMESPACE_LOCK_CACHE:
                unlocked_keys = [k for k, v in _NAMESPACE_LOCKS.items() if not v.locked()]
                for stale_key in unlocked_keys[: max(1, len(unlocked_keys) // 2)]:
                    _NAMESPACE_LOCKS.pop(stale_key, None)
            lock = threading.Lock()
            _NAMESPACE_LOCKS[namespace] = lock
        return lock


def derive_aead_key(token: str) -> bytes:
    """Derive a 256-bit AES-GCM key from the user's Bearer token via RFC 5869 HKDF-SHA256."""
    clean_token = token.strip().encode("utf-8")
    prk = hmac.new(HKDF_SALT_V2, clean_token, hashlib.sha256).digest()
    return hmac.new(prk, HKDF_INFO_AEAD_V2, hashlib.sha256).digest()


def verify_and_derive_namespace(auth_header: str | None) -> tuple[bool, str | None, bytes | None, str | None]:
    if not auth_header or not auth_header.lower().startswith("bearer "):
        return False, None, None, "Missing Authorization: Bearer <token> header"
    token = auth_header[7:].strip()
    if len(token) < 12:
        return False, None, None, "Bearer token must be at least 12 characters"

    if ALLOWED_TOKENS:
        matched = any(hmac.compare_digest(token.encode("utf-8"), allowed.encode("utf-8")) for allowed in ALLOWED_TOKENS)
        if not matched:
            return False, None, None, "Invalid or unauthorized Bearer token"

    digest = hashlib.sha256(f"promptpanel-v2:{token}".encode("utf-8")).hexdigest()[:32]
    aead_key = derive_aead_key(token)
    return True, digest, aead_key, None


def encrypt_db_record(obj: dict[str, Any], aead_key: bytes | None, kind: str, record_id: str) -> str:
    raw_str = json.dumps(obj, ensure_ascii=False)
    if aead_key is None or AESGCM is None:
        return raw_str
    nonce = os.urandom(12)
    aad = f"kv:{kind}:{record_id}".encode("utf-8")
    ct_and_tag = AESGCM(aead_key).encrypt(nonce, raw_str.encode("utf-8"), aad)
    return DB_ENC_PREFIX + base64.b64encode(nonce + ct_and_tag).decode("ascii")


def decrypt_db_record(raw_payload: str, aead_key: bytes | None, kind: str, record_id: str) -> tuple[dict[str, Any], bool]:
    """Return (parsed_dict, was_encrypted). Supports transparent migration from legacy plaintext rows."""
    if raw_payload.startswith(DB_ENC_PREFIX):
        if aead_key is None or AESGCM is None:
            raise ValueError("Cannot decrypt enc:v2 database record without AES-256-GCM key")
        combined = base64.b64decode(raw_payload[len(DB_ENC_PREFIX):])
        if len(combined) < 28:
            raise ValueError("Corrupted enc:v2 database record")
        nonce, ct_and_tag = combined[:12], combined[12:]
        aad = f"kv:{kind}:{record_id}".encode("utf-8")
        plain_bytes = AESGCM(aead_key).decrypt(nonce, ct_and_tag, aad)
        return json.loads(plain_bytes.decode("utf-8")), True
    return json.loads(raw_payload), False


def encrypt_wire_envelope(envelope: dict[str, Any], aead_key: bytes) -> dict[str, Any]:
    """Compress with Gzip and encrypt with AES-256-GCM (12B nonce + ciphertext + 16B tag)."""
    if AESGCM is None:
        return envelope
    raw_json = json.dumps(envelope, ensure_ascii=False).encode("utf-8")
    compressed = gzip.compress(raw_json, compresslevel=6)
    nonce = os.urandom(12)
    ct_and_tag = AESGCM(aead_key).encrypt(nonce, compressed, WIRE_AAD_V2)
    return {
        "cipher": "aes-256-gcm+gzip",
        "v": 2,
        "data": base64.b64encode(nonce + ct_and_tag).decode("ascii"),
    }


def decrypt_wire_envelope(incoming: dict[str, Any], aead_key: bytes | None) -> tuple[dict[str, Any], bool]:
    """Decrypt incoming wire envelope if encrypted with AES-256-GCM; returns (envelope_dict, was_encrypted)."""
    cipher_name = incoming.get("cipher")
    if not cipher_name:
        return incoming, False
    if cipher_name not in ("aes-256-gcm+gzip", "aes-256-gcm"):
        raise ValueError(f"Unsupported wire cipher: {cipher_name}")
    if aead_key is None or AESGCM is None:
        raise ValueError("AES-256-GCM key unavailable for wire decryption")
    b64_data = incoming.get("data")
    if not isinstance(b64_data, str) or not b64_data:
        raise ValueError("Encrypted envelope missing base64 'data' field")
    try:
        combined = base64.b64decode(b64_data)
    except Exception as exc:
        raise ValueError(f"Invalid base64 in encrypted envelope: {exc}") from exc
    if len(combined) < 28:
        raise ValueError("Encrypted envelope payload too short")
    nonce, ct_and_tag = combined[:12], combined[12:]
    try:
        decrypted = AESGCM(aead_key).decrypt(nonce, ct_and_tag, WIRE_AAD_V2)
    except Exception as exc:
        raise ValueError("AES-256-GCM authentication tag verification failed") from exc

    if cipher_name == "aes-256-gcm+gzip" or decrypted[:2] == b"\x1f\x8b":
        with gzip.GzipFile(fileobj=io.BytesIO(decrypted)) as gz_file:
            decompressed = gz_file.read(MAX_BODY_BYTES + 1)
        if len(decompressed) > MAX_BODY_BYTES:
            raise ValueError(f"Decompressed encrypted payload exceeds max {MAX_BODY_BYTES} bytes")
        decrypted = decompressed

    parsed = json.loads(decrypted.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError("Decrypted sync envelope root must be a JSON object")
    return parsed, True


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


def load_envelope_from_db(
    conn: sqlite3.Connection,
    device_id: str = "promptpanel-sync-server",
    aead_key: bytes | None = None,
) -> dict[str, Any]:
    projects: list[dict[str, Any]] = []
    entries: list[dict[str, Any]] = []
    versions: list[dict[str, Any]] = []
    legacy_rows_to_upgrade: list[tuple[str, str, dict[str, Any]]] = []

    for kind, target_list in (("project", projects), ("entry", entries), ("version", versions)):
        for row in conn.execute(
            "SELECT id, payload_json FROM kv_records WHERE kind = ? ORDER BY updated_at ASC",
            (kind,),
        ):
            rec_id = str(row["id"])
            obj, was_encrypted = decrypt_db_record(row["payload_json"], aead_key, kind, rec_id)
            if kind == "project" and isinstance(obj, dict):
                obj = _normalize_project_payload(obj)
            elif kind == "entry" and isinstance(obj, dict):
                obj = _normalize_entry_payload(obj)
            target_list.append(obj)
            if not was_encrypted and aead_key is not None and AESGCM is not None:
                legacy_rows_to_upgrade.append((kind, rec_id, obj))

    if legacy_rows_to_upgrade and aead_key is not None:
        with conn:
            for kind, rec_id, obj in legacy_rows_to_upgrade:
                enc_val = encrypt_db_record(obj, aead_key, kind, rec_id)
                conn.execute(
                    "UPDATE kv_records SET payload_json = ? WHERE kind = ? AND id = ?",
                    (enc_val, kind, rec_id),
                )

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


def rotate_namespace_backup(db_path: Path, namespace: str, is_guard: bool = False) -> None:
    if not db_path.exists():
        return
    backup_dir = DATA_DIR / "backups" / namespace
    backup_dir.mkdir(parents=True, exist_ok=True)
    prefix = "pre-drop" if is_guard else "sync"
    min_interval = GUARD_BACKUP_MIN_INTERVAL_SEC if is_guard else BACKUP_MIN_INTERVAL_SEC
    max_keep = MAX_GUARD_BACKUPS_PER_NAMESPACE if is_guard else MAX_BACKUPS_PER_NAMESPACE

    existing = sorted(backup_dir.glob(f"{prefix}-*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    if existing and min_interval > 0:
        try:
            if (time.time() - existing[0].stat().st_mtime) < min_interval:
                return
        except OSError:
            pass

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
    target = backup_dir / f"{prefix}-{stamp}.db"
    if not target.exists():
        tmp_target = backup_dir / f".{prefix}-{stamp}-{uuid.uuid4().hex[:8]}.db.tmp"
        src_conn: sqlite3.Connection | None = None
        dst_conn: sqlite3.Connection | None = None
        try:
            src_conn = sqlite3.connect(str(db_path), timeout=15.0)
            dst_conn = sqlite3.connect(str(tmp_target), timeout=15.0)
            src_conn.backup(dst_conn)
            dst_conn.close()
            dst_conn = None
            src_conn.close()
            src_conn = None
            tmp_target.replace(target)
        except Exception:
            try:
                if tmp_target.exists():
                    tmp_target.unlink()
            except OSError:
                pass
            raise
        finally:
            if dst_conn is not None:
                dst_conn.close()
            if src_conn is not None:
                src_conn.close()
    backups = sorted(backup_dir.glob(f"{prefix}-*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for stale in backups[max_keep:]:
        try:
            stale.unlink()
        except OSError:
            pass


def check_storage_writable() -> bool:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        probe = DATA_DIR / f".health-probe-{os.getpid()}-{threading.get_ident()}"
        probe.write_bytes(b"ok")
        probe.unlink()
        return True
    except OSError:
        return False


def _get_field(obj: dict[str, Any], camel_key: str, snake_key: str, default: Any = None) -> Any:
    val = obj.get(camel_key)
    if val is not None:
        return val
    val = obj.get(snake_key)
    if val is not None:
        return val
    return default


def _safe_int(val: Any, default: int = 0) -> int:
    try:
        return int(val)
    except (TypeError, ValueError):
        return default


def _bump_iso_timestamp(reference_iso: str) -> str:
    now_dt = datetime.datetime.now(datetime.timezone.utc)
    ref_dt = now_dt
    if reference_iso:
        try:
            cleaned = reference_iso.replace("Z", "+00:00")
            parsed = datetime.datetime.fromisoformat(cleaned)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=datetime.timezone.utc)
            if parsed > ref_dt:
                ref_dt = parsed
        except ValueError:
            pass
    bumped = ref_dt + datetime.timedelta(seconds=2)
    return bumped.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _prefer_camel_side(record: dict[str, Any]) -> bool:
    camel_u = str(record.get("updatedAt") or "")
    snake_u = str(record.get("updated_at") or "")
    if camel_u and snake_u:
        return camel_u >= snake_u
    return bool(camel_u)


def _pick_pair(
    record: dict[str, Any],
    camel_key: str,
    snake_key: str,
    prefer_camel: bool,
    default: Any = None,
    allow_none: bool = False,
) -> Any:
    first_key, second_key = (camel_key, snake_key) if prefer_camel else (snake_key, camel_key)
    if first_key in record:
        val = record.get(first_key)
        if allow_none or val is not None or second_key not in record:
            return val
    if second_key in record:
        return record.get(second_key)
    return default


def _normalize_project_payload(raw_proj: dict[str, Any]) -> dict[str, Any]:
    proj = dict(raw_proj)
    prefer_camel = _prefer_camel_side(proj)
    camel_u = str(proj.get("updatedAt") or "")
    snake_u = str(proj.get("updated_at") or "")
    resolved_updated = max(camel_u, snake_u) if (camel_u and snake_u) else (camel_u or snake_u or utc_now_iso())
    resolved_created = str(_pick_pair(proj, "createdAt", "created_at", prefer_camel) or resolved_updated)
    is_def = bool(_pick_pair(proj, "isDefault", "is_default", prefer_camel, False))
    if prefer_camel:
        kind_raw = proj.get("groupKindRaw") or proj.get("groupKind") or proj.get("group_kind") or ("category" if is_def else "project")
    else:
        kind_raw = proj.get("group_kind") or proj.get("groupKindRaw") or proj.get("groupKind") or ("category" if is_def else "project")
    is_arch = bool(_pick_pair(proj, "isArchived", "is_archived", prefer_camel, False))
    icon_val = _pick_pair(proj, "iconName", "icon_name", prefer_camel, allow_none=True)
    deleted_val = _pick_pair(proj, "deletedAt", "deleted_at", prefer_camel, allow_none=True)
    sort_val = _safe_int(_pick_pair(proj, "sortOrder", "sort_order", prefer_camel, 0))

    proj["isDefault"] = is_def
    proj["is_default"] = is_def
    proj["groupKindRaw"] = kind_raw
    proj["group_kind"] = kind_raw
    proj["isArchived"] = is_arch
    proj["is_archived"] = is_arch
    proj["iconName"] = icon_val
    proj["icon_name"] = icon_val
    proj["sortOrder"] = sort_val
    proj["sort_order"] = sort_val
    proj["createdAt"] = resolved_created
    proj["created_at"] = resolved_created
    proj["updatedAt"] = resolved_updated
    proj["updated_at"] = resolved_updated
    proj["deletedAt"] = deleted_val
    proj["deleted_at"] = deleted_val
    return proj


def _normalize_entry_payload(raw_entry: dict[str, Any]) -> dict[str, Any]:
    entry = dict(raw_entry)
    prefer_camel = _prefer_camel_side(entry)
    camel_u = str(entry.get("updatedAt") or "")
    snake_u = str(entry.get("updated_at") or "")
    resolved_updated = max(camel_u, snake_u) if (camel_u and snake_u) else (camel_u or snake_u or utc_now_iso())
    resolved_created = str(_pick_pair(entry, "createdAt", "created_at", prefer_camel) or resolved_updated)
    proj_id = str(_pick_pair(entry, "projectId", "project_id", prefer_camel, "") or "")
    is_pin = bool(_pick_pair(entry, "isPinned", "is_pinned", prefer_camel, False))
    is_comp = bool(_pick_pair(entry, "isCompleted", "is_completed", prefer_camel, False))
    sort_val = _safe_int(_pick_pair(entry, "sortOrder", "sort_order", prefer_camel, 0))
    use_c = max(
        _safe_int(entry.get("useCount"), 0),
        _safe_int(entry.get("use_count"), 0),
    )
    lu_c = entry.get("lastUsedAt")
    lu_s = entry.get("last_used_at")
    last_used = max(str(lu_c), str(lu_s)) if (lu_c and lu_s) else (lu_c or lu_s)
    deleted_val = _pick_pair(entry, "deletedAt", "deleted_at", prefer_camel, allow_none=True)
    src_val = _pick_pair(entry, "sourceEntryId", "source_entry_id", prefer_camel, allow_none=True)

    entry["projectId"] = proj_id
    entry["project_id"] = proj_id
    entry["isPinned"] = is_pin
    entry["is_pinned"] = is_pin
    entry["isCompleted"] = is_comp
    entry["is_completed"] = is_comp
    entry["sortOrder"] = sort_val
    entry["sort_order"] = sort_val
    entry["useCount"] = use_c
    entry["use_count"] = use_c
    entry["lastUsedAt"] = last_used
    entry["last_used_at"] = last_used
    entry["createdAt"] = resolved_created
    entry["created_at"] = resolved_created
    entry["updatedAt"] = resolved_updated
    entry["updated_at"] = resolved_updated
    entry["deletedAt"] = deleted_val
    entry["deleted_at"] = deleted_val
    entry["sourceEntryId"] = src_val
    entry["source_entry_id"] = src_val
    return entry


def merge_envelope_into_db(
    conn: sqlite3.Connection,
    incoming: dict[str, Any],
    aead_key: bytes | None = None,
    db_path: Path | None = None,
    namespace: str | None = None,
) -> dict[str, int]:
    if not isinstance(incoming, dict):
        raise ValueError("Sync envelope root must be a JSON object")
    for collection_key in ("projects", "entries", "versions"):
        collection_val = incoming.get(collection_key, [])
        if collection_val is not None and not isinstance(collection_val, list):
            raise ValueError(f"Sync envelope field '{collection_key}' must be a JSON array")

    stats = {
        "projectsCreated": 0,
        "projectsUpdated": 0,
        "entriesCreated": 0,
        "entriesUpdated": 0,
        "conflictsPreserved": 0,
        "protectedEntries": 0,
        "protectedProjects": 0,
    }
    remote_device = str(_get_field(incoming, "deviceId", "device_id") or "remote-client")
    allow_mass_delete = bool(_get_field(incoming, "allowMassDelete", "allow_mass_delete", False))

    # Pre-flight inspection for mass-tombstone circuit breaker & pre-drop guard backup
    srv_active_entries: dict[str, tuple[str, dict[str, Any]]] = {}
    for e_row in conn.execute("SELECT id, updated_at, payload_json FROM kv_records WHERE kind = 'entry'"):
        eid_str = str(e_row["id"])
        e_obj, _ = decrypt_db_record(e_row["payload_json"], aead_key, "entry", eid_str)
        if isinstance(e_obj, dict):
            e_obj = _normalize_entry_payload(e_obj)
        if e_obj.get("deletedAt") is None:
            srv_active_entries[eid_str] = (str(e_row["updated_at"]), e_obj)

    srv_active_count = len(srv_active_entries)
    incoming_deleting_count = 0
    for inc_entry in incoming.get("entries") or []:
        if not isinstance(inc_entry, dict) or not inc_entry.get("id"):
            continue
        norm_inc = _normalize_entry_payload(inc_entry)
        eid_str = str(norm_inc["id"])
        if eid_str in srv_active_entries:
            srv_upd, _ = srv_active_entries[eid_str]
            inc_upd = str(norm_inc.get("updatedAt") or "")
            if norm_inc.get("deletedAt") is not None and inc_upd > srv_upd:
                incoming_deleting_count += 1

    should_block_mass_delete = False
    if not allow_mass_delete:
        if (
            incoming_deleting_count >= MASS_DELETE_MIN_COUNT
            and (incoming_deleting_count / max(srv_active_count, 1)) >= MASS_DELETE_RATIO_THRESHOLD
        ) or (srv_active_count >= 2 and incoming_deleting_count == srv_active_count):
            should_block_mass_delete = True

    if (should_block_mass_delete or incoming_deleting_count > 0) and db_path is not None and namespace is not None:
        try:
            rotate_namespace_backup(db_path, namespace, is_guard=True)
        except Exception:
            pass

    with conn:
        remapped_project_ids: dict[str, str] = {}
        existing_default_id: str | None = None
        for p_row in conn.execute("SELECT id, payload_json FROM kv_records WHERE kind = 'project'"):
            p_id_str = str(p_row["id"])
            p_obj, _ = decrypt_db_record(p_row["payload_json"], aead_key, "project", p_id_str)
            if bool(_get_field(p_obj, "isDefault", "is_default", False)):
                existing_default_id = p_id_str
                break

        # 1. Merge Projects
        for proj in incoming.get("projects") or []:
            if not isinstance(proj, dict) or not proj.get("id"):
                continue
            proj = _normalize_project_payload(proj)
            pid = str(proj["id"])
            is_default_proj = bool(proj.get("isDefault", False))
            inc_updated = str(proj.get("updatedAt") or "")
            row = conn.execute(
                "SELECT updated_at, payload_json FROM kv_records WHERE kind = 'project' AND id = ?",
                (pid,),
            ).fetchone()
            if row is None:
                if is_default_proj and existing_default_id and existing_default_id != pid:
                    remapped_project_ids[pid] = existing_default_id
                    continue
                if is_default_proj and existing_default_id is None:
                    existing_default_id = pid
                conn.execute(
                    "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('project', ?, ?, ?)",
                    (pid, inc_updated, encrypt_db_record(proj, aead_key, "project", pid)),
                )
                if _get_field(proj, "deletedAt", "deleted_at") is None:
                    stats["projectsCreated"] += 1
            elif inc_updated > str(row["updated_at"]):
                srv_proj, _ = decrypt_db_record(row["payload_json"], aead_key, "project", pid)
                srv_deleted = _get_field(srv_proj, "deletedAt", "deleted_at")
                inc_deleted = _get_field(proj, "deletedAt", "deleted_at")
                if srv_deleted is None and inc_deleted is not None and should_block_mass_delete:
                    healed_proj = dict(srv_proj)
                    healed_proj.pop("deletedAt", None)
                    healed_proj.pop("deleted_at", None)
                    healed_upd = _bump_iso_timestamp(inc_updated)
                    if "updated_at" in healed_proj or "updatedAt" not in healed_proj:
                        healed_proj["updated_at"] = healed_upd
                    if "updatedAt" in healed_proj:
                        healed_proj["updatedAt"] = healed_upd
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                        (healed_upd, encrypt_db_record(healed_proj, aead_key, "project", pid), pid),
                    )
                    stats["protectedProjects"] += 1
                    continue
                conn.execute(
                    "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                    (inc_updated, encrypt_db_record(proj, aead_key, "project", pid), pid),
                )
                stats["projectsUpdated"] += 1

        # Load existing versions index for conflict preservation
        existing_versions_by_entry: dict[str, list[dict[str, Any]]] = {}
        for v_row in conn.execute("SELECT id, payload_json FROM kv_records WHERE kind = 'version'"):
            v_id_str = str(v_row["id"])
            v_obj, _ = decrypt_db_record(v_row["payload_json"], aead_key, "version", v_id_str)
            eid = str(_get_field(v_obj, "entryId", "entry_id") or "")
            existing_versions_by_entry.setdefault(eid, []).append(v_obj)

        def insert_version_obj(v_obj: dict[str, Any]) -> None:
            vid = str(v_obj.get("id") or uuid.uuid4())
            v_obj["id"] = vid
            eid_val = str(_get_field(v_obj, "entryId", "entry_id") or "")
            vnum_val = _safe_int(_get_field(v_obj, "versionNumber", "version_number", 1), default=1)
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
                (vid, v_created, encrypt_db_record(v_obj, aead_key, "version", vid)),
            )
            existing_versions_by_entry.setdefault(eid_val, []).append(v_obj)

        # 2. Merge Entries with automatic Conflict-to-Version-History preservation
        for entry in incoming.get("entries") or []:
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            entry = _normalize_entry_payload(entry)
            raw_pid = str(entry.get("projectId") or "")
            if raw_pid in remapped_project_ids:
                mapped_pid = remapped_project_ids[raw_pid]
                entry["project_id"] = mapped_pid
                entry["projectId"] = mapped_pid
            eid = str(entry["id"])
            inc_updated = str(entry.get("updatedAt") or "")
            inc_created = str(entry.get("createdAt") or inc_updated or utc_now_iso())
            row = conn.execute(
                "SELECT updated_at, payload_json FROM kv_records WHERE kind = 'entry' AND id = ?",
                (eid,),
            ).fetchone()

            if row is None:
                conn.execute(
                    "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('entry', ?, ?, ?)",
                    (eid, inc_updated, encrypt_db_record(entry, aead_key, "entry", eid)),
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
                server_entry, _ = decrypt_db_record(row["payload_json"], aead_key, "entry", eid)
                srv_updated = str(row["updated_at"])
                has_diff = (
                    server_entry.get("content") != entry.get("content")
                    or server_entry.get("title") != entry.get("title")
                )

                if inc_updated > srv_updated:
                    srv_deleted = _get_field(server_entry, "deletedAt", "deleted_at")
                    inc_deleted = _get_field(entry, "deletedAt", "deleted_at")
                    is_incoming_deletion = srv_deleted is None and inc_deleted is not None

                    if has_diff or is_incoming_deletion:
                        vers = existing_versions_by_entry.get(eid, [])
                        max_ver = max((_safe_int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0)
                        latest_snap = max(vers, key=lambda v: _safe_int(_get_field(v, "versionNumber", "version_number", 0)), default=None)
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
                                    "changeNote": "服务端删除前版本自动留存" if is_incoming_deletion else "服务端合并前版本自动留存",
                                    "createdAt": srv_updated or utc_now_iso(),
                                }
                            )
                            stats["conflictsPreserved"] += 1

                    # Preserve max useCount and latest lastUsedAt across snake_case and camelCase
                    srv_use_count = _safe_int(_get_field(server_entry, "useCount", "use_count", 0))
                    inc_use_count = _safe_int(_get_field(entry, "useCount", "use_count", 0))
                    merged_use_count = max(srv_use_count, inc_use_count)
                    srv_used = _get_field(server_entry, "lastUsedAt", "last_used_at")
                    inc_used = _get_field(entry, "lastUsedAt", "last_used_at")
                    merged_used = max(str(srv_used), str(inc_used)) if (srv_used and inc_used) else (srv_used or inc_used)

                    if is_incoming_deletion and should_block_mass_delete:
                        healed_entry = dict(server_entry)
                        healed_entry.pop("deletedAt", None)
                        healed_entry.pop("deleted_at", None)
                        healed_upd = _bump_iso_timestamp(inc_updated)
                        if "updated_at" in healed_entry or "updatedAt" not in healed_entry:
                            healed_entry["updated_at"] = healed_upd
                        if "updatedAt" in healed_entry:
                            healed_entry["updatedAt"] = healed_upd
                        if "use_count" in healed_entry or "useCount" not in healed_entry:
                            healed_entry["use_count"] = merged_use_count
                        if "useCount" in healed_entry:
                            healed_entry["useCount"] = merged_use_count
                        if merged_used is not None:
                            if "last_used_at" in healed_entry or "lastUsedAt" not in healed_entry:
                                healed_entry["last_used_at"] = merged_used
                            if "lastUsedAt" in healed_entry:
                                healed_entry["lastUsedAt"] = merged_used
                        conn.execute(
                            "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                            (healed_upd, encrypt_db_record(healed_entry, aead_key, "entry", eid), eid),
                        )
                        stats["protectedEntries"] += 1
                        continue

                    if "use_count" in entry or "useCount" not in entry:
                        entry["use_count"] = merged_use_count
                    if "useCount" in entry:
                        entry["useCount"] = merged_use_count
                    if merged_used is not None:
                        if "last_used_at" in entry or "lastUsedAt" not in entry:
                            entry["last_used_at"] = merged_used
                        if "lastUsedAt" in entry:
                            entry["lastUsedAt"] = merged_used

                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                        (inc_updated, encrypt_db_record(entry, aead_key, "entry", eid), eid),
                    )
                    stats["entriesUpdated"] += 1
                else:
                    if inc_updated < srv_updated and has_diff:
                        # Incoming is older than server state, but has different text -> save incoming as historical version
                        vers = existing_versions_by_entry.get(eid, [])
                        already_recorded = any(
                            v.get("content") == entry.get("content") and v.get("title") == entry.get("title")
                            for v in vers
                        )
                        if not already_recorded:
                            max_ver = max((_safe_int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0) + 1
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

                    # Monotonically converge useCount and lastUsedAt even when incoming updatedAt <= server updatedAt
                    srv_use_count = _safe_int(_get_field(server_entry, "useCount", "use_count", 0))
                    inc_use_count = _safe_int(_get_field(entry, "useCount", "use_count", 0))
                    srv_used = _get_field(server_entry, "lastUsedAt", "last_used_at")
                    inc_used = _get_field(entry, "lastUsedAt", "last_used_at")
                    merged_use_count = max(srv_use_count, inc_use_count)
                    merged_used = max(str(srv_used), str(inc_used)) if (srv_used and inc_used) else (srv_used or inc_used)
                    usage_changed = (merged_use_count > srv_use_count) or (
                        merged_used is not None and str(merged_used) != str(srv_used or "")
                    )
                    if usage_changed:
                        if "use_count" in server_entry or "useCount" not in server_entry:
                            server_entry["use_count"] = merged_use_count
                        if "useCount" in server_entry:
                            server_entry["useCount"] = merged_use_count
                        if merged_used is not None:
                            if "last_used_at" in server_entry or "lastUsedAt" not in server_entry:
                                server_entry["last_used_at"] = merged_used
                            if "lastUsedAt" in server_entry:
                                server_entry["lastUsedAt"] = merged_used
                        conn.execute(
                            "UPDATE kv_records SET payload_json = ? WHERE kind = 'entry' AND id = ?",
                            (encrypt_db_record(server_entry, aead_key, "entry", eid), eid),
                        )

        # 3. Revive any soft-deleted project that still contains active entries
        active_project_ids_needed: set[str] = set()
        for e_row in conn.execute("SELECT id, payload_json FROM kv_records WHERE kind = 'entry'"):
            e_obj, _ = decrypt_db_record(e_row["payload_json"], aead_key, "entry", str(e_row["id"]))
            if _get_field(e_obj, "deletedAt", "deleted_at") is None:
                pid_val = str(_get_field(e_obj, "projectId", "project_id") or "")
                if pid_val:
                    active_project_ids_needed.add(pid_val)

        for needed_pid in active_project_ids_needed:
            p_row = conn.execute(
                "SELECT updated_at, payload_json FROM kv_records WHERE kind = 'project' AND id = ?",
                (needed_pid,),
            ).fetchone()
            if p_row is not None:
                p_obj, _ = decrypt_db_record(p_row["payload_json"], aead_key, "project", needed_pid)
                if _get_field(p_obj, "deletedAt", "deleted_at") is not None:
                    revived = dict(p_obj)
                    revived.pop("deletedAt", None)
                    revived.pop("deleted_at", None)
                    revived_upd = _bump_iso_timestamp(str(p_row["updated_at"]))
                    if "updated_at" in revived or "updatedAt" not in revived:
                        revived["updated_at"] = revived_upd
                    if "updatedAt" in revived:
                        revived["updatedAt"] = revived_upd
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                        (revived_upd, encrypt_db_record(revived, aead_key, "project", needed_pid), needed_pid),
                    )
                    stats["protectedProjects"] += 1

        # 4. Merge Explicit Incoming Versions
        for ver in incoming.get("versions") or []:
            if not isinstance(ver, dict) or not ver.get("id"):
                continue
            eid = str(_get_field(ver, "entryId", "entry_id") or "")
            if not eid:
                continue
            vnum = _safe_int(_get_field(ver, "versionNumber", "version_number", 1), default=1)
            vers = existing_versions_by_entry.get(eid, [])
            if any(v.get("id") == ver["id"] for v in vers):
                continue
            has_num_collision = any(_safe_int(_get_field(v, "versionNumber", "version_number", 0)) == vnum for v in vers)
            if not has_num_collision:
                insert_version_obj(dict(ver))
            else:
                already_has_same_text = any(
                    v.get("content") == ver.get("content") and v.get("title") == ver.get("title")
                    for v in vers
                )
                if not already_has_same_text:
                    max_ver = max((_safe_int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0)
                    renumbered = dict(ver)
                    renumbered["versionNumber"] = max_ver + 1
                    renumbered["version_number"] = max_ver + 1
                    insert_version_obj(renumbered)

    return stats


class SyncRequestHandler(BaseHTTPRequestHandler):
    server_version = f"PromptPanelSync/{SERVER_VERSION}"

    def log_message(self, fmt: str, *args: Any) -> None:
        record = {
            "timestamp": utc_now_iso(),
            "service": "promptpanel-sync-server",
            "client": self.address_string(),
            "message": fmt % args,
        }
        sys.stderr.write(json.dumps(record, ensure_ascii=False) + "\n")

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
        _record_metric("requestsTotal")
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path in ("/health", "/v1/health"):
            ok, namespace, _, _ = verify_and_derive_namespace(self.headers.get("Authorization"))
            p_count, e_count, v_count = (0, 0, 0)
            if ok and namespace:
                db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
                if db_path.exists():
                    lock = get_namespace_lock(namespace)
                    with lock:
                        p_count, e_count, v_count = count_namespace_stats(db_path)
            storage_ok = check_storage_writable()
            status_code = HTTPStatus.OK if storage_ok else HTTPStatus.SERVICE_UNAVAILABLE
            self._send_json(
                status_code,
                {
                    "status": "ok" if storage_ok else "degraded",
                    "service": "promptpanel-sync-server",
                    "version": SERVER_VERSION,
                    "schemaVersion": SCHEMA_VERSION,
                    "encryption": "aes-256-gcm+gzip (HKDF-SHA256)" if AESGCM is not None else "none",
                    "atRestEncrypted": AESGCM is not None,
                    "storageWritable": storage_ok,
                    "uptimeSeconds": int(max(0.0, time.monotonic() - _SERVER_START_MONOTONIC)),
                    "authenticated": ok,
                    "namespace": namespace[:12] if namespace else None,
                    "projectCount": p_count,
                    "entryCount": e_count,
                    "versionCount": v_count,
                    "metrics": _snapshot_metrics(),
                    "serverTime": utc_now_iso(),
                },
            )
            return

        if path not in ("/", "/sync", "/v1/sync", "/v1/promptpanel"):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        ok, namespace, aead_key, err = verify_and_derive_namespace(self.headers.get("Authorization"))
        if not ok or not namespace or aead_key is None:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": err or "Unauthorized"})
            return

        _record_metric("syncGetTotal")
        lock = get_namespace_lock(namespace)
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            conn = init_namespace_db(db_path)
            try:
                envelope = load_envelope_from_db(conn, aead_key=aead_key)
            except Exception as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Decryption or database error: {exc}"})
                return
            finally:
                conn.close()

        wants_wire_cipher = "aes-256-gcm" in self.headers.get("X-PromptPanel-Cipher", "").lower()
        response_payload = encrypt_wire_envelope(envelope, aead_key) if wants_wire_cipher else envelope
        extra_hdrs = {"X-PromptPanel-Namespace": namespace[:12]}
        if wants_wire_cipher and AESGCM is not None:
            extra_hdrs["X-PromptPanel-Cipher"] = "aes-256-gcm+gzip"

        self._send_json(
            HTTPStatus.OK,
            response_payload,
            extra_headers=extra_hdrs,
        )

    def do_POST(self) -> None:
        _record_metric("requestsTotal")
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if path not in ("/", "/sync", "/v1/sync", "/v1/promptpanel"):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        ok, namespace, aead_key, err = verify_and_derive_namespace(self.headers.get("Authorization"))
        if not ok or not namespace or aead_key is None:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": err or "Unauthorized"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Malformed Content-Length header"})
            return

        if content_length <= 0 or content_length > MAX_BODY_BYTES:
            _record_metric("syncErrorsTotal")
            self._send_json(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE if content_length > MAX_BODY_BYTES else HTTPStatus.BAD_REQUEST,
                {"error": f"Invalid Content-Length (max {MAX_BODY_BYTES} bytes)"},
            )
            return

        raw_body = self.rfile.read(content_length)
        if self.headers.get("Content-Encoding", "").lower() == "gzip":
            try:
                with gzip.GzipFile(fileobj=io.BytesIO(raw_body)) as gz_file:
                    decompressed = gz_file.read(MAX_BODY_BYTES + 1)
                if len(decompressed) > MAX_BODY_BYTES:
                    _record_metric("syncErrorsTotal")
                    self._send_json(
                        HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                        {"error": f"Decompressed gzip payload exceeds max {MAX_BODY_BYTES} bytes"},
                    )
                    return
                raw_body = decompressed
            except Exception as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Invalid gzip payload: {exc}"})
                return

        try:
            raw_incoming = json.loads(raw_body.decode("utf-8"))
        except Exception as exc:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Invalid JSON payload: {exc}"})
            return

        if not isinstance(raw_incoming, dict):
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Sync envelope root must be a JSON object"})
            return

        try:
            incoming, was_wire_encrypted = decrypt_wire_envelope(raw_incoming, aead_key)
        except ValueError as exc:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        _record_metric("syncPostTotal")
        lock = get_namespace_lock(namespace)
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            conn = init_namespace_db(db_path)
            try:
                stats = merge_envelope_into_db(
                    conn,
                    incoming,
                    aead_key=aead_key,
                    db_path=db_path,
                    namespace=namespace,
                )
                merged_envelope = load_envelope_from_db(conn, aead_key=aead_key)
            except ValueError as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            finally:
                conn.close()
            rotate_namespace_backup(db_path, namespace)

        _record_metric("conflictsPreservedTotal", stats.get("conflictsPreserved", 0))
        _record_metric(
            "massDeletionsProtectedTotal",
            stats.get("protectedEntries", 0) + stats.get("protectedProjects", 0),
        )
        wants_wire_cipher = was_wire_encrypted or ("aes-256-gcm" in self.headers.get("X-PromptPanel-Cipher", "").lower())
        response_payload = encrypt_wire_envelope(merged_envelope, aead_key) if wants_wire_cipher else merged_envelope
        extra_hdrs = {
            "X-PromptPanel-Namespace": namespace[:12],
            "X-PromptPanel-Merge-Stats": json.dumps(stats),
        }
        if wants_wire_cipher and AESGCM is not None:
            extra_hdrs["X-PromptPanel-Cipher"] = "aes-256-gcm+gzip"

        self._send_json(
            HTTPStatus.OK,
            response_payload,
            extra_headers=extra_hdrs,
        )


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "namespaces").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "backups").mkdir(parents=True, exist_ok=True)
    if not check_storage_writable():
        sys.stderr.write(f"FATAL:PP_SYNC_DATA_DIR={DATA_DIR} is not writable\n")
        sys.exit(1)

    server = ThreadingHTTPServer((HOST, PORT), SyncRequestHandler)
    shutdown_initiated = threading.Event()

    def _handle_shutdown_signal(signum: int, _frame: Any) -> None:
        if shutdown_initiated.is_set():
            return
        shutdown_initiated.set()
        sig_name = signal.Signals(signum).name if signum in signal.Signals._value2member_map_ else str(signum)
        print(f"Received {sig_name}, draining in-flight sync requests before shutdown...", flush=True)
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _handle_shutdown_signal)
    signal.signal(signal.SIGINT, _handle_shutdown_signal)

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
        print("PromptPanel Sync Server stopped cleanly.", flush=True)


if __name__ == "__main__":
    main()
