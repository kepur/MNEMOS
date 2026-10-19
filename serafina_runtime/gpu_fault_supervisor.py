"""GPU Fault Supervisor and Multi-Tier Runtime Health Supervisor for Serafina 5.1.

Implements:
1. 6-Tier Runtime Health State Machine:
   - L1_SYSTEM: CPU, RAM, Swap, Thermal, Memory Pressure
   - L2_METAL_GPU: Metal Command Buffer, GPU Watchdog, Metal allocation
   - L3_INFERENCE_BACKEND: oMLX / MTPLX backend availability, active model, prefill/decode
   - L4_GATEWAY_PROTOCOL: Gateway port :8002, SSE stream, request queue, HTTP status
   - L5_AGENT_SUPERVISOR: Loop radar, Circuit Breaker, Stalled tool detection, Task progress
   - L6_MEMORY_RECOVERY: Event store WAL, FTS5 index, blob store, APFS Quiescent Checkpoints
2. Unified Health States: HEALTHY, DEGRADED, UNHEALTHY, RECOVERING, QUARANTINED, UNKNOWN
3. Adaptive Runtime Protection (Fault Circuit Breaker & Automatic Quarantine on 2 consecutive faults)
4. Key Agent Productivity Metrics:
   - Effective Agent Throughput (EAT): Verified steps / criteria completed per minute
   - Wasted Compute Ratio (WCR): Ratio of compute wasted on dead retries/failed prefills/stalls
"""
from __future__ import annotations

import dataclasses
import enum
import time
from typing import Any, Dict, List, Optional, Tuple


class HealthState(enum.Enum):
    HEALTHY = "HEALTHY"
    DEGRADED = "DEGRADED"
    UNHEALTHY = "UNHEALTHY"
    RECOVERING = "RECOVERING"
    QUARANTINED = "QUARANTINED"
    UNKNOWN = "UNKNOWN"


class RuntimeLayer(enum.Enum):
    L1_SYSTEM = "L1_SYSTEM"
    L2_METAL_GPU = "L2_METAL_GPU"
    L3_INFERENCE_BACKEND = "L3_INFERENCE_BACKEND"
    L4_GATEWAY_PROTOCOL = "L4_GATEWAY_PROTOCOL"
    L5_AGENT_SUPERVISOR = "L5_AGENT_SUPERVISOR"
    L6_MEMORY_RECOVERY = "L6_MEMORY_RECOVERY"


class FaultType(enum.Enum):
    METAL_GPU = "METAL_GPU"           # kIOGPUCommandBufferCallbackError, Metal device lost
    OOM_SWAP = "OOM_SWAP"             # Memory pressure critical, allocation failure, swap
    TIMEOUT = "TIMEOUT"               # Stalled prefill, TTFT exceeded limit
    PROTOCOL_ERROR = "PROTOCOL_ERROR" # Bad JSON, HTTP 5xx, SSE disconnection
    UNKNOWN = "UNKNOWN"


@dataclasses.dataclass
class FaultIncident:
    fault_type: FaultType
    raw_error: str
    model_id: str
    backend: str
    prefill_chunk: int
    timestamp: float = dataclasses.field(default_factory=time.time)
    resolved: bool = False
    recovery_action: str = ""


class GPUFaultClassifier:
    """Classifies runtime exceptions and backend errors into structured fault domains."""

    METAL_SIGNATURES = [
        "kiogpucommandbuffercallbackerrorimpactinginteractivity",
        "kiogpu",
        "metal device lost",
        "command buffer failed",
        "mpscommandbuffer",
        "metal watchdog",
        "iogpu",
    ]

    OOM_SIGNATURES = [
        "out of memory",
        "metal memory allocation failure",
        "posix_spawn failed: cannot allocate memory",
        "memory pressure",
        "cannot allocate",
        "oom",
    ]

    TIMEOUT_SIGNATURES = [
        "timed out",
        "timeout",
        "connection closed before response",
        "read timeout",
    ]

    PROTOCOL_SIGNATURES = [
        "jsondecodeerror",
        "expecting value",
        "bad gateway",
        "502 bad gateway",
        "503 service unavailable",
        "broken pipe",
        "connection refused",
    ]

    @classmethod
    def classify(cls, error_text: str) -> FaultType:
        low = (error_text or "").lower()
        for sig in cls.METAL_SIGNATURES:
            if sig in low:
                return FaultType.METAL_GPU
        for sig in cls.OOM_SIGNATURES:
            if sig in low:
                return FaultType.OOM_SWAP
        for sig in cls.TIMEOUT_SIGNATURES:
            if sig in low:
                return FaultType.TIMEOUT
        for sig in cls.PROTOCOL_SIGNATURES:
            if sig in low:
                return FaultType.PROTOCOL_ERROR
        return FaultType.UNKNOWN


