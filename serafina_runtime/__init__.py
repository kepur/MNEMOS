"""Serafina 5.0 — Universal Persistent Agent Runtime (PAR) Core Package.

Provides a unified CPU-first supervisor, progress ledger, loop radar, circuit breaker,
checkpoint manager, memory engine, GPU fault supervisor, model capability profiles,
and resource budgets for Apple Silicon.
"""
from __future__ import annotations

from .event_store import EventStore
from .task_ledger import ProgressLedger, TaskState, AcceptanceCriterion, EvidenceItem
from .loop_detector import (
    LoopDetector,
    LoopAnomaly,
    ControlState,
    RepetitionDetector,
    ProgressEvaluator,
    SemanticLoopDetector,
    CompletionVerifier,
)
from .circuit_breaker import CircuitBreaker, BreakerLevel, DiagnosticSubtask
from .execution_controller import ExecutionController, ToolEffectType
from .checkpoint import CheckpointManager
from .context_compiler import ContextCompiler
from .memory_engine import MemoryEngine
from .gpu_fault_supervisor import (
    GPUFaultSupervisor,
    RuntimeHealthSupervisor,
    HealthState,
    RuntimeLayer,
    GPUFaultClassifier,
    FaultType,
    AdaptivePrefillManager,
)
from .model_profile import (
    ModelCapabilityProfile,
    ModelCapabilityRegistry,
    ProtocolConfig,
    CapabilitiesConfig,
    RuntimeConfig,
    ReliabilityConfig,
)
from .resource_budget import (
    MemoryPressureBudget,
    ComputeBudget,
    PersistenceBudget,
)

__all__ = [
    "EventStore",
    "ProgressLedger",
    "TaskState",
    "AcceptanceCriterion",
    "EvidenceItem",
    "LoopDetector",
    "LoopAnomaly",
    "ControlState",
    "RepetitionDetector",
    "ProgressEvaluator",
    "SemanticLoopDetector",
    "CompletionVerifier",
    "CircuitBreaker",
    "BreakerLevel",
    "DiagnosticSubtask",
    "ExecutionController",
    "ToolEffectType",
    "CheckpointManager",
    "ContextCompiler",
    "MemoryEngine",
    "GPUFaultSupervisor",
    "RuntimeHealthSupervisor",
    "HealthState",
    "RuntimeLayer",
    "GPUFaultClassifier",
    "FaultType",
    "AdaptivePrefillManager",
    "ModelCapabilityProfile",
    "ModelCapabilityRegistry",
    "ProtocolConfig",
    "CapabilitiesConfig",
    "RuntimeConfig",
    "ReliabilityConfig",
    "MemoryPressureBudget",
    "ComputeBudget",
    "PersistenceBudget",
]
