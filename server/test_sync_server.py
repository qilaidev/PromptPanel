#!/usr/bin/env python3
"""Automated test suite for PromptPanel Cloud Sync Server."""

from __future__ import annotations

import json
import re
import sqlite3
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any
from unittest import mock

import promptpanel_sync_server as srv


class SyncServerUnitTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self._tmp.name)
        self.orig_data_dir = srv.DATA_DIR
        srv.DATA_DIR = self.tmp_dir
        (self.tmp_dir / "namespaces").mkdir(parents=True, exist_ok=True)
        (self.tmp_dir / "backups").mkdir(parents=True, exist_ok=True)
        with srv._GLOBAL_LOCK:
            srv._INITIALIZED_DB_PATHS.clear()

    def tearDown(self) -> None:
        srv.DATA_DIR = self.orig_data_dir
        self._tmp.cleanup()

    def test_utc_now_iso_and_parse_iso_epoch_ms(self) -> None:
        now_iso = srv.utc_now_iso()
        self.assertRegex(now_iso, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")

        ms_no_frac = srv.parse_iso_epoch_ms("2026-11-18T00:05:12Z")
        ms_zero = srv.parse_iso_epoch_ms("2026-11-18T00:05:12.000Z")
        ms_999 = srv.parse_iso_epoch_ms("2026-11-18T00:05:12.999Z")
        ms_plus00 = srv.parse_iso_epoch_ms("2026-11-18T00:05:12.999+00:00")
        ms_offset = srv.parse_iso_epoch_ms("2026-11-18T05:35:12.999+05:30")

        self.assertIsNotNone(ms_no_frac)
        self.assertEqual(ms_no_frac, ms_zero)
        self.assertEqual(ms_999, ms_no_frac + 999)
        self.assertEqual(ms_plus00, ms_999)
        self.assertEqual(ms_offset, ms_999)
        self.assertIsNone(srv.parse_iso_epoch_ms(None))
        self.assertIsNone(srv.parse_iso_epoch_ms(""))
        self.assertIsNone(srv.parse_iso_epoch_ms("not-a-timestamp"))

    def test_lww_millisecond_vs_whole_second_z(self) -> None:
        """'2026-11-18T00:05:12Z' must NEVER beat '2026-11-18T00:05:12.999Z'."""
        db_path = self.tmp_dir / "namespaces" / "lww.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-123456")
            # Server has .999Z
            srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "projects": [{"id": "p1", "name": "General", "isDefault": True, "updatedAt": "2026-11-18T00:05:12.999Z"}],
                    "entries": [
                        {
                            "id": "e1",
                            "projectId": "p1",
                            "title": "Newer .999Z",
                            "content": "Fresh content",
                            "updatedAt": "2026-11-18T00:05:12.999Z",
                        }
                    ],
                },
                aead_key=key,
            )

            # Incoming has whole-second Z (which in raw ASCII 'Z' > '.' would falsely win)
            stats, env = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "legacy-client",
                    "entries": [
                        {
                            "id": "e1",
                            "projectId": "p1",
                            "title": "Stale Z",
                            "content": "Stale content",
                            "updatedAt": "2026-11-18T00:05:12Z",
                        }
                    ],
                },
                aead_key=key,
            )
            self.assertEqual(stats["entriesUpdated"], 0)
            self.assertEqual(stats["conflictsPreserved"], 1)
            self.assertEqual(len(env["entries"]), 1)
            self.assertEqual(env["entries"][0]["title"], "Newer .999Z")
            self.assertEqual(env["entries"][0]["content"], "Fresh content")
        finally:
            conn.close()

    def test_android_copy_usage_monotonic_merge_without_clobbering_newer_text(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "usage.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-usage-1")
            srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "projects": [{"id": "p1", "name": "Work", "updatedAt": "2026-11-18T00:01:00.000Z"}],
                    "entries": [
                        {
                            "id": "e1",
                            "projectId": "p1",
                            "title": "Mac Edited Title",
                            "content": "Mac Edited Content",
                            "useCount": 3,
                            "lastUsedAt": "2026-11-18T00:02:00Z",
                            "updatedAt": "2026-11-18T00:05:00.000Z",
                        }
                    ],
                },
                aead_key=key,
            )

            # Android copied an older version of the entry (older updatedAt, higher useCount, newer lastUsedAt)
            stats, env = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "android",
                    "entries": [
                        {
                            "id": "e1",
                            "projectId": "p1",
                            "title": "Old Android Title",
                            "content": "Old Android Content",
                            "useCount": 5,
                            "lastUsedAt": "2026-11-18T00:06:00.500Z",
                            "updatedAt": "2026-11-18T00:01:00.000Z",
                        }
                    ],
                },
                aead_key=key,
            )
            entry = env["entries"][0]
            self.assertEqual(entry["title"], "Mac Edited Title")
            self.assertEqual(entry["content"], "Mac Edited Content")
            self.assertEqual(entry["useCount"], 5)
            self.assertEqual(entry["lastUsedAt"], "2026-11-18T00:06:00.500Z")
            self.assertEqual(stats["entriesUpdated"], 0)
            self.assertGreaterEqual(env["revision"], 2)
        finally:
            conn.close()

    def test_null_field_sanitization_and_builtin_inbox_protection(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "sanitize.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-sanitize")
            _, env = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "android",
                    "projects": [
                        {
                            "id": "inbox-1",
                            "name": None,
                            "groupKindRaw": "inbox",
                            "isDefault": None,
                            "isArchived": None,
                            "sortOrder": None,
                            "updatedAt": "2026-11-18T00:01:00.000Z",
                        },
                        {
                            "id": "def-1",
                            "name": "General",
                            "isDefault": True,
                            "updatedAt": "2026-11-18T00:01:00.000Z",
                        },
                    ],
                    "entries": [
                        {
                            "id": "e-null",
                            "projectId": "inbox-1",
                            "title": None,
                            "content": None,
                            "tags": None,
                            "isPinned": None,
                            "isCompleted": None,
                            "sortOrder": None,
                            "useCount": None,
                            "updatedAt": "2026-11-18T00:01:00.000Z",
                        },
                        {
                            "id": "e-tags",
                            "projectId": "inbox-1",
                            "title": "Tagged",
                            "content": "Body",
                            "tags": [None, "ai", 123],
                            "updatedAt": "2026-11-18T00:01:00.000Z",
                        },
                    ],
                },
                aead_key=key,
            )

            proj_map = {p["id"]: p for p in env["projects"]}
            self.assertEqual(proj_map["inbox-1"]["groupKindRaw"], "builtin-inbox")
            self.assertEqual(proj_map["inbox-1"]["name"], "")
            self.assertIs(proj_map["inbox-1"]["isDefault"], False)
            self.assertIs(proj_map["inbox-1"]["isArchived"], False)
            self.assertEqual(proj_map["inbox-1"]["sortOrder"], 0)

            entry_map = {e["id"]: e for e in env["entries"]}
            self.assertEqual(entry_map["e-null"]["title"], "")
            self.assertEqual(entry_map["e-null"]["content"], "")
            self.assertEqual(entry_map["e-null"]["tags"], [])
            self.assertIs(entry_map["e-null"]["isPinned"], False)
            self.assertIs(entry_map["e-null"]["isCompleted"], False)
            self.assertEqual(entry_map["e-null"]["sortOrder"], 0)
            self.assertEqual(entry_map["e-null"]["useCount"], 0)
            self.assertEqual(entry_map["e-tags"]["tags"], ["ai", "123"])

            # Attempt to tombstone builtin-inbox and active isDefault project
            stats, env2 = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "bad-client",
                    "allowMassDelete": True,
                    "projects": [
                        {
                            "id": "inbox-1",
                            "name": "Inbox",
                            "groupKindRaw": "builtin-inbox",
                            "updatedAt": "2026-11-18T00:02:00.000Z",
                            "deletedAt": "2026-11-18T00:02:00.000Z",
                        },
                        {
                            "id": "def-1",
                            "name": "General",
                            "isDefault": True,
                            "updatedAt": "2026-11-18T00:02:00.000Z",
                            "deletedAt": "2026-11-18T00:02:00.000Z",
                        },
                    ],
                },
                aead_key=key,
            )
            self.assertEqual(stats["protectedProjects"], 2)
            proj_map2 = {p["id"]: p for p in env2["projects"]}
            self.assertIsNone(proj_map2["inbox-1"]["deletedAt"])
            self.assertIsNone(proj_map2["def-1"]["deletedAt"])
        finally:
            conn.close()

    def test_mass_delete_breaker_allow_flag_and_completed_todos(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "massdel.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-massdel")
            # Seed 2 active prompts and 4 completed todos
            srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "projects": [{"id": "p1", "name": "Inbox", "updatedAt": "2026-11-18T00:01:00.000Z"}],
                    "entries": [
                        {"id": "prompt-1", "projectId": "p1", "title": "P1", "content": "C1", "isCompleted": False, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "prompt-2", "projectId": "p1", "title": "P2", "content": "C2", "isCompleted": False, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "todo-1", "projectId": "p1", "title": "T1", "content": "", "isCompleted": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "todo-2", "projectId": "p1", "title": "T2", "content": "", "isCompleted": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "todo-3", "projectId": "p1", "title": "T3", "content": "", "isCompleted": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "todo-4", "projectId": "p1", "title": "T4", "content": "", "isCompleted": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                    ],
                },
                aead_key=key,
            )

            # Clearing all 4 completed todos without allowMassDelete must NOT trip the circuit breaker
            stats1, env1 = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "entries": [
                        {"id": f"todo-{i}", "projectId": "p1", "title": f"T{i}", "content": "", "isCompleted": True, "updatedAt": "2026-11-18T00:02:00.000Z", "deletedAt": "2026-11-18T00:02:00.000Z"}
                        for i in range(1, 5)
                    ],
                },
                aead_key=key,
            )
            self.assertEqual(stats1["protectedEntries"], 0)
            e_map1 = {e["id"]: e for e in env1["entries"]}
            for i in range(1, 5):
                self.assertIsNotNone(e_map1[f"todo-{i}"]["deletedAt"])

            # Deleting both active prompts WITHOUT allowMassDelete MUST trip the breaker
            stats2, env2 = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "entries": [
                        {"id": "prompt-1", "projectId": "p1", "title": "P1", "content": "C1", "isCompleted": False, "updatedAt": "2026-11-18T00:03:00.000Z", "deletedAt": "2026-11-18T00:03:00.000Z"},
                        {"id": "prompt-2", "projectId": "p1", "title": "P2", "content": "C2", "isCompleted": False, "updatedAt": "2026-11-18T00:03:00.000Z", "deletedAt": "2026-11-18T00:03:00.000Z"},
                    ],
                },
                aead_key=key,
            )
            self.assertEqual(stats2["protectedEntries"], 2)

            # Deleting both active prompts WITH allowMassDelete: true MUST succeed
            e_map2 = {e["id"]: e for e in env2["entries"]}
            later_ts = srv._bump_iso_timestamp(e_map2["prompt-1"]["updatedAt"])
            stats3, env3 = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "allowMassDelete": True,
                    "entries": [
                        {"id": "prompt-1", "projectId": "p1", "title": "P1", "content": "C1", "isCompleted": False, "updatedAt": later_ts, "deletedAt": later_ts},
                        {"id": "prompt-2", "projectId": "p1", "title": "P2", "content": "C2", "isCompleted": False, "updatedAt": later_ts, "deletedAt": later_ts},
                    ],
                },
                aead_key=key,
            )
            self.assertEqual(stats3["protectedEntries"], 0)
            e_map3 = {e["id"]: e for e in env3["entries"]}
            self.assertIsNotNone(e_map3["prompt-1"]["deletedAt"])
            self.assertIsNotNone(e_map3["prompt-2"]["deletedAt"])
        finally:
            conn.close()

    def test_revision_initialization_for_legacy_db_without_meta(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "legacy.db"
        raw_conn = sqlite3.connect(str(db_path))
        raw_conn.execute(
            "CREATE TABLE kv_records (kind TEXT NOT NULL, id TEXT NOT NULL, updated_at TEXT NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY (kind, id))"
        )
        raw_conn.execute(
            "INSERT INTO kv_records (kind, id, updated_at, payload_json) VALUES ('project', 'p1', '2026-11-18T00:00:00.000Z', '{\"id\":\"p1\",\"name\":\"Legacy\",\"updatedAt\":\"2026-11-18T00:00:00.000Z\"}')"
        )
        raw_conn.commit()
        raw_conn.close()

        conn = srv.init_namespace_db(db_path)
        try:
            self.assertEqual(srv.get_sync_revision(conn), 1)
        finally:
            conn.close()

    def test_soft_deleted_project_not_revived_by_orphan_active_entry(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "orphan.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-orphan-1")
            srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac",
                    "projects": [
                        {"id": "p-default", "name": "通用项目", "isDefault": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "p-temp", "name": "临时项目", "isDefault": False, "updatedAt": "2026-11-18T00:01:00.000Z"},
                    ],
                    "entries": [],
                },
                aead_key=key,
            )

            # Device A soft-deletes p-temp at 00:05:00Z while Device B offline adds e-orphan into p-temp at 00:04:00Z
            stats, env = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "device-b",
                    "projects": [
                        {"id": "p-temp", "name": "临时项目", "isDefault": False, "updatedAt": "2026-11-18T00:05:00.000Z", "deletedAt": "2026-11-18T00:05:00.000Z"},
                    ],
                    "entries": [
                        {"id": "e-orphan", "projectId": "p-temp", "title": "孤儿词条", "content": "Body", "updatedAt": "2026-11-18T00:04:00.000Z"},
                    ],
                },
                aead_key=key,
            )
            proj_map = {p["id"]: p for p in env["projects"]}
            entry_map = {e["id"]: e for e in env["entries"]}
            self.assertIsNotNone(proj_map["p-temp"]["deletedAt"])
            self.assertEqual(entry_map["e-orphan"]["projectId"], "p-default")
            self.assertEqual(stats["orphansMigrated"], 1)
        finally:
            conn.close()

    def test_force_overwrite_replaces_cloud_state(self) -> None:
        db_path = self.tmp_dir / "namespaces" / "force.db"
        conn = srv.init_namespace_db(db_path)
        try:
            key = srv.derive_aead_key("test-token-force-1")
            srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac-a",
                    "projects": [
                        {"id": "p-def", "name": "通用项目", "isDefault": True, "updatedAt": "2026-11-18T00:01:00.000Z"},
                        {"id": "p-extra", "name": "多余分组", "updatedAt": "2026-11-18T00:01:00.000Z"},
                    ],
                    "entries": [
                        {"id": "e-keep", "projectId": "p-def", "title": "Old", "content": "OldBody", "updatedAt": "2026-11-18T00:05:00.000Z"},
                        {"id": "e-drop", "projectId": "p-extra", "title": "Drop", "content": "DropBody", "updatedAt": "2026-11-18T00:05:00.000Z"},
                    ],
                },
                aead_key=key,
            )
            _, env = srv.merge_envelope_into_db(
                conn,
                {
                    "deviceId": "mac-b",
                    "forceOverwrite": True,
                    "allowMassDelete": True,
                    "projects": [
                        {"id": "p-def", "name": "通用项目", "isDefault": True, "updatedAt": "2026-11-18T00:02:00.000Z"},
                    ],
                    "entries": [
                        {"id": "e-keep", "projectId": "p-def", "title": "Forced", "content": "ForcedBody", "updatedAt": "2026-11-18T00:02:00.000Z"},
                    ],
                },
                aead_key=key,
            )
            proj_map = {p["id"]: p for p in env["projects"]}
            entry_map = {e["id"]: e for e in env["entries"]}
            self.assertIsNotNone(proj_map["p-extra"]["deletedAt"])
            self.assertIsNotNone(entry_map["e-drop"]["deletedAt"])
            self.assertEqual(entry_map["e-keep"]["title"], "Forced")
        finally:
            conn.close()


class SyncServerHTTPTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self._tmp.name)
        self.orig_data_dir = srv.DATA_DIR
        self.orig_max_tenants = srv.MAX_TENANTS
        self.orig_auth_fail_max = srv.AUTH_FAIL_MAX
        self.orig_cors_origin = srv.CORS_ORIGIN
        self.orig_allowed = list(srv.ALLOWED_TOKENS)

        srv.DATA_DIR = self.tmp_dir
        srv.ALLOWED_TOKENS = []
        srv.MAX_TENANTS = 64
        srv.AUTH_FAIL_MAX = 20
        srv.CORS_ORIGIN = "https://app.promptpanel.local"
        (self.tmp_dir / "namespaces").mkdir(parents=True, exist_ok=True)
        (self.tmp_dir / "backups").mkdir(parents=True, exist_ok=True)
        with srv._GLOBAL_LOCK:
            srv._INITIALIZED_DB_PATHS.clear()
        with srv._AUTH_RATE_LOCK:
            srv._AUTH_FAIL_HISTORY.clear()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), srv.SyncRequestHandler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        srv.DATA_DIR = self.orig_data_dir
        srv.MAX_TENANTS = self.orig_max_tenants
        srv.AUTH_FAIL_MAX = self.orig_auth_fail_max
        srv.CORS_ORIGIN = self.orig_cors_origin
        srv.ALLOWED_TOKENS = self.orig_allowed
        self._tmp.cleanup()

    def _request(
        self,
        method: str,
        path: str,
        token: str | None = None,
        body: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], dict[str, Any] | None]:
        url = f"http://127.0.0.1:{self.port}{path}"
        req_headers = dict(headers or {})
        if token is not None:
            req_headers["Authorization"] = f"Bearer {token}"
        data: bytes | None = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            req_headers.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                raw = resp.read()
                parsed = json.loads(raw.decode("utf-8")) if raw else None
                return resp.status, dict(resp.headers.items()), parsed
        except urllib.error.HTTPError as err:
            try:
                raw = err.read()
                parsed = json.loads(raw.decode("utf-8")) if raw else None
                return err.code, dict(err.headers.items()), parsed
            finally:
                err.close()

    def test_since_revision_o1_poll_and_single_pass_post(self) -> None:
        token = "valid-sync-token-12345"
        # Initial GET on empty namespace -> revision 0
        status, _, env0 = self._request("GET", "/v1/sync", token=token)
        self.assertEqual(status, 200)
        assert env0 is not None
        self.assertEqual(env0["revision"], 0)
        self.assertEqual(env0["entries"], [])

        # Poll with since_revision=0 -> unchanged: true, ZERO kv_records decrypts
        with mock.patch.object(srv, "decrypt_db_record", wraps=srv.decrypt_db_record) as dec_spy:
            status, _, poll0 = self._request("GET", "/v1/sync?since_revision=0", token=token)
            self.assertEqual(status, 200)
            assert poll0 is not None
            self.assertTrue(poll0["unchanged"])
            self.assertEqual(poll0["revision"], 0)
            self.assertEqual(poll0["projects"], [])
            self.assertEqual(poll0["entries"], [])
            self.assertEqual(poll0["versions"], [])
            self.assertEqual(dec_spy.call_count, 0)

        # POST mutation -> single-pass (load_envelope_from_db NOT called), revision increments to 1
        with mock.patch.object(srv, "load_envelope_from_db", wraps=srv.load_envelope_from_db) as load_spy:
            status, _, post1 = self._request(
                "POST",
                "/v1/sync",
                token=token,
                body={
                    "deviceId": "mac-test",
                    "projects": [{"id": "p1", "name": "General", "isDefault": True, "updatedAt": "2026-11-18T00:10:00.000Z"}],
                    "entries": [{"id": "e1", "projectId": "p1", "title": "Hello", "content": "World", "updatedAt": "2026-11-18T00:10:00.000Z"}],
                },
            )
            self.assertEqual(status, 200)
            assert post1 is not None
            self.assertEqual(post1["revision"], 1)
            self.assertEqual(len(post1["entries"]), 1)
            self.assertEqual(load_spy.call_count, 0)

        # Poll with stale since_revision=0 -> returns full envelope at revision 1
        status, _, full1 = self._request("GET", "/v1/sync?since_revision=0", token=token)
        self.assertEqual(status, 200)
        assert full1 is not None
        self.assertNotIn("unchanged", full1)
        self.assertEqual(full1["revision"], 1)
        self.assertEqual(len(full1["entries"]), 1)

        # Poll with current since_revision=1 -> unchanged: true
        status, _, poll1 = self._request("GET", "/v1/sync?since_revision=1", token=token)
        self.assertEqual(status, 200)
        assert poll1 is not None
        self.assertTrue(poll1["unchanged"])
        self.assertEqual(poll1["revision"], 1)

    def test_hardening_timeout_cors_rate_limit_and_tenant_cap(self) -> None:
        self.assertEqual(srv.SyncRequestHandler.timeout, 15)

        # OPTIONS CORS preflight
        status, hdrs, _ = self._request("OPTIONS", "/v1/sync")
        self.assertEqual(status, 204)
        self.assertEqual(hdrs.get("Access-Control-Allow-Origin"), "https://app.promptpanel.local")
        self.assertIn("POST", hdrs.get("Access-Control-Allow-Methods", ""))

        # Tenant cap
        srv.MAX_TENANTS = 2
        s1, _, _ = self._request("GET", "/v1/sync", token="tenant-token-0001")
        s2, _, _ = self._request("GET", "/v1/sync", token="tenant-token-0002")
        s3, _, err3 = self._request("GET", "/v1/sync", token="tenant-token-0003")
        self.assertEqual(s1, 200)
        self.assertEqual(s2, 200)
        self.assertEqual(s3, 403)
        assert err3 is not None
        self.assertIn("Tenant capacity", err3["error"])

        # Auth failure rate limiting -> 429 after burst
        srv.AUTH_FAIL_MAX = 3
        c1, _, _ = self._request("GET", "/v1/sync", token="short")
        c2, _, _ = self._request("GET", "/v1/sync", token="short")
        c3, hdrs3, _ = self._request("GET", "/v1/sync", token="short")
        c4, _, _ = self._request("GET", "/v1/sync", token="short")
        self.assertEqual((c1, c2, c3, c4), (401, 401, 429, 429))
        self.assertIn("Retry-After", hdrs3)

    def test_concurrent_sync_requests_with_wire_encryption(self) -> None:
        token = "concurrent-sync-token-999"
        key = srv.derive_aead_key(token)

        def push_entry(idx: int) -> dict[str, Any]:
            envelope = {
                "deviceId": f"worker-{idx}",
                "projects": [
                    {"id": "p-shared", "name": "Shared", "isDefault": True, "updatedAt": "2026-11-18T00:00:00.000Z"}
                ],
                "entries": [
                    {
                        "id": f"entry-{idx}",
                        "projectId": "p-shared",
                        "title": f"Title {idx}",
                        "content": f"Content {idx}",
                        "updatedAt": f"2026-11-18T00:00:{idx:02d}.123Z",
                    }
                ],
            }
            wire_body = srv.encrypt_wire_envelope(envelope, key)
            status, _, resp_payload = self._request(
                "POST",
                "/v1/sync",
                token=token,
                body=wire_body,
                headers={"X-PromptPanel-Cipher": "aes-256-gcm"},
            )
            self.assertEqual(status, 200)
            assert resp_payload is not None
            decrypted, was_enc = srv.decrypt_wire_envelope(resp_payload, key)
            self.assertTrue(was_enc)
            return decrypted

        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(push_entry, range(12)))

        self.assertEqual(len(results), 12)
        status, _, final_env = self._request("GET", "/v1/sync", token=token)
        self.assertEqual(status, 200)
        assert final_env is not None
        self.assertEqual(len(final_env["entries"]), 12)
        self.assertGreaterEqual(final_env["revision"], 12)

    def test_optimistic_locking_etag_409_conflict_and_rebase(self) -> None:
        token = "optimistic-lock-token-12345"
        # Seed revision 1 from Device A
        s1, h1, env1 = self._request(
            "POST",
            "/v1/sync",
            token=token,
            body={
                "deviceId": "mac-a",
                "expectedRevision": 0,
                "strictConflict": True,
                "projects": [{"id": "p1", "name": "General", "isDefault": True, "updatedAt": "2026-11-18T00:01:00.000Z"}],
                "entries": [{"id": "e1", "projectId": "p1", "title": "V1", "content": "C1", "updatedAt": "2026-11-18T00:01:00.000Z"}],
            },
        )
        self.assertEqual(s1, 200)
        assert env1 is not None
        self.assertEqual(env1["revision"], 1)
        self.assertEqual(h1.get("ETag"), '"rev-1"')
        self.assertIn("serverTime", env1)

        # GET verifies ETag and serverTime
        sg, hg, envg = self._request("GET", "/v1/sync", token=token)
        self.assertEqual(sg, 200)
        assert envg is not None
        self.assertEqual(hg.get("ETag"), '"rev-1"')
        self.assertEqual(hg.get("X-PromptPanel-Revision"), "1")
        self.assertIn("serverTime", envg)

        # Device A pushes another update -> revision 2
        s2, _, env2 = self._request(
            "POST",
            "/v1/sync",
            token=token,
            headers={"If-Match": '"rev-1"'},
            body={
                "deviceId": "mac-a",
                "strictConflict": True,
                "entries": [{"id": "e1", "projectId": "p1", "title": "V2-A", "content": "C2-A", "updatedAt": "2026-11-18T00:03:00.000Z"}],
            },
        )
        self.assertEqual(s2, 200)
        assert env2 is not None
        self.assertEqual(env2["revision"], 2)

        # Device B pushes with stale expectedRevision=1 & strictConflict=True -> 409 Conflict
        s_conflict, h_conflict, env_conflict = self._request(
            "POST",
            "/v1/sync",
            token=token,
            body={
                "deviceId": "android-b",
                "expectedRevision": 1,
                "strictConflict": True,
                "entries": [{"id": "e1", "projectId": "p1", "title": "V2-B", "content": "C2-B", "updatedAt": "2026-11-18T00:02:00.000Z"}],
            },
        )
        self.assertEqual(s_conflict, 409)
        assert env_conflict is not None
        self.assertTrue(env_conflict["conflict"])
        self.assertEqual(env_conflict["serverRevision"], 2)
        self.assertEqual(h_conflict.get("ETag"), '"rev-2"')
        self.assertEqual(env_conflict["entries"][0]["title"], "V2-A")

        # Device B retries with updated expectedRevision=2 -> 200 OK
        s_retry, h_retry, env_retry = self._request(
            "POST",
            "/v1/sync",
            token=token,
            body={
                "deviceId": "android-b",
                "expectedRevision": 2,
                "strictConflict": True,
                "entries": [{"id": "e1", "projectId": "p1", "title": "V2-B", "content": "C2-B", "updatedAt": "2026-11-18T00:02:00.000Z"}],
            },
        )
        self.assertEqual(s_retry, 200)
        assert env_retry is not None
        self.assertEqual(env_retry["revision"], 3)
        self.assertEqual(h_retry.get("ETag"), '"rev-3"')
        self.assertEqual(env_retry["entries"][0]["title"], "V2-A")
        self.assertTrue(any(v["title"] == "V2-B" for v in env_retry["versions"]))

        # Legacy client without strictConflict passing stale expectedRevision=1 -> 200 with rebased=True
        s_rebase, _, env_rebase = self._request(
            "POST",
            "/v1/sync",
            token=token,
            body={
                "deviceId": "legacy-b",
                "expectedRevision": 1,
                "entries": [{"id": "e2", "projectId": "p1", "title": "Legacy", "content": "Body", "updatedAt": "2026-11-18T00:04:00.000Z"}],
            },
        )
        self.assertEqual(s_rebase, 200)
        assert env_rebase is not None
        self.assertTrue(env_rebase.get("rebased"))
        self.assertEqual(env_rebase["serverRevision"], 4)


if __name__ == "__main__":
    unittest.main()