class AdaptivePrefillManager:
    """Manages adaptive chunk ladder degradation (2048 -> 1024 -> 512 -> 256)."""

    LADDER: List[int] = [2048, 1024, 512, 256]

    def __init__(self, default_chunk: int = 2048):
        self.default_chunk = default_chunk
        self.current_chunks: Dict[str, int] = {}  # model_id -> current chunk

    def get_chunk_size(self, model_id: str) -> int:
        return self.current_chunks.get(model_id, self.default_chunk)

    def degrade_chunk(self, model_id: str) -> Tuple[int, bool]:
        """Degrades to the next smaller chunk. Returns (new_chunk, can_degrade_further)."""
        current = self.get_chunk_size(model_id)
        try:
            idx = self.LADDER.index(current)
            if idx + 1 < len(self.LADDER):
                new_chunk = self.LADDER[idx + 1]
                self.current_chunks[model_id] = new_chunk
                can_more = (idx + 1 + 1 < len(self.LADDER))
                return new_chunk, can_more
        except ValueError:
            pass
        # Fallback to minimum
        self.current_chunks[model_id] = self.LADDER[-1]
        return self.LADDER[-1], False

    def reset_chunk(self, model_id: str) -> int:
        self.current_chunks[model_id] = self.default_chunk
        return self.default_chunk


