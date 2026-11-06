"""Azure Files (SMB, ReadWriteMany) helpers with safe concurrent-write practices.

Layout:
  /mnt/shared/common/<file>            shared by all services
  /mnt/shared/<service>/<file>         written only by <service>, readable by all

Rules implemented here:
  * Atomic writes: write a unique temp file in the target directory, flush +
    fsync, then os.replace(). Readers on any node see the old or the new file,
    never a partial one (rename is atomic on the same SMB share).
  * One writer per file: services write only below their own directory or use
    unique file names (UUIDs) in common/.
  * Cross-node mutual exclusion: lock files created with O_CREAT|O_EXCL, which
    the SMB server evaluates atomically. Stale locks expire after a timeout.
  * Path traversal protection: every path must resolve below the mount.
"""

from __future__ import annotations

import contextlib
import json
import os
import socket
import time
import uuid
from collections.abc import Iterator
from pathlib import Path

SHARED_DIRS = ("common", "frontend", "user-service", "product-service", "order-service", "notification-service")


class StorageError(RuntimeError):
    pass


class LockTimeout(StorageError):
    pass


class SharedStorage:
    def __init__(self, root: str | Path, service: str) -> None:
        self.root = Path(root)
        self.service = service

    # -- paths -------------------------------------------------------------
    def _resolve(self, *parts: str) -> Path:
        path = self.root.joinpath(*parts).resolve()
        root = self.root.resolve()
        if path != root and root not in path.parents:
            raise StorageError("path escapes the shared volume")
        return path

    def own_dir(self) -> Path:
        return self._resolve(self.service)

    def ensure_layout(self) -> None:
        for d in SHARED_DIRS:
            self._resolve(d).mkdir(parents=True, exist_ok=True)

    # -- writes ------------------------------------------------------------
    def write_bytes(self, relative: str, data: bytes, area: str | None = None) -> Path:
        if area not in (None, self.service, "common"):
            raise StorageError(f"{self.service} may only write to its own directory or common/")
        target = self._resolve(area or self.service, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.parent / f".{target.name}.{uuid.uuid4().hex}.tmp"
        try:
            with open(tmp, "wb") as fh:
                fh.write(data)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, target)
        finally:
            with contextlib.suppress(FileNotFoundError):
                tmp.unlink()
        return target

    def write_text(self, relative: str, text: str, area: str | None = None) -> Path:
        return self.write_bytes(relative, text.encode("utf-8"), area)

    def write_json(self, relative: str, payload: dict, area: str | None = None) -> Path:
        return self.write_text(relative, json.dumps(payload, indent=2, default=str), area)

    # -- reads -------------------------------------------------------------
    def read_text(self, owner: str, relative: str) -> str:
        path = self._resolve(owner, relative)
        if not path.is_file():
            raise FileNotFoundError(relative)
        return path.read_text(encoding="utf-8")

    def list_files(self, owner: str, sub: str = "", limit: int = 100) -> list[dict]:
        base = self._resolve(owner, sub) if sub else self._resolve(owner)
        if not base.exists():
            return []
        files = [p for p in base.rglob("*") if p.is_file() and not p.name.startswith(".")]
        files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return [
            {
                "path": str(p.relative_to(self._resolve(owner))),
                "size": p.stat().st_size,
                "modified": p.stat().st_mtime,
            }
            for p in files[:limit]
        ]

    # -- locking -----------------------------------------------------------
    @contextlib.contextmanager
    def exclusive_lock(self, name: str, timeout: float = 10.0, stale_after: float = 60.0) -> Iterator[Path]:
        lock = self._resolve("common", ".locks", f"{name}.lock")
        lock.parent.mkdir(parents=True, exist_ok=True)
        deadline = time.monotonic() + timeout
        while True:
            try:
                fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o640)
                with os.fdopen(fd, "w") as fh:
                    fh.write(json.dumps({"owner": self.service, "host": socket.gethostname(), "at": time.time()}))
                break
            except FileExistsError:
                with contextlib.suppress(FileNotFoundError):
                    if time.time() - lock.stat().st_mtime > stale_after:
                        lock.unlink()  # crashed holder
                        continue
                if time.monotonic() > deadline:
                    raise LockTimeout(name) from None
                time.sleep(0.1)
        try:
            yield lock
        finally:
            with contextlib.suppress(FileNotFoundError):
                lock.unlink()
