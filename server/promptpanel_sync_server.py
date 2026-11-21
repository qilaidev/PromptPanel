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
import re
import signal
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError as _crypto_exc:  # pragma: no cover
    AESGCM = None  # type: ignore[assignment,misc]

SERVER_VERSION = "2.3.0"
SCHEMA_VERSION = 2
MAX_NAMESPACE_LOCK_CACHE = 1024
HKDF_SALT_V2 = b"PromptPanel-HKDF-Salt-v2"
HKDF_INFO_AEAD_V2 = b"promptpanel-v2-aes256gcm-key\x01"
WIRE_AAD_V2 = b"promptpanel-aead-v2"
DB_ENC_PREFIX = "enc:v2:"
_EPOCH_UTC = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)


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
MAX_TENANTS = _parse_env_int("PP_SYNC_MAX_TENANTS", 64, minimum=1, maximum=100000)
AUTH_FAIL_WINDOW_SEC = _parse_env_int("PP_SYNC_AUTH_FAIL_WINDOW_SEC", 60, minimum=1, maximum=86400)
AUTH_FAIL_MAX = _parse_env_int("PP_SYNC_AUTH_FAIL_MAX", 20, minimum=1, maximum=10000)
CORS_ORIGIN = os.environ.get("PP_SYNC_CORS_ORIGIN", "").strip()
GITHUB_RELEASE_REPO = os.environ.get("PP_SYNC_GITHUB_REPO", "qilaidev/PromptPanel").strip() or "qilaidev/PromptPanel"
UPDATE_CACHE_TTL_SEC = _parse_env_int("PP_SYNC_UPDATE_CACHE_TTL_SEC", 300, minimum=10, maximum=86400)

