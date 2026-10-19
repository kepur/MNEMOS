"""Apple Silicon Unified Memory (96GB) Multi-Tier Resource Budget Engine.

Maintains three independent budgets:
1. Memory Pressure Budget (Mach VM pressure, Swap, KV expansion limits)
2. Compute Budget (Serialized primary LLM inference, embedding worker throttling)
3. Persistence Budget (SQLite WAL pruning, CAS blob quotas & TTL GC)
"""
from __future__ import annotations

import os
import shutil
import subprocess
import time
from typing import Any, Dict, Tuple


class MemoryPressureBudget:
    """Monitors macOS Mach kernel VM pressure and controls KV cache / context growth."""

    def __init__(self, critical_threshold_pct: float = 85.0):
        self.critical_threshold_pct = critical_threshold_pct

    def get_memory_pressure_state(self) -> Dict[str, Any]:
        """Queries vm_stat and sysctl to evaluate unified memory pressure."""
        total_gb = 96.0
        used_gb = 30.0
        pressure_level = "normal"

        try:
            # Try sysctl hw.memsize
            out = subprocess.check_output(["sysctl", "-n", "hw.memsize"], timeout=1).decode().strip()
            total_bytes = int(out)
            total_gb = total_bytes / (1024 ** 3)
        except Exception:
            pass

        try:
            # Query vm_stat to estimate used pages
            vm_out = subprocess.check_output(["vm_stat"], timeout=1).decode()
            lines = vm_out.splitlines()
            pages_active = 0
            pages_wired = 0
            pages_compressed = 0
            for line in lines:
                if "Pages active:" in line:
                    pages_active = int(line.split(":")[1].strip().rstrip("."))
                elif "Pages wired down:" in line:
                    pages_wired = int(line.split(":")[1].strip().rstrip("."))
                elif "Pages occupied by compressor:" in line:
                    pages_compressed = int(line.split(":")[1].strip().rstrip("."))
            # Page size on Apple Silicon is 16384 bytes (16KB)
            used_bytes = (pages_active + pages_wired + pages_compressed) * 16384
            used_gb = used_bytes / (1024 ** 3)
        except Exception:
            pass

        used_pct = (used_gb / total_gb) * 100.0 if total_gb > 0 else 0.0
        if used_pct >= self.critical_threshold_pct:
            pressure_level = "critical"
        elif used_pct >= 70.0:
            pressure_level = "warning"
        else:
            pressure_level = "normal"

        return {
            "total_gb": round(total_gb, 1),
            "used_gb": round(used_gb, 1),
            "used_pct": round(used_pct, 1),
            "pressure_level": pressure_level,
            "allow_context_expansion": pressure_level != "critical",
        }


class ComputeBudget:
    """Guarantees single primary active model on unified memory, serializes inference."""

    def __init__(self, max_concurrent_llm: int = 1):
        self.max_concurrent_llm = max_concurrent_llm
        self.active_llm_count = 0
        self.active_embedding_workers = 0

    def acquire_inference_slot(self) -> bool:
        if self.active_llm_count >= self.max_concurrent_llm:
            return False
        self.active_llm_count += 1
        return True

    def release_inference_slot(self) -> None:
        self.active_llm_count = max(0, self.active_llm_count - 1)

    def can_run_embedding(self) -> bool:
        # Avoid heavy embedding compute if primary LLM is actively generating
        return self.active_llm_count == 0


class PersistenceBudget:
    """Manages disk space quotas for SQLite WAL, checkpoint events, and CAS blobs."""

    def __init__(self, max_blob_store_mb: float = 2048.0):
        self.max_blob_store_mb = max_blob_store_mb

    def check_disk_quota(self, store_path: str) -> Dict[str, Any]:
        """Calculates storage usage and free disk capacity."""
        total_size_bytes = 0
        file_count = 0
        if os.path.exists(store_path):
            for root, _, files in os.walk(store_path):
                for f in files:
                    fp = os.path.join(root, f)
                    try:
                        total_size_bytes += os.path.getsize(fp)
                        file_count += 1
                    except OSError:
                        pass

        size_mb = total_size_bytes / (1024 * 1024)
        free_disk_gb = 0.0
        try:
            stat = shutil.disk_usage(store_path if os.path.exists(store_path) else "/")
            free_disk_gb = stat.free / (1024 ** 3)
        except Exception:
            pass

        return {
            "used_mb": round(size_mb, 2),
            "max_mb": self.max_blob_store_mb,
            "file_count": file_count,
            "free_disk_gb": round(free_disk_gb, 1),
            "quota_exceeded": size_mb > self.max_blob_store_mb,
        }