class RuntimeHealthSupervisor:
    """Oversees multi-tier runtime health, classifies Metal/OOM crashes, and enforces ARP isolation."""

    def __init__(self, cooldown_seconds: float = 60.0):
        self.cooldown_seconds = cooldown_seconds
        self.prefill_mgr = AdaptivePrefillManager()
        self.incidents: List[FaultIncident] = []
        self.isolated_models: Dict[str, float] = {}  # model_id -> cooldown_expiry_timestamp
        self.consecutive_faults: Dict[str, int] = {} # model_id -> count

        # 6-Tier Health State Machine
        self.layer_states: Dict[RuntimeLayer, HealthState] = {
            RuntimeLayer.L1_SYSTEM: HealthState.HEALTHY,
            RuntimeLayer.L2_METAL_GPU: HealthState.HEALTHY,
            RuntimeLayer.L3_INFERENCE_BACKEND: HealthState.HEALTHY,
            RuntimeLayer.L4_GATEWAY_PROTOCOL: HealthState.HEALTHY,
            RuntimeLayer.L5_AGENT_SUPERVISOR: HealthState.HEALTHY,
            RuntimeLayer.L6_MEMORY_RECOVERY: HealthState.HEALTHY,
        }
        self.layer_details: Dict[RuntimeLayer, str] = {
            RuntimeLayer.L1_SYSTEM: "系统资源正常 · 统一内存与能耗稳定",
            RuntimeLayer.L2_METAL_GPU: "Metal 看门狗就绪 · 命令缓冲区正常",
            RuntimeLayer.L3_INFERENCE_BACKEND: "推理引擎活跃 · 预填解码正常",
            RuntimeLayer.L4_GATEWAY_PROTOCOL: "网关 :8002 在线 · 请求队列正常",
            RuntimeLayer.L5_AGENT_SUPERVISOR: "PAR 督导就绪 · 防循环熔断器监控中",
            RuntimeLayer.L6_MEMORY_RECOVERY: "SQLite WAL 就绪 · FTS5 索引与快照同步",
        }

        # Agent Productivity & Compute Metrics
        self.start_time = time.time()
        self.verified_steps: int = 0
        self.productive_tokens: int = 0
        self.wasted_tokens: int = 0
        self.total_requests: int = 0
        self.failed_requests: int = 0

    def update_layer(self, layer: RuntimeLayer, state: HealthState, detail: str = "") -> None:
        self.layer_states[layer] = state
        if detail:
            self.layer_details[layer] = detail

    def get_layer(self, layer: RuntimeLayer) -> Tuple[HealthState, str]:
        return self.layer_states.get(layer, HealthState.UNKNOWN), self.layer_details.get(layer, "")

    def record_fault(self, model_id: str, backend: str, raw_error: str) -> Tuple[FaultType, str]:
        """Records a fault, decides recovery action, and tracks isolation status."""
        ft = GPUFaultClassifier.classify(raw_error)
        chunk = self.prefill_mgr.get_chunk_size(model_id)
        incident = FaultIncident(
            fault_type=ft,
            raw_error=raw_error,
            model_id=model_id,
            backend=backend,
            prefill_chunk=chunk,
        )

        self.consecutive_faults[model_id] = self.consecutive_faults.get(model_id, 0) + 1
        count = self.consecutive_faults[model_id]
        self.failed_requests += 1

        action = "retry"
        if ft == FaultType.METAL_GPU:
            new_chunk, can_degrade = self.prefill_mgr.degrade_chunk(model_id)
            if count >= 2:
                # Isolate model instance into cooldown
                self.isolated_models[model_id] = time.time() + self.cooldown_seconds
                action = f"isolate_and_cooldown:{self.cooldown_seconds}s"
                self.update_layer(
                    RuntimeLayer.L2_METAL_GPU,
                    HealthState.QUARANTINED,
                    f"Metal看门狗连续异常 ({count}次) · 触发ARP故障隔离 (冷却 {int(self.cooldown_seconds)}s)"
                )
                self.update_layer(
                    RuntimeLayer.L3_INFERENCE_BACKEND,
                    HealthState.QUARANTINED,
                    f"模型 {model_id} 已隔离 · 保护系统免受GPU崩溃影响"
                )
            else:
                action = f"degrade_prefill_chunk:{new_chunk}"
                self.update_layer(
                    RuntimeLayer.L2_METAL_GPU,
                    HealthState.DEGRADED,
                    f"Metal命令缓冲区超时 · Prefill降级至 {new_chunk}"
                )
                self.update_layer(
                    RuntimeLayer.L3_INFERENCE_BACKEND,
                    HealthState.DEGRADED,
                    f"自适应降级 Prefill chunk: {new_chunk}"
                )
        elif ft == FaultType.OOM_SWAP:
            action = "reduce_context_and_concurrency"
            if count >= 2:
                self.isolated_models[model_id] = time.time() + self.cooldown_seconds
                action = f"isolate_and_cooldown:{self.cooldown_seconds}s"
                self.update_layer(RuntimeLayer.L1_SYSTEM, HealthState.UNHEALTHY, "内存压力临界 · 触发实例隔离")
                self.update_layer(RuntimeLayer.L2_METAL_GPU, HealthState.QUARANTINED, "显存分配耗尽 · 隔离保护")
            else:
                self.update_layer(RuntimeLayer.L1_SYSTEM, HealthState.DEGRADED, "内存压力过大 · 缩减上下文")
        elif ft == FaultType.TIMEOUT:
            action = "check_output_limits_and_retry"
            self.update_layer(RuntimeLayer.L3_INFERENCE_BACKEND, HealthState.DEGRADED, f"推理超时 · 限制生成输出")
        elif ft == FaultType.PROTOCOL_ERROR:
            action = "restart_backend_adapter"
            self.update_layer(RuntimeLayer.L4_GATEWAY_PROTOCOL, HealthState.DEGRADED, f"协议异常 · {raw_error[:60]}")
        else:
            action = "quiescent_pause"

        incident.recovery_action = action
        self.incidents.append(incident)
        return ft, action

    def record_success(self, model_id: str, prompt_tokens: int = 0, completion_tokens: int = 0) -> None:
        """Clears consecutive fault counters on successful inference and restores layers."""
        self.consecutive_faults[model_id] = 0
        self.total_requests += 1
        self.productive_tokens += (prompt_tokens + completion_tokens)

        # Clear quarantine if previously isolated
        if model_id in self.isolated_models:
            del self.isolated_models[model_id]

        if self.layer_states[RuntimeLayer.L2_METAL_GPU] != HealthState.HEALTHY:
            self.update_layer(RuntimeLayer.L2_METAL_GPU, HealthState.HEALTHY, "Metal 看门狗就绪 · 推理成功")
        if self.layer_states[RuntimeLayer.L3_INFERENCE_BACKEND] != HealthState.HEALTHY:
            self.update_layer(RuntimeLayer.L3_INFERENCE_BACKEND, HealthState.HEALTHY, f"推理引擎活跃 · 模型 {model_id} 正常")

    def record_wasted(self, model_id: str, prompt_tokens: int = 0, completion_tokens: int = 0, reason: str = "") -> None:
        """Records tokens wasted on failed, aborted, or looped executions."""
        wasted = prompt_tokens + completion_tokens
        if wasted > 0:
            self.wasted_tokens += wasted

    def record_progress_step(self, verified: bool = True) -> None:
        """Records an agent step that produced verified progress towards task acceptance."""
        if verified:
            self.verified_steps += 1

    def is_isolated(self, model_id: str) -> Tuple[bool, float]:
        """Returns (is_isolated, remaining_seconds)."""
        expiry = self.isolated_models.get(model_id, 0.0)
        now = time.time()
        if expiry > now:
            return True, expiry - now
        if model_id in self.isolated_models:
            del self.isolated_models[model_id]
            # Transition layer from QUARANTINED to RECOVERING
            if self.layer_states[RuntimeLayer.L3_INFERENCE_BACKEND] == HealthState.QUARANTINED:
                self.update_layer(RuntimeLayer.L3_INFERENCE_BACKEND, HealthState.RECOVERING, f"模型 {model_id} 冷却完毕 · 恢复待命中")
            if self.layer_states[RuntimeLayer.L2_METAL_GPU] == HealthState.QUARANTINED:
                self.update_layer(RuntimeLayer.L2_METAL_GPU, HealthState.RECOVERING, "Metal 故障隔离解除 · 恢复健康监测")
        return False, 0.0

    def get_eat_per_min(self) -> float:
        """Calculates Effective Agent Throughput (EAT) in verified steps per minute."""
        elapsed_mins = max((time.time() - self.start_time) / 60.0, 1.0 / 60.0)
        return round(float(self.verified_steps) / elapsed_mins, 2)

    def get_wcr_pct(self) -> float:
        """Calculates Wasted Compute Ratio (WCR) as a percentage of total compute."""
        total_tokens = self.productive_tokens + self.wasted_tokens
        if total_tokens <= 0:
            return 0.0
        return round(float(self.wasted_tokens) / float(total_tokens) * 100.0, 1)

    def get_overall_health(self) -> HealthState:
        """Determines the system-wide health status based on the most severe layer state."""
        severities = [
            HealthState.QUARANTINED,
            HealthState.UNHEALTHY,
            HealthState.RECOVERING,
            HealthState.DEGRADED,
            HealthState.UNKNOWN,
            HealthState.HEALTHY,
        ]
        active_states = set(self.layer_states.values())
        for sev in severities:
            if sev in active_states:
                return sev
        return HealthState.HEALTHY

    def get_health_matrix(self) -> Dict[str, Any]:
        """Returns comprehensive 6-layer health matrix and productivity metrics."""
        now = time.time()
        # Prune expired isolations
        quarantined = []
        for mid, exp in list(self.isolated_models.items()):
            rem = exp - now
            if rem > 0:
                quarantined.append({"model": mid, "remaining_seconds": round(rem, 1)})
            else:
                del self.isolated_models[mid]

        return {
            "overall": self.get_overall_health().value,
            "layers": {
                layer.value: {
                    "state": self.layer_states[layer].value,
                    "detail": self.layer_details[layer],
                }
                for layer in RuntimeLayer
            },
            "metrics": {
                "eat_per_min": self.get_eat_per_min(),
                "wcr_pct": self.get_wcr_pct(),
                "verified_steps": self.verified_steps,
                "productive_tokens": self.productive_tokens,
                "wasted_tokens": self.wasted_tokens,
                "total_requests": self.total_requests,
                "failed_requests": self.failed_requests,
            },
            "quarantined_models": quarantined,
            "total_incidents": len(self.incidents),
            "recent_incidents": [
                {
                    "type": inc.fault_type.value,
                    "model": inc.model_id,
                    "backend": inc.backend,
                    "action": inc.recovery_action,
                    "chunk": inc.prefill_chunk,
                    "time": round(inc.timestamp, 2),
                    "error": inc.raw_error[:120],
                }
                for inc in self.incidents[-6:]
            ],
        }

    def get_summary(self) -> Dict[str, Any]:
        """Backward-compatible summary for older endpoints and UI widgets."""
        matrix = self.get_health_matrix()
        return {
            "total_incidents": len(self.incidents),
            "recent_incidents": matrix["recent_incidents"],
            "isolated_models_count": len(matrix["quarantined_models"]),
            "quarantined_models": matrix["quarantined_models"],
            "eat_per_min": matrix["metrics"]["eat_per_min"],
            "wcr_pct": matrix["metrics"]["wcr_pct"],
            "overall_health": matrix["overall"],
            "layers": matrix["layers"],
        }


# Keep GPUFaultSupervisor as an alias / subclass for complete backward compatibility
GPUFaultSupervisor = RuntimeHealthSupervisor
