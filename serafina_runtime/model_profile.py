"""Universal Model Capability Profile & Auto Discovery Engine for Serafina 5.0.

Decouples runtime logic from hard-coded model names (Nemotron, Qwen, K2).
Provides dynamic capability probing, protocol mapping, and runtime profiles.
"""
from __future__ import annotations

import dataclasses
import json
import urllib.request
import urllib.error
from typing import Any, Dict, List, Optional


@dataclasses.dataclass
class ProtocolConfig:
    api: str = "openai_chat"  # 'openai_chat', 'responses', 'anthropic'
    streaming: bool = True
    tool_calls: bool = True
    reasoning: str = "auto"   # 'auto', 'native', 'none'


@dataclasses.dataclass
class CapabilitiesConfig:
    context_window: int = 32768
    max_output_tokens: int = 4096
    tokenizer: str = "auto"
    vision: bool = False
    embeddings: bool = False


@dataclasses.dataclass
class RuntimeConfig:
    prefill_chunk: int = 2048
    prefix_cache: bool = True
    mtp: bool = False
    kv_quantization: str = "none"
    max_concurrency: int = 1


@dataclasses.dataclass
class ReliabilityConfig:
    metal_error_count: int = 0
    fallback_model: Optional[str] = None
    health: str = "unknown"  # 'healthy', 'degraded', 'isolated', 'stopped'


@dataclasses.dataclass
class ModelCapabilityProfile:
    model_id: str
    backend: str              # 'omlx', 'mtplx', 'lmstudio', 'remote_api'
    endpoint: str             # e.g. 'http://127.0.0.1:7777'
    protocol: ProtocolConfig = dataclasses.field(default_factory=ProtocolConfig)
    capabilities: CapabilitiesConfig = dataclasses.field(default_factory=CapabilitiesConfig)
    runtime: RuntimeConfig = dataclasses.field(default_factory=RuntimeConfig)
    reliability: ReliabilityConfig = dataclasses.field(default_factory=ReliabilityConfig)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "model_id": self.model_id,
            "backend": self.backend,
            "endpoint": self.endpoint,
            "protocol": dataclasses.asdict(self.protocol),
            "capabilities": dataclasses.asdict(self.capabilities),
            "runtime": dataclasses.asdict(self.runtime),
            "reliability": dataclasses.asdict(self.reliability),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> ModelCapabilityProfile:
        return cls(
            model_id=data["model_id"],
            backend=data.get("backend", "omlx"),
            endpoint=data.get("endpoint", "http://127.0.0.1:7777"),
            protocol=ProtocolConfig(**data.get("protocol", {})),
            capabilities=CapabilitiesConfig(**data.get("capabilities", {})),
            runtime=RuntimeConfig(**data.get("runtime", {})),
            reliability=ReliabilityConfig(**data.get("reliability", {})),
        )


class ModelCapabilityRegistry:
    """Discovers, registers, and serves Model Capability Profiles."""

    def __init__(self):
        self.profiles: Dict[str, ModelCapabilityProfile] = {}

    def register(self, profile: ModelCapabilityProfile) -> None:
        self.profiles[profile.model_id] = profile

    def get(self, model_id: str) -> Optional[ModelCapabilityProfile]:
        return self.profiles.get(model_id)

    def probe_backend(self, backend: str, endpoint: str, timeout: float = 2.0) -> List[ModelCapabilityProfile]:
        """Probes local inference backend API to auto-discover models and capabilities."""
        discovered: List[ModelCapabilityProfile] = []
        try:
            # 1. Try standard /v1/models
            url = f"{endpoint.rstrip('/')}/v1/models"
            req = urllib.request.Request(url, headers={"User-Agent": "Serafina-Discovery/5.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status == 200:
                    payload = json.loads(resp.read().decode("utf-8"))
                    models_data = payload.get("data", [])
                    for m in models_data:
                        mid = m.get("id") or m.get("name")
                        if not mid:
                            continue
                        
                        # Infer capability based on backend characteristics
                        profile = ModelCapabilityProfile(
                            model_id=mid,
                            backend=backend,
                            endpoint=endpoint,
                            protocol=ProtocolConfig(
                                api="openai_chat",
                                streaming=True,
                                tool_calls=True,
                                reasoning="auto",
                            ),
                            capabilities=CapabilitiesConfig(
                                context_window=32768,
                                max_output_tokens=4096,
                                vision=any(kw in mid.lower() for kw in ["vision", "vl", "omni", "mova"]),
                            ),
                            runtime=RuntimeConfig(
                                prefill_chunk=2048,
                                prefix_cache=True,
                                mtp=("mtp" in mid.lower() or backend == "mtplx"),
                                max_concurrency=1,
                            ),
                            reliability=ReliabilityConfig(health="healthy"),
                        )
                        self.register(profile)
                        discovered.append(profile)
        except Exception:
            pass
        return discovered