_NAMESPACE_LOCKS: dict[str, threading.Lock] = {}
_GLOBAL_LOCK = threading.Lock()
_AUTH_RATE_LOCK = threading.Lock()
_AUTH_FAIL_HISTORY: dict[str, list[float]] = {}
_TENANT_CREATE_LOCK = threading.Lock()
_RELEASE_CACHE_LOCK = threading.Lock()
_MANIFEST_REFRESH_LOCK = threading.Lock()
_ASSET_DOWNLOAD_LOCKS: dict[str, threading.Lock] = {}
_VERIFIED_ASSET_HASHES: dict[str, tuple[int, int, str]] = {}
_AESGCM_CACHE: dict[bytes, Any] = {}
_TOKEN_DERIVED_CACHE: dict[bytes, tuple[str, bytes]] = {}
_INITIALIZED_DB_PATHS: set[str] = set()
_CACHED_RELEASE_MANIFEST: dict[str, Any] | None = None
_CACHED_RELEASE_FETCHED_MONO: float = 0.0
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
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_iso_epoch_ms(value: Any) -> int | None:
    """Parse an ISO8601 timestamp (Z, +00:00, with or without fractional seconds) into UTC epoch ms."""
    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    if raw.endswith(("Z", "z")):
        raw = raw[:-1] + "+00:00"
    try:
        parsed = datetime.datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    else:
        parsed = parsed.astimezone(datetime.timezone.utc)
    delta = parsed - _EPOCH_UTC
    return (delta.days * 86400 + delta.seconds) * 1000 + (delta.microseconds // 1000)


def _is_iso_newer(a: Any, b: Any) -> bool:
    ms_a = parse_iso_epoch_ms(a)
    ms_b = parse_iso_epoch_ms(b)
    if ms_a is not None and ms_b is not None:
        return ms_a > ms_b
    if ms_a is not None:
        return True
    if ms_b is not None:
        return False
    return str(a or "") > str(b or "")


def _is_iso_older(a: Any, b: Any) -> bool:
    ms_a = parse_iso_epoch_ms(a)
    ms_b = parse_iso_epoch_ms(b)
    if ms_a is not None and ms_b is not None:
        return ms_a < ms_b
    if ms_a is None and ms_b is not None:
        return True
    if ms_a is not None and ms_b is None:
        return False
    return str(a or "") < str(b or "")


def _pick_newer_iso(a: Any, b: Any) -> str | None:
    a_str = str(a).strip() if isinstance(a, str) else ""
    b_str = str(b).strip() if isinstance(b, str) else ""
    if a_str and b_str:
        ms_a = parse_iso_epoch_ms(a_str)
        ms_b = parse_iso_epoch_ms(b_str)
        if ms_a is not None and ms_b is not None:
            return a_str if ms_a >= ms_b else b_str
        if ms_a is not None:
            return a_str
        if ms_b is not None:
            return b_str
        return a_str if a_str >= b_str else b_str
    return a_str or b_str or None


def _is_auth_rate_limited(client_ip: str) -> bool:
    now = time.monotonic()
    cutoff = now - AUTH_FAIL_WINDOW_SEC
    with _AUTH_RATE_LOCK:
        history = _AUTH_FAIL_HISTORY.get(client_ip)
        if not history:
            return False
        recent = [ts for ts in history if ts >= cutoff]
        if recent:
            _AUTH_FAIL_HISTORY[client_ip] = recent
        else:
            _AUTH_FAIL_HISTORY.pop(client_ip, None)
        return len(recent) >= AUTH_FAIL_MAX


def _record_auth_failure(client_ip: str) -> bool:
    """Record an auth failure for client_ip and return True if the burst limit is now exceeded."""
    now = time.monotonic()
    cutoff = now - AUTH_FAIL_WINDOW_SEC
    with _AUTH_RATE_LOCK:
        if len(_AUTH_FAIL_HISTORY) >= 4096:
            stale_ips = [
                ip for ip, timestamps in _AUTH_FAIL_HISTORY.items()
                if not timestamps or timestamps[-1] < cutoff
            ]
            for ip in stale_ips:
                _AUTH_FAIL_HISTORY.pop(ip, None)
            if len(_AUTH_FAIL_HISTORY) >= 4096:
                _AUTH_FAIL_HISTORY.clear()
        recent = [ts for ts in _AUTH_FAIL_HISTORY.get(client_ip, []) if ts >= cutoff]
        recent.append(now)
        _AUTH_FAIL_HISTORY[client_ip] = recent
        return len(recent) >= AUTH_FAIL_MAX


def _check_tenant_capacity(db_path: Path) -> bool:
    """Return True if db_path already exists or a new tenant DB can be created under PP_SYNC_MAX_TENANTS."""
    if ALLOWED_TOKENS or db_path.exists():
        return True
    ns_dir = DATA_DIR / "namespaces"
    with _TENANT_CREATE_LOCK:
        if db_path.exists():
            return True
        if not ns_dir.exists():
            return True
        existing_count = sum(1 for _ in ns_dir.glob("*.db"))
        return existing_count < MAX_TENANTS


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


def _get_aesgcm(aead_key: bytes) -> Any:
    cipher = _AESGCM_CACHE.get(aead_key)
    if cipher is None:
        with _GLOBAL_LOCK:
            cipher = _AESGCM_CACHE.get(aead_key)
            if cipher is None:
                if len(_AESGCM_CACHE) >= 256:
                    _AESGCM_CACHE.clear()
                cipher = AESGCM(aead_key)
                _AESGCM_CACHE[aead_key] = cipher
    return cipher


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

    token_bytes = token.encode("utf-8")
    if ALLOWED_TOKENS:
        matched = any(hmac.compare_digest(token_bytes, allowed.encode("utf-8")) for allowed in ALLOWED_TOKENS)
        if not matched:
            return False, None, None, "Invalid or unauthorized Bearer token"

    cache_key = hashlib.sha256(token_bytes).digest()
    with _GLOBAL_LOCK:
        cached = _TOKEN_DERIVED_CACHE.get(cache_key)
    if cached is not None:
        return True, cached[0], cached[1], None

    digest = hashlib.sha256(f"promptpanel-v2:{token}".encode("utf-8")).hexdigest()[:32]
    aead_key = derive_aead_key(token)
    with _GLOBAL_LOCK:
        if len(_TOKEN_DERIVED_CACHE) >= 256:
            _TOKEN_DERIVED_CACHE.clear()
        _TOKEN_DERIVED_CACHE[cache_key] = (digest, aead_key)
    return True, digest, aead_key, None


def encrypt_db_record(obj: dict[str, Any], aead_key: bytes | None, kind: str, record_id: str) -> str:
    raw_str = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    if aead_key is None or AESGCM is None:
        return raw_str
    nonce = os.urandom(12)
    aad = f"kv:{kind}:{record_id}".encode("utf-8")
    ct_and_tag = _get_aesgcm(aead_key).encrypt(nonce, raw_str.encode("utf-8"), aad)
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
        plain_bytes = _get_aesgcm(aead_key).decrypt(nonce, ct_and_tag, aad)
        return json.loads(plain_bytes.decode("utf-8")), True
    return json.loads(raw_payload), False


def encrypt_wire_envelope(envelope: dict[str, Any], aead_key: bytes) -> dict[str, Any]:
    """Compress with Gzip and encrypt with AES-256-GCM (12B nonce + ciphertext + 16B tag)."""
    if AESGCM is None:
        return envelope
    raw_json = json.dumps(envelope, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressed = gzip.compress(raw_json, compresslevel=6)
    nonce = os.urandom(12)
    ct_and_tag = _get_aesgcm(aead_key).encrypt(nonce, compressed, WIRE_AAD_V2)
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
        decrypted = _get_aesgcm(aead_key).decrypt(nonce, ct_and_tag, WIRE_AAD_V2)
    except Exception as exc:
        raise ValueError("AES-256-GCM authentication tag verification failed") from exc

    if cipher_name == "aes-256-gcm+gzip" or decrypted[:2] == b"\x1f\x8b":
        try:
            with gzip.GzipFile(fileobj=io.BytesIO(decrypted)) as gz_file:
                decompressed = gz_file.read(MAX_BODY_BYTES + 1)
        except Exception as exc:
            raise ValueError(f"Invalid gzip stream inside encrypted envelope: {exc}") from exc
        if len(decompressed) > MAX_BODY_BYTES:
            raise ValueError(f"Decompressed encrypted payload exceeds max {MAX_BODY_BYTES} bytes")
        decrypted = decompressed

    try:
        parsed = json.loads(decrypted.decode("utf-8"))
    except Exception as exc:
        raise ValueError(f"Invalid JSON inside encrypted envelope: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Decrypted sync envelope root must be a JSON object")
    return parsed, True


def init_namespace_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db_key = str(db_path.resolve())
    existed_on_disk = db_path.exists()
    conn = sqlite3.connect(str(db_path), timeout=15.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=15000;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA temp_store=MEMORY;")

    with _GLOBAL_LOCK:
        already_initialized = existed_on_disk and (db_key in _INITIALIZED_DB_PATHS)

    if not already_initialized:
        conn.execute("PRAGMA journal_mode=WAL;")
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
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        row = conn.execute("SELECT value FROM meta WHERE key = 'sync_revision'").fetchone()
        if row is None:
            has_records = conn.execute("SELECT 1 FROM kv_records LIMIT 1").fetchone() is not None
            init_rev = "1" if has_records else "0"
            with conn:
                conn.execute(
                    "INSERT OR IGNORE INTO meta (key, value) VALUES ('sync_revision', ?)",
                    (init_rev,),
                )
        with _GLOBAL_LOCK:
            _INITIALIZED_DB_PATHS.add(db_key)
    return conn


def get_sync_revision(conn: sqlite3.Connection) -> int:
    """Read the monotonic sync_revision from meta in O(1), initializing if absent."""
    row = conn.execute("SELECT value FROM meta WHERE key = 'sync_revision'").fetchone()
    if row is not None:
        try:
            return max(0, int(row["value"]))
        except (TypeError, ValueError):
            pass
    has_records = conn.execute("SELECT 1 FROM kv_records LIMIT 1").fetchone() is not None
    init_rev = 1 if has_records else 0
    with conn:
        conn.execute(
            "INSERT OR IGNORE INTO meta (key, value) VALUES ('sync_revision', ?)",
            (str(init_rev),),
        )
    return init_rev


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
            elif kind == "version" and isinstance(obj, dict):
                obj = _normalize_version_payload(obj)
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

    rev = get_sync_revision(conn)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "revision": rev,
        "serverRevision": rev,
        "serverTime": utc_now_iso(),
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
        counts: dict[str, int] = {"project": 0, "entry": 0, "version": 0}
        for row in conn.execute("SELECT kind, COUNT(*) AS cnt FROM kv_records GROUP BY kind"):
            k = str(row["kind"])
            if k in counts:
                counts[k] = int(row["cnt"])
        return counts["project"], counts["entry"], counts["version"]
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


_ASSET_VERSION_RE = re.compile(r"PromptPanel-([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)-")


def _compute_file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _is_cached_asset_valid(target_path: Path, expected_sha: str) -> bool:
    try:
        st = target_path.stat()
    except OSError:
        return False
    if st.st_size <= 0:
        return False
    if not expected_sha:
        return True
    key = str(target_path)
    with _RELEASE_CACHE_LOCK:
        cached_meta = _VERIFIED_ASSET_HASHES.get(key)
    if cached_meta is not None and cached_meta[0] == st.st_mtime_ns and cached_meta[1] == st.st_size:
        return cached_meta[2] == expected_sha
    try:
        actual_sha = _compute_file_sha256(target_path).lower()
    except OSError:
        return False
    with _RELEASE_CACHE_LOCK:
        if len(_VERIFIED_ASSET_HASHES) >= 64:
            _VERIFIED_ASSET_HASHES.clear()
        _VERIFIED_ASSET_HASHES[key] = (st.st_mtime_ns, st.st_size, actual_sha)
    return actual_sha == expected_sha


def _get_asset_download_lock(name: str) -> threading.Lock:
    with _RELEASE_CACHE_LOCK:
        lock = _ASSET_DOWNLOAD_LOCKS.get(name)
        if lock is None:
            if len(_ASSET_DOWNLOAD_LOCKS) >= 64:
                unlocked = [k for k, v in _ASSET_DOWNLOAD_LOCKS.items() if not v.locked()]
                for k in unlocked:
                    _ASSET_DOWNLOAD_LOCKS.pop(k, None)
            lock = threading.Lock()
            _ASSET_DOWNLOAD_LOCKS[name] = lock
        return lock


def _parse_sha256sums_text(text: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for line in (text or "").splitlines():
        parts = line.strip().split()
        if len(parts) >= 2 and len(parts[0]) == 64:
            fname = parts[-1].lstrip("*./")
            mapping[fname] = parts[0].lower()
    return mapping


def _fetch_url_bytes(url: str, timeout: float = 12.0, accept: str = "*/*") -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": f"PromptPanelSync/{SERVER_VERSION}",
            "Accept": accept,
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(2 * 1024 * 1024)


def resolve_latest_release_manifest(force_refresh: bool = False) -> dict[str, Any]:
    global _CACHED_RELEASE_MANIFEST, _CACHED_RELEASE_FETCHED_MONO
    now_mono = time.monotonic()
    with _RELEASE_CACHE_LOCK:
        if (
            not force_refresh
            and _CACHED_RELEASE_MANIFEST is not None
            and (now_mono - _CACHED_RELEASE_FETCHED_MONO) < UPDATE_CACHE_TTL_SEC
        ):
            return dict(_CACHED_RELEASE_MANIFEST)

    with _MANIFEST_REFRESH_LOCK:
        now_mono = time.monotonic()
        with _RELEASE_CACHE_LOCK:
            if (
                not force_refresh
                and _CACHED_RELEASE_MANIFEST is not None
                and (now_mono - _CACHED_RELEASE_FETCHED_MONO) < UPDATE_CACHE_TTL_SEC
            ):
                return dict(_CACHED_RELEASE_MANIFEST)

        local_manifest_path = DATA_DIR / "releases" / "manifest.json"
        api_url = f"https://api.github.com/repos/{GITHUB_RELEASE_REPO}/releases/latest"
        try:
            raw_bytes = _fetch_url_bytes(api_url, timeout=10.0, accept="application/vnd.github+json")
            rel = json.loads(raw_bytes.decode("utf-8"))
            tag_name = str(rel.get("tag_name") or "").strip()
            short_ver = tag_name.lstrip("vV")
            build_num = 0
            sha_map: dict[str, str] = {}
            assets = rel.get("assets") or []

            for asset in assets:
                name = str(asset.get("name") or "")
                dl_url = str(asset.get("browser_download_url") or "")
                m = _ASSET_VERSION_RE.search(name)
                if m:
                    short_ver = m.group(1)
                    build_num = int(m.group(2))
                if name == "SHA256SUMS.txt" and dl_url:
                    try:
                        sums_text = _fetch_url_bytes(dl_url, timeout=10.0).decode("utf-8", errors="replace")
                        sha_map = _parse_sha256sums_text(sums_text)
                    except Exception:
                        pass

            macos_zip_info: dict[str, Any] | None = None
            macos_dmg_info: dict[str, Any] | None = None
            android_apk_info: dict[str, Any] | None = None

            for asset in assets:
                name = str(asset.get("name") or "")
                dl_url = str(asset.get("browser_download_url") or "")
                size_bytes = _safe_int(asset.get("size"), 0)
                if not name or not dl_url:
                    continue
                digest = str(asset.get("digest") or "")
                if digest.startswith("sha256:") and len(digest) == 71:
                    asset_sha = digest[7:].lower()
                else:
                    asset_sha = sha_map.get(name, "")

                if name.endswith("-macos.zip"):
                    macos_zip_info = {
                        "name": name,
                        "size": size_bytes,
                        "sha256": asset_sha,
                        "githubUrl": dl_url,
                        "mirrorPath": "/v1/update/download/macos.zip",
                    }
                elif name.endswith("-macos.dmg"):
                    macos_dmg_info = {
                        "name": name,
                        "size": size_bytes,
                        "sha256": asset_sha,
                        "githubUrl": dl_url,
                        "mirrorPath": "/v1/update/download/macos.dmg",
                    }
                elif name.endswith("-android.apk"):
                    android_apk_info = {
                        "name": name,
                        "size": size_bytes,
                        "sha256": asset_sha,
                        "githubUrl": dl_url,
                        "mirrorPath": "/v1/update/download/android.apk",
                    }

            manifest = {
                "repository": GITHUB_RELEASE_REPO,
                "tag": tag_name,
                "version": short_ver,
                "build": build_num,
                "publishedAt": str(rel.get("published_at") or ""),
                "releaseUrl": str(rel.get("html_url") or f"https://github.com/{GITHUB_RELEASE_REPO}/releases/latest"),
                "notes": str(rel.get("body") or "")[:4000],
                "macosZip": macos_zip_info,
                "macosDmg": macos_dmg_info,
                "androidApk": android_apk_info,
                "checkedAt": utc_now_iso(),
            }

            tmp_mf: Path | None = None
            try:
                rel_dir = DATA_DIR / "releases"
                rel_dir.mkdir(parents=True, exist_ok=True)
                tmp_mf = rel_dir / f".manifest.{uuid.uuid4().hex[:8]}.json.tmp"
                tmp_mf.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
                tmp_mf.replace(local_manifest_path)
            except OSError:
                if tmp_mf is not None:
                    try:
                        if tmp_mf.exists():
                            tmp_mf.unlink()
                    except OSError:
                        pass

            with _RELEASE_CACHE_LOCK:
                _CACHED_RELEASE_MANIFEST = manifest
                _CACHED_RELEASE_FETCHED_MONO = time.monotonic()
            return dict(manifest)
        except Exception as exc:
            with _RELEASE_CACHE_LOCK:
                if _CACHED_RELEASE_MANIFEST is not None:
                    return dict(_CACHED_RELEASE_MANIFEST)
            if local_manifest_path.exists():
                try:
                    loaded = json.loads(local_manifest_path.read_text(encoding="utf-8"))
                    if isinstance(loaded, dict) and loaded.get("version"):
                        with _RELEASE_CACHE_LOCK:
                            _CACHED_RELEASE_MANIFEST = loaded
                            _CACHED_RELEASE_FETCHED_MONO = time.monotonic()
                        return dict(loaded)
                except Exception:
                    pass
            raise RuntimeError(f"Failed to query latest release manifest: {exc}") from exc


def ensure_cached_release_asset(asset_info: dict[str, Any]) -> Path:
    name = Path(str(asset_info.get("name") or "")).name
    github_url = str(asset_info.get("githubUrl") or "")
    expected_sha = str(asset_info.get("sha256") or "").lower().strip()
    if not name or not github_url:
        raise ValueError("Incomplete release asset metadata")

    rel_dir = DATA_DIR / "releases"
    rel_dir.mkdir(parents=True, exist_ok=True)
    target_path = rel_dir / name

    if _is_cached_asset_valid(target_path, expected_sha):
        return target_path

    asset_lock = _get_asset_download_lock(name)
    with asset_lock:
        if _is_cached_asset_valid(target_path, expected_sha):
            return target_path
        if target_path.exists():
            try:
                target_path.unlink()
            except OSError:
                pass

        tmp_path = rel_dir / f".{name}.{uuid.uuid4().hex[:8]}.tmp"
        req = urllib.request.Request(
            github_url,
            headers={"User-Agent": f"PromptPanelSync/{SERVER_VERSION}"},
        )
        hasher = hashlib.sha256()
        try:
            with urllib.request.urlopen(req, timeout=60.0) as resp, tmp_path.open("wb") as out_f:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    out_f.write(chunk)
                    hasher.update(chunk)
            actual_sha = hasher.hexdigest().lower()
            if expected_sha and actual_sha != expected_sha:
                raise ValueError(f"SHA-256 mismatch for {name}: expected {expected_sha}, got {actual_sha}")
            tmp_path.replace(target_path)
            try:
                st = target_path.stat()
                with _RELEASE_CACHE_LOCK:
                    _VERIFIED_ASSET_HASHES[str(target_path)] = (st.st_mtime_ns, st.st_size, actual_sha)
            except OSError:
                pass
        except Exception:
            try:
                if tmp_path.exists():
                    tmp_path.unlink()
            except OSError:
                pass
            raise

        # Prune older cached binaries of the same suffix to keep disk bounded
        suffix_key = "-android.apk" if name.endswith("-android.apk") else (
            "-macos.zip" if name.endswith("-macos.zip") else (
                "-macos.dmg" if name.endswith("-macos.dmg") else ""
            )
        )
        if suffix_key:
            for old_file in rel_dir.glob(f"*{suffix_key}"):
                if old_file.name != name:
                    try:
                        old_file.unlink()
                    except OSError:
                        pass

    return target_path


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
        if val is None or isinstance(val, bool):
            return default
        return int(val)
    except (TypeError, ValueError):
        return default


def _safe_bool(val: Any, default: bool = False) -> bool:
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return bool(val)
    if isinstance(val, str):
        lowered = val.strip().lower()
        if lowered in ("true", "1", "yes"):
            return True
        if lowered in ("false", "0", "no", ""):
            return False
    return default


def _normalize_tags(raw_tags: Any) -> list[str]:
    if isinstance(raw_tags, list):
        return [str(t) for t in raw_tags if t is not None and str(t) != ""]
    if isinstance(raw_tags, str):
        return [t.strip() for t in re.split(r"[\s,，、]+", raw_tags) if t.strip()]
    return []


def _bump_iso_timestamp(reference_iso: str) -> str:
    now_ms = parse_iso_epoch_ms(utc_now_iso()) or 0
    ref_ms = parse_iso_epoch_ms(reference_iso)
    base_ms = max(now_ms, ref_ms) if ref_ms is not None else now_ms
    bumped_dt = datetime.datetime.fromtimestamp((base_ms + 2000) / 1000.0, tz=datetime.timezone.utc)
    return bumped_dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _prefer_camel_side(record: dict[str, Any]) -> bool:
    camel_u = str(record.get("updatedAt") or "")
    snake_u = str(record.get("updated_at") or "")
    if camel_u and snake_u:
        ms_c = parse_iso_epoch_ms(camel_u)
        ms_s = parse_iso_epoch_ms(snake_u)
        if ms_c is not None and ms_s is not None:
            return ms_c >= ms_s
        if ms_c is not None:
            return True
        if ms_s is not None:
            return False
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
    resolved_updated = _pick_newer_iso(camel_u, snake_u) or utc_now_iso()
    resolved_created = str(_pick_pair(proj, "createdAt", "created_at", prefer_camel) or resolved_updated)
    is_def = _safe_bool(_pick_pair(proj, "isDefault", "is_default", prefer_camel, False), False)
    if prefer_camel:
        kind_raw = str(
            proj.get("groupKindRaw")
            or proj.get("groupKind")
            or proj.get("group_kind")
            or ("category" if is_def else "project")
        )
    else:
        kind_raw = str(
            proj.get("group_kind")
            or proj.get("groupKindRaw")
            or proj.get("groupKind")
            or ("category" if is_def else "project")
        )
    if kind_raw == "inbox":
        kind_raw = "builtin-inbox"
    is_arch = _safe_bool(_pick_pair(proj, "isArchived", "is_archived", prefer_camel, False), False)
    icon_raw = _pick_pair(proj, "iconName", "icon_name", prefer_camel, allow_none=True)
    icon_val = str(icon_raw) if icon_raw is not None else None
    deleted_raw = _pick_pair(proj, "deletedAt", "deleted_at", prefer_camel, allow_none=True)
    deleted_val = str(deleted_raw) if (deleted_raw is not None and str(deleted_raw).strip() != "") else None
    sort_val = _safe_int(_pick_pair(proj, "sortOrder", "sort_order", prefer_camel, 0), 0)

    proj["name"] = str(proj.get("name") or "")
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
    resolved_updated = _pick_newer_iso(camel_u, snake_u) or utc_now_iso()
    resolved_created = str(_pick_pair(entry, "createdAt", "created_at", prefer_camel) or resolved_updated)
    proj_id = str(_pick_pair(entry, "projectId", "project_id", prefer_camel, "") or "")
    is_pin = _safe_bool(_pick_pair(entry, "isPinned", "is_pinned", prefer_camel, False), False)
    is_comp = _safe_bool(_pick_pair(entry, "isCompleted", "is_completed", prefer_camel, False), False)
    sort_val = _safe_int(_pick_pair(entry, "sortOrder", "sort_order", prefer_camel, 0), 0)
    use_c = max(
        _safe_int(entry.get("useCount"), 0),
        _safe_int(entry.get("use_count"), 0),
    )
    lu_c = entry.get("lastUsedAt")
    lu_s = entry.get("last_used_at")
    last_used = _pick_newer_iso(lu_c, lu_s)
    deleted_raw = _pick_pair(entry, "deletedAt", "deleted_at", prefer_camel, allow_none=True)
    deleted_val = str(deleted_raw) if (deleted_raw is not None and str(deleted_raw).strip() != "") else None
    src_raw = _pick_pair(entry, "sourceEntryId", "source_entry_id", prefer_camel, allow_none=True)
    src_val = str(src_raw) if (src_raw is not None and str(src_raw).strip() != "") else None

    entry["title"] = str(entry.get("title") or "")
    entry["content"] = str(entry.get("content") or "")
    entry["tags"] = _normalize_tags(entry.get("tags"))
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


def _normalize_version_payload(raw_ver: dict[str, Any]) -> dict[str, Any]:
    ver = dict(raw_ver)
    eid_val = str(_get_field(ver, "entryId", "entry_id") or "")
    vnum_val = _safe_int(_get_field(ver, "versionNumber", "version_number", 1), default=1)
    note_val = _get_field(ver, "changeNote", "change_note")
    v_created = str(_get_field(ver, "createdAt", "created_at") or utc_now_iso())
    ver["title"] = str(ver.get("title") or "")
    ver["content"] = str(ver.get("content") or "")
    ver["entryId"] = eid_val
    ver["entry_id"] = eid_val
    ver["versionNumber"] = vnum_val
    ver["version_number"] = vnum_val
    if note_val is not None:
        note_str = str(note_val)
        ver["changeNote"] = note_str
        ver["change_note"] = note_str
    else:
        ver["changeNote"] = None
        ver["change_note"] = None
    ver["createdAt"] = v_created
    ver["created_at"] = v_created
    return ver


def merge_envelope_into_db(
    conn: sqlite3.Connection,
    incoming: dict[str, Any],
    aead_key: bytes | None = None,
    db_path: Path | None = None,
    namespace: str | None = None,
) -> tuple[dict[str, int], dict[str, Any]]:
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
        "orphansMigrated": 0,
    }
    remote_device = str(_get_field(incoming, "deviceId", "device_id") or "remote-client")
    allow_mass_delete = _safe_bool(
        _get_field(incoming, "allowMassDelete", "allow_mass_delete", False),
        False,
    ) or _safe_bool(
        _get_field(incoming, "massDeleteConfirmed", "mass_delete_confirmed", False),
        False,
    )
    force_overwrite = _safe_bool(
        _get_field(incoming, "forceOverwrite", "force_overwrite", False),
        False,
    )

    # Single-pass load of existing records to avoid repeated SQLite scans & AES-GCM decryptions
    srv_projects: dict[str, tuple[str, dict[str, Any]]] = {}
    srv_entries: dict[str, tuple[str, dict[str, Any]]] = {}
    existing_versions_by_entry: dict[str, list[dict[str, Any]]] = {}
    existing_version_ids: set[str] = set()
    legacy_rows_to_upgrade: list[tuple[str, str, dict[str, Any]]] = []
    existing_default_id: str | None = None

    for row in conn.execute("SELECT kind, id, updated_at, payload_json FROM kv_records"):
        kind = str(row["kind"])
        rec_id = str(row["id"])
        upd_str = str(row["updated_at"])
        obj, was_encrypted = decrypt_db_record(row["payload_json"], aead_key, kind, rec_id)
        if not isinstance(obj, dict):
            continue
        if kind == "project":
            norm_p = _normalize_project_payload(obj)
            srv_projects[rec_id] = (upd_str, norm_p)
            if existing_default_id is None and bool(norm_p.get("isDefault", False)):
                existing_default_id = rec_id
            if not was_encrypted and aead_key is not None and AESGCM is not None:
                legacy_rows_to_upgrade.append((kind, rec_id, norm_p))
        elif kind == "entry":
            norm_e = _normalize_entry_payload(obj)
            srv_entries[rec_id] = (upd_str, norm_e)
            if not was_encrypted and aead_key is not None and AESGCM is not None:
                legacy_rows_to_upgrade.append((kind, rec_id, norm_e))
        elif kind == "version":
            norm_v = _normalize_version_payload(obj)
            eid = str(norm_v.get("entryId") or "")
            existing_versions_by_entry.setdefault(eid, []).append(norm_v)
            existing_version_ids.add(rec_id)
            if not was_encrypted and aead_key is not None and AESGCM is not None:
                legacy_rows_to_upgrade.append((kind, rec_id, norm_v))

    # Pre-flight inspection for mass-tombstone circuit breaker & pre-drop guard backup
    # Completed todos are excluded from the breaker so clearing completed todos never resurrects them.
    srv_active_entries: dict[str, tuple[str, dict[str, Any]]] = {
        eid_str: (upd_str, e_obj)
        for eid_str, (upd_str, e_obj) in srv_entries.items()
        if e_obj.get("deletedAt") is None and not bool(e_obj.get("isCompleted", False))
    }

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
            if (
                norm_inc.get("deletedAt") is not None
                and not bool(norm_inc.get("isCompleted", False))
                and _is_iso_newer(inc_upd, srv_upd)
            ):
                incoming_deleting_count += 1

    should_block_mass_delete = False
    if not allow_mass_delete:
        if (
            incoming_deleting_count >= MASS_DELETE_MIN_COUNT
            and (incoming_deleting_count / max(srv_active_count, 1)) >= MASS_DELETE_RATIO_THRESHOLD
        ) or (srv_active_count >= 2 and incoming_deleting_count == srv_active_count):
            should_block_mass_delete = True

    if (should_block_mass_delete or incoming_deleting_count > 0 or force_overwrite) and db_path is not None and namespace is not None:
        try:
            rotate_namespace_backup(db_path, namespace, is_guard=True)
        except Exception:
            pass

    db_mutated = False
    updated_record_keys: set[tuple[str, str]] = set()

    with conn:
        remapped_project_ids: dict[str, str] = {}

        if force_overwrite:
            inc_proj_ids: set[str] = set()
            for proj in incoming.get("projects") or []:
                if not isinstance(proj, dict) or not proj.get("id"):
                    continue
                proj = _normalize_project_payload(proj)
                pid = str(proj["id"])
                is_default_proj = bool(proj.get("isDefault", False))
                proj_kind = str(proj.get("groupKindRaw") or "")
                inc_updated = str(proj.get("updatedAt") or "")
                if (is_default_proj or proj_kind == "builtin-inbox") and proj.get("deletedAt") is not None:
                    proj["deletedAt"] = None
                    proj["deleted_at"] = None
                inc_proj_ids.add(pid)
                existing_proj_pair = srv_projects.get(pid)
                if existing_proj_pair is None:
                    conn.execute(
                        "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('project', ?, ?, ?)",
                        (pid, inc_updated, encrypt_db_record(proj, aead_key, "project", pid)),
                    )
                    if proj.get("deletedAt") is None:
                        stats["projectsCreated"] += 1
                else:
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                        (inc_updated, encrypt_db_record(proj, aead_key, "project", pid), pid),
                    )
                    stats["projectsUpdated"] += 1
                srv_projects[pid] = (inc_updated, proj)
                updated_record_keys.add(("project", pid))
                db_mutated = True

            now_iso = utc_now_iso()
            for pid, (_, srv_proj) in list(srv_projects.items()):
                if pid in inc_proj_ids:
                    continue
                srv_kind = str(srv_proj.get("groupKindRaw") or srv_proj.get("group_kind") or "")
                is_system_protected = (srv_kind == "builtin-inbox") or bool(srv_proj.get("isDefault", False))
                if not is_system_protected and srv_proj.get("deletedAt") is None:
                    tomb = dict(srv_proj)
                    tomb["deletedAt"] = now_iso
                    tomb["deleted_at"] = now_iso
                    tomb["updatedAt"] = now_iso
                    tomb["updated_at"] = now_iso
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                        (now_iso, encrypt_db_record(tomb, aead_key, "project", pid), pid),
                    )
                    srv_projects[pid] = (now_iso, tomb)
                    updated_record_keys.add(("project", pid))
                    db_mutated = True

            inc_entry_ids: set[str] = set()
            for entry in incoming.get("entries") or []:
                if not isinstance(entry, dict) or not entry.get("id"):
                    continue
                entry = _normalize_entry_payload(entry)
                eid = str(entry["id"])
                inc_updated = str(entry.get("updatedAt") or "")
                inc_entry_ids.add(eid)
                if eid not in srv_entries:
                    conn.execute(
                        "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('entry', ?, ?, ?)",
                        (eid, inc_updated, encrypt_db_record(entry, aead_key, "entry", eid)),
                    )
                    if entry.get("deletedAt") is None:
                        stats["entriesCreated"] += 1
                else:
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                        (inc_updated, encrypt_db_record(entry, aead_key, "entry", eid), eid),
                    )
                    stats["entriesUpdated"] += 1
                srv_entries[eid] = (inc_updated, entry)
                updated_record_keys.add(("entry", eid))
                db_mutated = True

            for eid, (_, srv_entry) in list(srv_entries.items()):
                if eid in inc_entry_ids:
                    continue
                if srv_entry.get("deletedAt") is None:
                    tomb = dict(srv_entry)
                    tomb["deletedAt"] = now_iso
                    tomb["deleted_at"] = now_iso
                    tomb["updatedAt"] = now_iso
                    tomb["updated_at"] = now_iso
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                        (now_iso, encrypt_db_record(tomb, aead_key, "entry", eid), eid),
                    )
                    srv_entries[eid] = (now_iso, tomb)
                    updated_record_keys.add(("entry", eid))
                    db_mutated = True

            for ver in incoming.get("versions") or []:
                if not isinstance(ver, dict) or not ver.get("id"):
                    continue
                vid_str = str(ver["id"])
                if vid_str in existing_version_ids:
                    continue
                norm_v = _normalize_version_payload(ver)
                norm_v["id"] = vid_str
                conn.execute(
                    "INSERT OR IGNORE INTO kv_records (kind, id, updated_at, payload_json) VALUES ('version', ?, ?, ?)",
                    (vid_str, norm_v["createdAt"], encrypt_db_record(norm_v, aead_key, "version", vid_str)),
                )
                existing_versions_by_entry.setdefault(norm_v["entryId"], []).append(norm_v)
                existing_version_ids.add(vid_str)
                updated_record_keys.add(("version", vid_str))
                db_mutated = True
        else:
            # 1. Merge Projects
            for proj in incoming.get("projects") or []:
                if not isinstance(proj, dict) or not proj.get("id"):
                    continue
                proj = _normalize_project_payload(proj)
                pid = str(proj["id"])
                is_default_proj = bool(proj.get("isDefault", False))
                proj_kind = str(proj.get("groupKindRaw") or "")
                inc_updated = str(proj.get("updatedAt") or "")
                existing_proj_pair = srv_projects.get(pid)
                if existing_proj_pair is None:
                    if is_default_proj and existing_default_id and existing_default_id != pid:
                        remapped_project_ids[pid] = existing_default_id
                        continue
                    if is_default_proj and existing_default_id is None:
                        existing_default_id = pid
                    if (is_default_proj or proj_kind == "builtin-inbox") and proj.get("deletedAt") is not None:
                        proj["deletedAt"] = None
                        proj["deleted_at"] = None
                    conn.execute(
                        "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('project', ?, ?, ?)",
                        (pid, inc_updated, encrypt_db_record(proj, aead_key, "project", pid)),
                    )
                    srv_projects[pid] = (inc_updated, proj)
                    updated_record_keys.add(("project", pid))
                    db_mutated = True
                    if _get_field(proj, "deletedAt", "deleted_at") is None:
                        stats["projectsCreated"] += 1
                elif _is_iso_newer(inc_updated, existing_proj_pair[0]):
                    srv_proj = existing_proj_pair[1]
                    srv_deleted = _get_field(srv_proj, "deletedAt", "deleted_at")
                    inc_deleted = _get_field(proj, "deletedAt", "deleted_at")
                    srv_kind = str(srv_proj.get("groupKindRaw") or srv_proj.get("group_kind") or "")
                    is_system_protected = (srv_kind == "builtin-inbox") or bool(srv_proj.get("isDefault", False))
                    if srv_deleted is None and inc_deleted is not None and (is_system_protected or should_block_mass_delete):
                        healed_proj = dict(srv_proj)
                        healed_proj["deletedAt"] = None
                        healed_proj["deleted_at"] = None
                        healed_upd = _bump_iso_timestamp(inc_updated)
                        healed_proj["updated_at"] = healed_upd
                        healed_proj["updatedAt"] = healed_upd
                        conn.execute(
                            "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                            (healed_upd, encrypt_db_record(healed_proj, aead_key, "project", pid), pid),
                        )
                        srv_projects[pid] = (healed_upd, healed_proj)
                        updated_record_keys.add(("project", pid))
                        db_mutated = True
                        stats["protectedProjects"] += 1
                        continue
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                        (inc_updated, encrypt_db_record(proj, aead_key, "project", pid), pid),
                    )
                    srv_projects[pid] = (inc_updated, proj)
                    updated_record_keys.add(("project", pid))
                    db_mutated = True
                    stats["projectsUpdated"] += 1

            def insert_version_obj(v_obj: dict[str, Any]) -> None:
                nonlocal db_mutated
                vid = str(v_obj.get("id") or uuid.uuid4())
                v_obj["id"] = vid
                norm_v = _normalize_version_payload(v_obj)
                eid_val = norm_v["entryId"]
                v_created = norm_v["createdAt"]
                cur = conn.execute(
                    "INSERT OR IGNORE INTO kv_records (kind, id, updated_at, payload_json) VALUES ('version', ?, ?, ?)",
                    (vid, v_created, encrypt_db_record(norm_v, aead_key, "version", vid)),
                )
                if cur.rowcount > 0:
                    db_mutated = True
                    updated_record_keys.add(("version", vid))
                if vid not in existing_version_ids:
                    existing_versions_by_entry.setdefault(eid_val, []).append(norm_v)
                    existing_version_ids.add(vid)

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
                existing_entry_pair = srv_entries.get(eid)

                if existing_entry_pair is None:
                    conn.execute(
                        "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('entry', ?, ?, ?)",
                        (eid, inc_updated, encrypt_db_record(entry, aead_key, "entry", eid)),
                    )
                    srv_entries[eid] = (inc_updated, entry)
                    updated_record_keys.add(("entry", eid))
                    db_mutated = True
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
                    srv_updated, server_entry = existing_entry_pair
                    has_diff = (
                        server_entry.get("content") != entry.get("content")
                        or server_entry.get("title") != entry.get("title")
                    )

                    if _is_iso_newer(inc_updated, srv_updated):
                        srv_deleted = _get_field(server_entry, "deletedAt", "deleted_at")
                        inc_deleted = _get_field(entry, "deletedAt", "deleted_at")
                        is_incoming_deletion = srv_deleted is None and inc_deleted is not None
                        is_completed_todo = bool(server_entry.get("isCompleted", False)) or bool(entry.get("isCompleted", False))

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
                        merged_used = _pick_newer_iso(srv_used, inc_used)

                        if is_incoming_deletion and should_block_mass_delete and not is_completed_todo:
                            healed_entry = dict(server_entry)
                            healed_entry["deletedAt"] = None
                            healed_entry["deleted_at"] = None
                            healed_upd = _bump_iso_timestamp(inc_updated)
                            healed_entry["updated_at"] = healed_upd
                            healed_entry["updatedAt"] = healed_upd
                            healed_entry["use_count"] = merged_use_count
                            healed_entry["useCount"] = merged_use_count
                            if merged_used is not None:
                                healed_entry["last_used_at"] = merged_used
                                healed_entry["lastUsedAt"] = merged_used
                            conn.execute(
                                "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                                (healed_upd, encrypt_db_record(healed_entry, aead_key, "entry", eid), eid),
                            )
                            srv_entries[eid] = (healed_upd, healed_entry)
                            updated_record_keys.add(("entry", eid))
                            db_mutated = True
                            stats["protectedEntries"] += 1
                            continue

                        entry["use_count"] = merged_use_count
                        entry["useCount"] = merged_use_count
                        if merged_used is not None:
                            entry["last_used_at"] = merged_used
                            entry["lastUsedAt"] = merged_used

                        conn.execute(
                            "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                            (inc_updated, encrypt_db_record(entry, aead_key, "entry", eid), eid),
                        )
                        srv_entries[eid] = (inc_updated, entry)
                        updated_record_keys.add(("entry", eid))
                        db_mutated = True
                        stats["entriesUpdated"] += 1
                    else:
                        if _is_iso_older(inc_updated, srv_updated) and has_diff:
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
                        merged_used = _pick_newer_iso(srv_used, inc_used)
                        usage_changed = (merged_use_count > srv_use_count) or (
                            merged_used is not None and _is_iso_newer(merged_used, srv_used)
                        )
                        if usage_changed:
                            updated_srv_entry = dict(server_entry)
                            updated_srv_entry["use_count"] = merged_use_count
                            updated_srv_entry["useCount"] = merged_use_count
                            if merged_used is not None:
                                updated_srv_entry["last_used_at"] = merged_used
                                updated_srv_entry["lastUsedAt"] = merged_used
                            conn.execute(
                                "UPDATE kv_records SET payload_json = ? WHERE kind = 'entry' AND id = ?",
                                (encrypt_db_record(updated_srv_entry, aead_key, "entry", eid), eid),
                            )
                            srv_entries[eid] = (srv_updated, updated_srv_entry)
                            updated_record_keys.add(("entry", eid))
                            db_mutated = True

            # 3. Reconcile active entries whose parent project is soft-deleted or missing:
            # System-protected groups are healed; non-builtin soft-deleted groups stay deleted
            # and their orphaned active entries are migrated to the active default group.
            fallback_pid: str | None = None
            for pid_cand, (_, p_cand) in srv_projects.items():
                if _get_field(p_cand, "deletedAt", "deleted_at") is None and bool(p_cand.get("isDefault", False)):
                    fallback_pid = pid_cand
                    break
            if fallback_pid is None:
                for pid_cand, (_, p_cand) in srv_projects.items():
                    if _get_field(p_cand, "deletedAt", "deleted_at") is None:
                        fallback_pid = pid_cand
                        break

            for eid_k, (e_upd, e_obj) in list(srv_entries.items()):
                if _get_field(e_obj, "deletedAt", "deleted_at") is not None:
                    continue
                pid_val = str(_get_field(e_obj, "projectId", "project_id") or "")
                proj_pair = srv_projects.get(pid_val) if pid_val else None
                if proj_pair is not None:
                    p_upd, p_obj = proj_pair
                    if _get_field(p_obj, "deletedAt", "deleted_at") is not None:
                        p_kind = str(p_obj.get("groupKindRaw") or p_obj.get("group_kind") or "")
                        is_sys = (p_kind == "builtin-inbox") or bool(p_obj.get("isDefault", False))
                        if is_sys:
                            revived = dict(p_obj)
                            revived["deletedAt"] = None
                            revived["deleted_at"] = None
                            revived_upd = _bump_iso_timestamp(p_upd)
                            revived["updated_at"] = revived_upd
                            revived["updatedAt"] = revived_upd
                            conn.execute(
                                "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'project' AND id = ?",
                                (revived_upd, encrypt_db_record(revived, aead_key, "project", pid_val), pid_val),
                            )
                            srv_projects[pid_val] = (revived_upd, revived)
                            updated_record_keys.add(("project", pid_val))
                            db_mutated = True
                            stats["protectedProjects"] += 1
                        elif fallback_pid and fallback_pid != pid_val:
                            migrated_entry = dict(e_obj)
                            migrated_entry["projectId"] = fallback_pid
                            migrated_entry["project_id"] = fallback_pid
                            migrated_upd = _bump_iso_timestamp(e_upd)
                            migrated_entry["updatedAt"] = migrated_upd
                            migrated_entry["updated_at"] = migrated_upd
                            conn.execute(
                                "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                                (migrated_upd, encrypt_db_record(migrated_entry, aead_key, "entry", eid_k), eid_k),
                            )
                            srv_entries[eid_k] = (migrated_upd, migrated_entry)
                            updated_record_keys.add(("entry", eid_k))
                            db_mutated = True
                            stats["orphansMigrated"] += 1
                elif fallback_pid and pid_val != fallback_pid:
                    migrated_entry = dict(e_obj)
                    migrated_entry["projectId"] = fallback_pid
                    migrated_entry["project_id"] = fallback_pid
                    migrated_upd = _bump_iso_timestamp(e_upd)
                    migrated_entry["updatedAt"] = migrated_upd
                    migrated_entry["updated_at"] = migrated_upd
                    conn.execute(
                        "UPDATE kv_records SET updated_at = ?, payload_json = ? WHERE kind = 'entry' AND id = ?",
                        (migrated_upd, encrypt_db_record(migrated_entry, aead_key, "entry", eid_k), eid_k),
                    )
                    srv_entries[eid_k] = (migrated_upd, migrated_entry)
                    updated_record_keys.add(("entry", eid_k))
                    db_mutated = True
                    stats["orphansMigrated"] += 1

            # 4. Merge Explicit Incoming Versions
            for ver in incoming.get("versions") or []:
                if not isinstance(ver, dict) or not ver.get("id"):
                    continue
                vid_str = str(ver["id"])
                if vid_str in existing_version_ids:
                    continue
                norm_inc_ver = _normalize_version_payload(ver)
                eid = norm_inc_ver["entryId"]
                if not eid:
                    continue
                vnum = norm_inc_ver["versionNumber"]
                vers = existing_versions_by_entry.get(eid, [])
                if any(v.get("id") == vid_str for v in vers):
                    continue
                has_num_collision = any(_safe_int(_get_field(v, "versionNumber", "version_number", 0)) == vnum for v in vers)
                if not has_num_collision:
                    insert_version_obj(norm_inc_ver)
                else:
                    already_has_same_text = any(
                        v.get("content") == norm_inc_ver.get("content") and v.get("title") == norm_inc_ver.get("title")
                        for v in vers
                    )
                    if not already_has_same_text:
                        max_ver = max((_safe_int(_get_field(v, "versionNumber", "version_number", 0)) for v in vers), default=0)
                        renumbered = dict(norm_inc_ver)
                        renumbered["versionNumber"] = max_ver + 1
                        renumbered["version_number"] = max_ver + 1
                        insert_version_obj(renumbered)

        # Upgrade any untouched legacy plaintext rows to enc:v2
        if legacy_rows_to_upgrade and aead_key is not None:
            for kind, rec_id, obj in legacy_rows_to_upgrade:
                if (kind, rec_id) not in updated_record_keys:
                    conn.execute(
                        "UPDATE kv_records SET payload_json = ? WHERE kind = ? AND id = ?",
                        (encrypt_db_record(obj, aead_key, kind, rec_id), kind, rec_id),
                    )

        current_rev = get_sync_revision(conn)
        if db_mutated:
            current_rev += 1
            conn.execute(
                "INSERT OR REPLACE INTO meta (key, value) VALUES ('sync_revision', ?)",
                (str(current_rev),),
            )

    sorted_projects = [
        p_obj
        for _, p_obj in sorted(
            srv_projects.values(),
            key=lambda pair: (parse_iso_epoch_ms(pair[0]) or 0, str(pair[1].get("id") or "")),
        )
    ]
    sorted_entries = [
        e_obj
        for _, e_obj in sorted(
            srv_entries.values(),
            key=lambda pair: (parse_iso_epoch_ms(pair[0]) or 0, str(pair[1].get("id") or "")),
        )
    ]
    all_versions = [v for v_list in existing_versions_by_entry.values() for v in v_list]
    sorted_versions = sorted(
        all_versions,
        key=lambda v: (parse_iso_epoch_ms(v.get("createdAt")) or 0, str(v.get("id") or "")),
    )

    now_iso = utc_now_iso()
    envelope = {
        "schemaVersion": SCHEMA_VERSION,
        "revision": current_rev,
        "serverRevision": current_rev,
        "serverTime": now_iso,
        "deviceId": "promptpanel-sync-server",
        "exportedAt": now_iso,
        "projects": sorted_projects,
        "entries": sorted_entries,
        "versions": sorted_versions,
    }
    return stats, envelope


class SyncRequestHandler(BaseHTTPRequestHandler):
    server_version = f"PromptPanelSync/{SERVER_VERSION}"
    timeout = 15

    def log_message(self, fmt: str, *args: Any) -> None:
        record = {
            "timestamp": utc_now_iso(),
            "service": "promptpanel-sync-server",
            "client": self.address_string(),
            "message": fmt % args,
        }
        sys.stderr.write(json.dumps(record, ensure_ascii=False) + "\n")

    def _send_cors_headers(self) -> None:
        if CORS_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", CORS_ORIGIN)
            if CORS_ORIGIN != "*":
                self.send_header("Vary", "Origin")

    def _authenticate_sync_request(self) -> tuple[str | None, bytes | None]:
        client_ip = self.client_address[0] if self.client_address else "unknown"
        if _is_auth_rate_limited(client_ip):
            _record_metric("syncErrorsTotal")
            self._send_json(
                HTTPStatus.TOO_MANY_REQUESTS,
                {"error": "Too many authentication failures, please retry later"},
                extra_headers={"Retry-After": str(AUTH_FAIL_WINDOW_SEC)},
            )
            return None, None
        ok, namespace, aead_key, err = verify_and_derive_namespace(self.headers.get("Authorization"))
        if not ok or not namespace or aead_key is None:
            _record_metric("syncErrorsTotal")
            if _record_auth_failure(client_ip):
                self._send_json(
                    HTTPStatus.TOO_MANY_REQUESTS,
                    {"error": "Too many authentication failures, please retry later"},
                    extra_headers={"Retry-After": str(AUTH_FAIL_WINDOW_SEC)},
                )
            else:
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": err or "Unauthorized"})
            return None, None
        return namespace, aead_key

    def _send_json(self, status: int, payload: dict[str, Any], extra_headers: dict[str, str] | None = None) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        accept_encoding = self.headers.get("Accept-Encoding", "")
        use_gzip = "gzip" in accept_encoding and len(raw) > 1024
        body = gzip.compress(raw, compresslevel=6) if use_gzip else raw

        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-PromptPanel-Schema", str(SCHEMA_VERSION))
            self._send_cors_headers()
            if use_gzip:
                self.send_header("Content-Encoding", "gzip")
            if extra_headers:
                for k, v in extra_headers.items():
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            return

    def do_OPTIONS(self) -> None:
        try:
            self.send_response(HTTPStatus.NO_CONTENT)
            self.send_header("Content-Length", "0")
            self.send_header("Allow", "GET, POST, OPTIONS")
            if CORS_ORIGIN:
                self._send_cors_headers()
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header(
                    "Access-Control-Allow-Headers",
                    "Authorization, Content-Type, Content-Encoding, If-Match, X-PromptPanel-Cipher",
                )
                self.send_header("Access-Control-Expose-Headers", "ETag, X-PromptPanel-Revision")
                self.send_header("Access-Control-Max-Age", "86400")
            self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            return

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

        if path in ("/update", "/v1/update"):
            qs = parse_qs(parsed.query)
            force_flag = qs.get("force", ["0"])[0] in ("1", "true", "yes")
            try:
                manifest = resolve_latest_release_manifest(force_refresh=force_flag)
                self._send_json(HTTPStatus.OK, manifest)
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_GATEWAY, {"error": str(exc)})
            return

        if path in (
            "/download/android",
            "/v1/update/download/android.apk",
            "/download/macos",
            "/v1/update/download/macos.zip",
            "/download/dmg",
            "/v1/update/download/macos.dmg",
        ):
            try:
                manifest = resolve_latest_release_manifest(force_refresh=False)
                if path in ("/download/android", "/v1/update/download/android.apk"):
                    asset_info = manifest.get("androidApk")
                    content_type = "application/vnd.android.package-archive"
                elif path in ("/download/dmg", "/v1/update/download/macos.dmg"):
                    asset_info = manifest.get("macosDmg")
                    content_type = "application/x-apple-diskimage"
                else:
                    asset_info = manifest.get("macosZip")
                    content_type = "application/zip"

                if not isinstance(asset_info, dict) or not asset_info.get("name"):
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": "Requested platform release asset not found"})
                    return

                cached_file = ensure_cached_release_asset(asset_info)
                file_size = cached_file.stat().st_size
                safe_filename = Path(str(asset_info["name"])).name

                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(file_size))
                self.send_header("Content-Disposition", f'attachment; filename="{safe_filename}"')
                if asset_info.get("sha256"):
                    self.send_header("X-PromptPanel-SHA256", str(asset_info["sha256"]))
                self.end_headers()
                with cached_file.open("rb") as f:
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception as exc:
                self._send_json(HTTPStatus.BAD_GATEWAY, {"error": f"Release asset download failed: {exc}"})
            return

        if path not in ("/", "/sync", "/v1/sync", "/v1/promptpanel"):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        namespace, aead_key = self._authenticate_sync_request()
        if not namespace or aead_key is None:
            return

        qs = parse_qs(parsed.query)
        since_rev_raw = qs.get("since_revision", [None])[0]
        since_rev: int | None = None
        if since_rev_raw is not None and since_rev_raw.strip() != "":
            try:
                since_rev = int(since_rev_raw.strip())
            except ValueError:
                since_rev = None

        _record_metric("syncGetTotal")
        lock = get_namespace_lock(namespace)
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            if not _check_tenant_capacity(db_path):
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.FORBIDDEN, {"error": "Tenant capacity limit reached"})
                return
            conn = init_namespace_db(db_path)
            try:
                current_rev = get_sync_revision(conn)
                if since_rev is not None and since_rev == current_rev:
                    now_iso = utc_now_iso()
                    envelope = {
                        "schemaVersion": SCHEMA_VERSION,
                        "unchanged": True,
                        "revision": current_rev,
                        "serverRevision": current_rev,
                        "serverTime": now_iso,
                        "generatedAt": now_iso,
                        "projects": [],
                        "entries": [],
                        "versions": [],
                    }
                else:
                    envelope = load_envelope_from_db(conn, aead_key=aead_key)
                    current_rev = int(envelope.get("revision", current_rev))
            except Exception as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Decryption or database error: {exc}"})
                return
            finally:
                conn.close()

        wants_wire_cipher = "aes-256-gcm" in self.headers.get("X-PromptPanel-Cipher", "").lower()
        response_payload = encrypt_wire_envelope(envelope, aead_key) if wants_wire_cipher else envelope
        extra_hdrs = {
            "X-PromptPanel-Namespace": namespace[:12],
            "X-PromptPanel-Revision": str(current_rev),
            "ETag": f'"rev-{current_rev}"',
        }
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

        namespace, aead_key = self._authenticate_sync_request()
        if not namespace or aead_key is None:
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

        try:
            raw_body = self.rfile.read(content_length)
        except OSError as exc:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Failed to read request body: {exc}"})
            return

        if len(raw_body) != content_length:
            _record_metric("syncErrorsTotal")
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Truncated request body"})
            return

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

        raw_expected_rev = _get_field(incoming, "expectedRevision", "expected_revision")
        if raw_expected_rev is None:
            if_match_hdr = (self.headers.get("If-Match") or "").strip()
            if if_match_hdr and if_match_hdr != "*":
                cleaned_etag = if_match_hdr.strip('"').strip("'")
                if cleaned_etag.startswith("rev-"):
                    cleaned_etag = cleaned_etag[4:]
                raw_expected_rev = cleaned_etag
        expected_revision: int | None = None
        if raw_expected_rev is not None and str(raw_expected_rev).strip() != "":
            try:
                expected_revision = int(str(raw_expected_rev).strip())
            except ValueError:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid expectedRevision / If-Match revision"})
                return

        strict_conflict = _safe_bool(_get_field(incoming, "strictConflict", "strict_conflict", False), False)
        force_overwrite = _safe_bool(_get_field(incoming, "forceOverwrite", "force_overwrite", False), False)
        wants_wire_cipher = was_wire_encrypted or ("aes-256-gcm" in self.headers.get("X-PromptPanel-Cipher", "").lower())

        _record_metric("syncPostTotal")
        lock = get_namespace_lock(namespace)
        conflict_envelope: dict[str, Any] | None = None
        rebased = False
        with lock:
            db_path = DATA_DIR / "namespaces" / f"{namespace}.db"
            if not _check_tenant_capacity(db_path):
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.FORBIDDEN, {"error": "Tenant capacity limit reached"})
                return
            conn = init_namespace_db(db_path)
            try:
                pre_rev = get_sync_revision(conn)
                if (
                    strict_conflict
                    and not force_overwrite
                    and expected_revision is not None
                    and expected_revision != pre_rev
                ):
                    conflict_envelope = load_envelope_from_db(conn, aead_key=aead_key)
                    conflict_envelope["conflict"] = True
                    conflict_envelope["expectedRevision"] = expected_revision
                    conflict_envelope["serverRevision"] = pre_rev
                    conflict_envelope["serverTime"] = utc_now_iso()
                    conflict_envelope["error"] = (
                        f"Revision conflict: expected {expected_revision}, server is at {pre_rev}"
                    )
                else:
                    if expected_revision is not None and expected_revision != pre_rev:
                        rebased = True
                    stats, merged_envelope = merge_envelope_into_db(
                        conn,
                        incoming,
                        aead_key=aead_key,
                        db_path=db_path,
                        namespace=namespace,
                    )
                    if rebased:
                        merged_envelope["rebased"] = True
            except (ValueError, TypeError) as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            except Exception as exc:
                _record_metric("syncErrorsTotal")
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Sync merge failed: {exc}"})
                return
            finally:
                conn.close()

            if conflict_envelope is not None:
                rev_str = str(conflict_envelope.get("serverRevision", 0))
                conflict_payload = (
                    encrypt_wire_envelope(conflict_envelope, aead_key)
                    if wants_wire_cipher
                    else conflict_envelope
                )
                conflict_hdrs = {
                    "X-PromptPanel-Namespace": namespace[:12],
                    "X-PromptPanel-Revision": rev_str,
                    "ETag": f'"rev-{rev_str}"',
                }
                if wants_wire_cipher and AESGCM is not None:
                    conflict_hdrs["X-PromptPanel-Cipher"] = "aes-256-gcm+gzip"
                self._send_json(
                    HTTPStatus.CONFLICT,
                    conflict_payload,
                    extra_headers=conflict_hdrs,
                )
                return

            try:
                rotate_namespace_backup(db_path, namespace)
            except Exception:
                pass

        _record_metric("conflictsPreservedTotal", stats.get("conflictsPreserved", 0))
        _record_metric(
            "massDeletionsProtectedTotal",
            stats.get("protectedEntries", 0) + stats.get("protectedProjects", 0),
        )
        new_rev = int(merged_envelope.get("revision", 0))
        response_payload = encrypt_wire_envelope(merged_envelope, aead_key) if wants_wire_cipher else merged_envelope
        extra_hdrs = {
            "X-PromptPanel-Namespace": namespace[:12],
            "X-PromptPanel-Revision": str(new_rev),
            "ETag": f'"rev-{new_rev}"',
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
