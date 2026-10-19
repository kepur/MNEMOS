"""Serafina 5.0 Network Sentinel & Traffic Monitor for macOS.

Real-time inspection of:
  * Network traffic bandwidth & interface throughput (in/out speed).
  * Real-time graphical traffic history wave (upload/download sparkline series).
  * Outbound data audit (inspecting what is being uploaded: image, text, document/archive, credentials).
  * Public IP geolocation & ISP resolution via fast public APIs with persistent local cache.
  * Active TCP/UDP sockets and outbound public internet connections.
  * Local listening ports and dangerous 0.0.0.0/public exposure.
  * Suspicious processes (paths in /tmp, unlinked/deleted binaries, reverse shells).
  * Process lineage (parent daemon, child processes) & recursive family termination.
"""
from __future__ import annotations

import collections
import ipaddress
import json
import mimetypes
import os
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Known dangerous or trojan ports
MALICIOUS_PORTS = {
    4444: "Metasploit / Meterpreter default payload",
    1337: "Elite / Common Hacktool backdoor",
    31337: "Back Orifice / Elite Trojan",
    6667: "IRC / Botnet C2",
    5555: "Android ADB / Trojan",
    8888: "Suspicious HTTP / Proxy / Web Shell",
    9999: "Urgent Trojan / Raw Shell",
    12345: "NetBus Trojan",
}

# Sensitive services that should NEVER be exposed to 0.0.0.0
SENSITIVE_SERVICE_PORTS = {
    6379: "Redis (No-Auth risk)",
    3306: "MySQL Database",
    5432: "PostgreSQL Database",
    27017: "MongoDB Database",
    9200: "Elasticsearch",
    11211: "Memcached",
    2375: "Docker Daemon (Unauthenticated Remote Code Execution)",
    2376: "Docker TLS",
    5005: "Java Remote Debugger",
    9229: "Node.js Remote Inspector",
    5900: "VNC Remote Desktop",
}

# Standard benign internet destination ports
STANDARD_INTERNET_PORTS = {
    80, 443, 53, 853, 123, 22, 587, 465, 993, 995, 5223, 5228, 8000, 8080, 8443
}

# Suspicious tools or shells that shouldn't typically establish persistent public sockets
SUSPICIOUS_TOOLS = {"nc", "netcat", "ncat", "socat"}

IMAGE_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".heic", ".raw", ".svg", ".ico"
}
VIDEO_EXTENSIONS = {
    ".mp4", ".mov", ".m4v", ".mkv", ".avi", ".flv", ".wmv", ".webm", ".mpg", ".mpeg"
}
TEXT_EXTENSIONS = {
    ".txt", ".json", ".csv", ".log", ".md", ".py", ".js", ".ts", ".html", ".xml",
    ".yaml", ".yml", ".sh", ".conf", ".ini", ".sql", ".env", ".toml", ".c", ".cpp", ".swift"
}
DOC_EXTENSIONS = {
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".zip", ".tar",
    ".gz", ".dmg", ".pkg", ".7z", ".rar", ".iso", ".bz2", ".xz"
}
SENSITIVE_PATTERNS = [
    ".ssh/", ".aws/", "keychain", "cookies.sqlite", ".zsh_history", ".bash_history",
    "id_rsa", "id_ed25519", "credentials", "login.keychain"
]


def is_private_ip(ip_str: str) -> bool:
    """Returns True if the IP is loopback, link-local, multicast, or RFC1918 private."""
    clean = ip_str.strip("[]")
    if not clean or clean in ("*", "0.0.0.0", "::", "127.0.0.1", "::1", "localhost"):
        return True
    try:
        ip = ipaddress.ip_address(clean)
        return ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved
    except ValueError:
        return False


def format_bytes(bytes_count: float, per_sec: bool = True) -> str:
    """Human-friendly byte and bandwidth formatting."""
    unit = "/s" if per_sec else ""
    if bytes_count < 1024:
        return f"{bytes_count:.0f} B{unit}"
    elif bytes_count < 1024 * 1024:
        return f"{bytes_count / 1024:.1f} KB{unit}"
    elif bytes_count < 1024 * 1024 * 1024:
        return f"{bytes_count / (1024 * 1024):.2f} MB{unit}"
    else:
        return f"{bytes_count / (1024 * 1024 * 1024):.2f} GB{unit}"


def country_code_to_flag(code: str) -> str:
    """Converts a 2-letter ISO country code to Unicode national flag emoji."""
    if not code or len(code) != 2:
        return "🌐"
    code = code.upper()
    try:
        return chr(127397 + ord(code[0])) + chr(127397 + ord(code[1]))
    except Exception:
        return "🌐"


# ─────────────────────────────────────────────────────────────────────────────
# IP Geolocation Resolver with ThreadPool & Local Persistent Cache
# ─────────────────────────────────────────────────────────────────────────────

class IPGeoResolver:
    """High performance, asynchronous IP Geolocation & ISP resolver."""

    def __init__(self):
        self.cache_file = os.path.expanduser("~/.cache/serafina/ip_geo_cache.json")
        try:
            os.makedirs(os.path.dirname(self.cache_file), exist_ok=True)
        except Exception:
            pass
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._load_cache()
        self._in_flight: Set[str] = set()
        self.executor = ThreadPoolExecutor(max_workers=4)

    def _load_cache(self):
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, "r", encoding="utf-8") as f:
                    self._cache = json.load(f)
            except Exception:
                self._cache = {}

    def _save_cache(self):
        try:
            with open(self.cache_file, "w", encoding="utf-8") as f:
                json.dump(self._cache, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def get_geo(self, ip_str: str) -> Dict[str, Any]:
        """Resolves IP to country, region, city, ISP, flag. Returns immediately."""
        clean = ip_str.strip("[]")
        # Strip port if present in IPv4
        if ":" in clean and not clean.count(":") > 1:
            clean = clean.split(":", 1)[0]

        if not clean or clean in ("*", "0.0.0.0", "::", "127.0.0.1", "::1", "localhost"):
            return {
                "country": "本机回环",
                "region": "本地",
                "city": "本机",
                "isp": "Loopback",
                "country_code": "LO",
                "flag": "💻",
                "summary": "💻 本机回环 (Loopback)",
            }
        if is_private_ip(clean):
            return {
                "country": "局域网",
                "region": "内网",
                "city": "本地网络",
                "isp": "RFC1918 私有地址",
                "country_code": "LAN",
                "flag": "🏠",
                "summary": "🏠 局域网内网 (RFC1918)",
            }

        if clean in self._cache:
            return self._cache[clean]

        # In flight or needs fetch
        if clean not in self._in_flight:
            self._in_flight.add(clean)
            self.executor.submit(self._fetch_geo, clean)

        return {
            "country": "查询中...",
            "region": "",
            "city": "",
            "isp": "",
            "country_code": "",
            "flag": "🌍",
            "summary": f"🌍 解析归属地中: {clean}",
        }

    def _fetch_geo(self, ip: str):
        """Worker thread to query free IP APIs."""
        info: Optional[Dict[str, Any]] = None
        # Primary: ip-api.com with Chinese localization
        try:
            url = f"http://ip-api.com/json/{ip}?lang=zh-CN"
            req = urllib.request.Request(url, headers={"User-Agent": "SerafinaSentinel/1.0"})
            with urllib.request.urlopen(req, timeout=2.5) as resp:
                data = json.loads(resp.read().decode())
                if data.get("status") == "success":
                    cc = data.get("countryCode", "")
                    flag = country_code_to_flag(cc)
                    country = data.get("country", "")
                    region = data.get("regionName", "")
                    city = data.get("city", "")
                    isp = data.get("isp", "") or data.get("org", "")
                    loc_parts = [p for p in [country, region, city] if p]
                    loc_str = "·".join(loc_parts)
                    summary = f"{flag} {loc_str}" + (f" ({isp})" if isp else "")
                    info = {
                        "country": country,
                        "region": region,
                        "city": city,
                        "isp": isp,
                        "org": data.get("org", ""),
                        "country_code": cc,
                        "flag": flag,
                        "summary": summary,
                    }
        except Exception:
            pass

        # Fallback: ipinfo.io
        if not info:
            try:
                url = f"https://ipinfo.io/{ip}/json"
                req = urllib.request.Request(url, headers={"User-Agent": "curl/7.88.1"})
                with urllib.request.urlopen(req, timeout=2.0) as resp:
                    data = json.loads(resp.read().decode())
                    cc = data.get("country", "")
                    flag = country_code_to_flag(cc)
                    country = cc
                    region = data.get("region", "")
                    city = data.get("city", "")
                    org = data.get("org", "")
                    summary = f"{flag} {country}·{city}" + (f" ({org})" if org else "")
                    info = {
                        "country": country,
                        "region": region,
                        "city": city,
                        "isp": org,
                        "org": org,
                        "country_code": cc,
                        "flag": flag,
                        "summary": summary,
                    }
            except Exception:
                pass

        if not info:
            info = {
                "country": "公网未知",
                "region": "",
                "city": "",
                "isp": "",
                "country_code": "",
                "flag": "🌐",
                "summary": f"🌐 公网目标 ({ip})",
            }

        self._cache[ip] = info
        self._in_flight.discard(ip)
        self._save_cache()


# ─────────────────────────────────────────────────────────────────────────────
# Destination Analyzer & Platform Trust Classifier
# ─────────────────────────────────────────────────────────────────────────────

class DestinationAnalyzer:
    """Analyzes upload destination endpoints, resolves domain/host, identifies organisation,
    and categorizes safety trust level (OFFICIAL_TRUSTED, PUBLIC_CLOUD, SUSPICIOUS)."""

    def __init__(self, geo_resolver: Optional['IPGeoResolver'] = None):
        self.geo_resolver = geo_resolver
        self._rdns_cache: Dict[str, str] = {}
        self._lock = threading.Lock()

    def resolve_domain(self, ip_or_host: str) -> str:
        clean = ip_or_host.strip("[]")
        if ":" in clean and not clean.count(":") > 1:
            clean = clean.split(":", 1)[0]
        if not clean or clean in ("*", "0.0.0.0", "127.0.0.1", "localhost", "::1", "::"):
            return "localhost (本机回环)"
        if is_private_ip(clean):
            return "局域网内部节点"
        # If already a domain name
        if any(c.isalpha() for c in clean) and "." in clean:
            return clean

        with self._lock:
            if clean in self._rdns_cache:
                return self._rdns_cache[clean]

        # Check known Apple ranges immediately (17.0.0.0/8 is Apple Inc.)
        if clean.startswith("17."):
            res = "apple.com / icloud.com (Apple 网络骨干)"
            with self._lock:
                self._rdns_cache[clean] = res
            return res

        # Try fast reverse DNS
        resolved = ""
        try:
            orig_timeout = socket.getdefaulttimeout()
            socket.setdefaulttimeout(0.8)
            host, _, _ = socket.gethostbyaddr(clean)
            socket.setdefaulttimeout(orig_timeout)
            if host and host != clean:
                resolved = host
        except Exception:
            pass

        if not resolved:
            resolved = clean

        with self._lock:
            self._rdns_cache[clean] = resolved
        return resolved

    def analyze(
        self,
        remote_str: str,
        geo_summary: str = "",
        upload_audit: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Classifies destination into domain, org, trust level, badge, and recommendation."""
        remote_str = str(remote_str or "").strip()
        r_ip = remote_str
        r_port = 0
        if ":" in remote_str and not remote_str.count(":") > 1:
            parts = remote_str.rsplit(":", 1)
            r_ip = parts[0].strip("[]")
            try:
                r_port = int(parts[1])
            except ValueError:
                pass

        # Resolve domain
        domain = self.resolve_domain(r_ip)
        domain_lower = domain.lower()

        # Query Geo & ISP info if available
        geo_data = {}
        if self.geo_resolver and r_ip and not is_private_ip(r_ip):
            geo_data = self.geo_resolver.get_geo(r_ip)

        isp_org = (geo_data.get("isp") or geo_data.get("org") or "").strip()
        country = geo_data.get("country", "")
        city = geo_data.get("city", "")

        org_lower = (isp_org + " " + geo_summary).lower()

        # 1. Detect Apple Official Services
        is_apple = (
            r_ip.startswith("17.")
            or any(s in domain_lower for s in ("apple.com", "icloud.com", "mzstatic.com", "aaplimg.com", "apple-dns.net"))
            or ("apple" in org_lower and "pineapple" not in org_lower)
        )
        if is_apple:
            target_domain = domain if ("apple" in domain_lower or "icloud" in domain_lower) else "gateway.icloud.com / apple.com"
            target_org = "Apple Inc. (苹果公司官方网络)"
            trust_level = "OFFICIAL_TRUSTED"
            trust_badge = "🟢 Apple 官方认证服务节点 (安全受信任)"
            trust_advice = (
                "上传目的地为 Apple 官方认证服务器 (apple.com / icloud.com)。"
                "检测到的 Token、Cookie 或账号配置属于苹果生态正常的身份认证与系统同步，"
                "受端到端加密保护，通常无需拦截。建议：允许放行 (SIGCONT)。"
            )
            return {
                "remote_endpoint": remote_str,
                "target_ip": r_ip,
                "target_port": r_port,
                "target_domain": target_domain,
                "target_org": target_org,
                "trust_level": trust_level,
                "trust_badge": trust_badge,
                "trust_advice": trust_advice,
                "is_official": True,
                "destination_summary": f"{target_domain} ({target_org})",
            }

        # 2. Detect Microsoft / GitHub
        is_ms_gh = (
            any(s in domain_lower for s in ("github.com", "githubusercontent.com", "microsoft.com", "azure.com", "live.com", "windows.net"))
            or "github" in org_lower or "microsoft" in org_lower
        )
        if is_ms_gh:
            target_domain = domain if any(s in domain_lower for s in ("github", "microsoft", "azure")) else "github.com / microsoft.com"
            target_org = "Microsoft / GitHub 官方基础设施"
            trust_level = "OFFICIAL_TRUSTED"
            trust_badge = "🟢 GitHub / 微软官方认证节点 (安全受信任)"
            trust_advice = (
                "上传目的地为 GitHub 或微软官方服务器。若为代码拉取推送、GitHub Copilot、"
                "VS Code 插件同步或 Azure 认证请求，属于预期业务通信。建议：核对应用后允许放行。"
            )
            return {
                "remote_endpoint": remote_str,
                "target_ip": r_ip,
                "target_port": r_port,
                "target_domain": target_domain,
                "target_org": target_org,
                "trust_level": trust_level,
                "trust_badge": trust_badge,
                "trust_advice": trust_advice,
                "is_official": True,
                "destination_summary": f"{target_domain} ({target_org})",
            }

        # 3. Detect Google
        is_google = (
            any(s in domain_lower for s in ("google.com", "googleapis.com", "gstatic.com", "1e100.net", "googleusercontent.com"))
            or "google" in org_lower
        )
        if is_google:
            target_domain = domain if "google" in domain_lower else "google.com / googleapis.com"
            target_org = "Google LLC (谷歌官方网络)"
            trust_level = "OFFICIAL_TRUSTED"
            trust_badge = "🟢 Google 官方认证服务节点 (安全受信任)"
            trust_advice = "上传目的地为 Google 官方认证服务器。若为 Google 账号登录、API 调用或 Chrome 同步，属于官方服务通信。建议：允许放行。"
            return {
                "remote_endpoint": remote_str,
                "target_ip": r_ip,
                "target_port": r_port,
                "target_domain": target_domain,
                "target_org": target_org,
                "trust_level": trust_level,
                "trust_badge": trust_badge,
                "trust_advice": trust_advice,
                "is_official": True,
                "destination_summary": f"{target_domain} ({target_org})",
            }

        # 4. Detect OpenAI / Anthropic
        is_ai_platform = (
            any(s in domain_lower for s in ("openai.com", "chatgpt.com", "oaistatic.com", "anthropic.com", "claude.ai"))
            or "openai" in org_lower or "anthropic" in org_lower
        )
        if is_ai_platform:
            target_domain = domain if any(s in domain_lower for s in ("openai", "anthropic", "chatgpt", "claude")) else "api.openai.com / api.anthropic.com"
            target_org = "OpenAI / Anthropic 官方 AI 平台"
            trust_level = "OFFICIAL_TRUSTED"
            trust_badge = "🟢 官方主流 AI 平台节点 (安全受信任)"
            trust_advice = "上传目的地为 OpenAI 或 Anthropic 官方模型 API 接口。若为当前本地模型网关转发或客户端提示词请求，属于预期业务流量。建议：允许放行。"
            return {
                "remote_endpoint": remote_str,
                "target_ip": r_ip,
                "target_port": r_port,
                "target_domain": target_domain,
                "target_org": target_org,
                "trust_level": trust_level,
                "trust_badge": trust_badge,
                "trust_advice": trust_advice,
                "is_official": True,
                "destination_summary": f"{target_domain} ({target_org})",
            }

        # 5. Detect Public Cloud / CDN
        is_cloud = (
            any(s in domain_lower for s in ("cloudflare", "amazonaws.com", "aliyun", "alibaba", "tencent", "qcloud", "fastly", "akamai", "digitalocean"))
            or any(s in org_lower for s in ("cloudflare", "amazon", "aws", "aliyun", "alibaba", "tencent", "fastly", "akamai", "digitalocean", "linode"))
        )
        if is_cloud:
            target_domain = domain
            target_org = isp_org or "公有云 / CDN 托管服务商"
            trust_level = "PUBLIC_CLOUD"
            trust_badge = "🟡 公有云 / 基础设施托管节点 (需核对应用)"
            trust_advice = "上传目的地属于公共云服务商或 CDN 节点。请核对当前正在运行的应用或脚本是否合法需要向该云端发送数据。如属未知脚本外发，建议选择阻断并核实。"
            return {
                "remote_endpoint": remote_str,
                "target_ip": r_ip,
                "target_port": r_port,
                "target_domain": target_domain,
                "target_org": target_org,
                "trust_level": trust_level,
                "trust_badge": trust_badge,
                "trust_advice": trust_advice,
                "is_official": False,
                "destination_summary": f"{target_domain} ({target_org})",
            }

        # 6. Fallback: Suspicious / Unknown
        target_domain = domain
        target_org = isp_org or (f"{country} {city}".strip() if country else "未知公网 / 自建节点")
        trust_level = "SUSPICIOUS"
        trust_badge = "🔴 未知外部公网 / 高危自建节点 (严重风险)"
        trust_advice = "上传目的地为非官方未知公网主机，且当前进程正在尝试外发本地敏感凭证、私钥或配置！存在极高数据泄露或恶意回连风险。强烈建议：立即拒绝并终止进程 (Kill)！"
        return {
            "remote_endpoint": remote_str,
            "target_ip": r_ip,
            "target_port": r_port,
            "target_domain": target_domain,
            "target_org": target_org,
            "trust_level": trust_level,
            "trust_badge": trust_badge,
            "trust_advice": trust_advice,
            "is_official": False,
            "destination_summary": f"{target_domain} ({target_org})",
        }


# ─────────────────────────────────────────────────────────────────────────────
# Process Traffic Tracker (nettop on macOS)
# ─────────────────────────────────────────────────────────────────────────────

class ProcessTrafficTracker:
    """Tracks per-process exact upload/download bytes and bandwidth history wave."""

    def __init__(self):
        self.last_poll: float = 0.0
        self.proc_traffic: Dict[int, Dict[str, Any]] = {}
        self.history: collections.deque[Dict[str, Any]] = collections.deque(maxlen=40)
        self.total_uploaded: int = 0
        self.total_downloaded: int = 0
        self._lock = threading.Lock()

    def poll(self, iface_in_speed: float = 0.0, iface_out_speed: float = 0.0):
        now = time.monotonic()
        with self._lock:
            if self.last_poll > 0 and (now - self.last_poll) < 0.35:
                return
            try:
                out = subprocess.check_output(
                    ["nettop", "-P", "-l", "1", "-x", "-n"],
                    text=True,
                    errors="replace",
                    stderr=subprocess.DEVNULL,
                    timeout=1.8,
                )
            except Exception:
                return

            dt = now - self.last_poll if self.last_poll > 0 else 1.0
            self.last_poll = now
            total_in_delta = 0
            total_out_delta = 0

            for line in out.splitlines()[1:]:
                # Match: <timestamp> <process name possibly with spaces>.<pid> <bytes_in> <bytes_out> ...
                m = re.match(r"^\S+\s+(.+?)\.(\d+)\s+(\d+)\s+(\d+)", line)
                if m:
                    name = m.group(1).strip()
                    pid = int(m.group(2))
                    b_in = int(m.group(3))
                    b_out = int(m.group(4))
                    prev = self.proc_traffic.get(pid)
                    if prev:
                        d_in = max(0, b_in - prev["bytes_in"])
                        d_out = max(0, b_out - prev["bytes_out"])
                        in_spd = d_in / dt if dt > 0 else 0.0
                        out_spd = d_out / dt if dt > 0 else 0.0
                        total_in_delta += d_in
                        total_out_delta += d_out
                    else:
                        in_spd = 0.0
                        out_spd = 0.0

                    self.proc_traffic[pid] = {
                        "name": name,
                        "bytes_in": b_in,
                        "bytes_out": b_out,
                        "in_speed": in_spd,
                        "out_speed": out_spd,
                    }

            sum_in = sum(p["bytes_in"] for p in self.proc_traffic.values())
            sum_out = sum(p["bytes_out"] for p in self.proc_traffic.values())
            self.total_downloaded = max(self.total_downloaded + total_in_delta, sum_in)
            self.total_uploaded = max(self.total_uploaded + total_out_delta, sum_out)

            cur_out_speed = max(total_out_delta / dt if dt > 0 else 0.0, iface_out_speed)
            cur_in_speed = max(total_in_delta / dt if dt > 0 else 0.0, iface_in_speed)
            self.history.append({
                "timestamp": now,
                "time": time.strftime("%H:%M:%S"),
                "in_speed": round(cur_in_speed, 1),
                "out_speed": round(cur_out_speed, 1),
            })

    def get_proc(self, pid: int) -> Dict[str, Any]:
        return self.proc_traffic.get(pid, {
            "name": "",
            "bytes_in": 0,
            "bytes_out": 0,
            "in_speed": 0.0,
            "out_speed": 0.0,
        })


# ─────────────────────────────────────────────────────────────────────────────
# Process Network Rate Limiter (Bandwidth Throttler)
# ─────────────────────────────────────────────────────────────────────────────

class ProcessRateLimiter:
    """Manages bandwidth speed limits (throttling) for specific processes or applications.
    Uses precise duty-cycle pulse regulation (SIGSTOP/SIGCONT) to cap network throughput.
    Persisted in ~/.cache/serafina/process_rate_limits.json.
    """
    def __init__(self, filepath: Optional[str] = None):
        self.filepath = filepath or os.path.expanduser("~/.cache/serafina/process_rate_limits.json")
        try:
            os.makedirs(os.path.dirname(self.filepath), exist_ok=True)
        except Exception:
            pass
        self._lock = threading.Lock()
        self.limits: Dict[str, Dict[str, Any]] = {}  # key -> {pid, name, process_name, limit_kb_s, limit_formatted, added_at, enabled}
        self.sentinel = None
        self._load()
        self._running = True
        self._thread = threading.Thread(target=self._throttle_loop, daemon=True)
        self._thread.start()

    def _load(self):
        with self._lock:
            if os.path.exists(self.filepath):
                try:
                    with open(self.filepath, "r", encoding="utf-8") as f:
                        self.limits = json.load(f)
                except Exception:
                    self.limits = {}
            else:
                self.limits = {}

    def _save(self):
        try:
            with open(self.filepath, "w", encoding="utf-8") as f:
                json.dump(self.limits, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def set_rate_limit(self, pid: int = 0, process_name: str = "", limit_kb_s: float = 0.0, name: str = "") -> Dict[str, Any]:
        """Sets or removes a bandwidth rate limit in KB/s. If limit_kb_s <= 0, limit is removed (unlimited)."""
        with self._lock:
            p_name = (process_name or name or "").strip()
            key = str(pid) if pid > 0 else p_name.lower()
            if not key or key == "0":
                return {"ok": False, "error": "无效的进程 PID 或名称"}

            # If limit <= 0, remove the restriction
            if limit_kb_s <= 0:
                removed = False
                if key in self.limits:
                    del self.limits[key]
                    removed = True
                for k, v in list(self.limits.items()):
                    if pid > 0 and v.get("pid") == pid:
                        del self.limits[k]
                        removed = True
                    elif p_name and v.get("name", "").lower() == p_name.lower():
                        del self.limits[k]
                        removed = True
                if removed:
                    self._save()
                target_desc = f"{p_name} (PID {pid})" if (p_name and pid > 0) else (p_name or f"PID {pid}")
                return {
                    "ok": True,
                    "action": "unlimited",
                    "pid": pid,
                    "limit_kb_s": 0.0,
                    "limit_formatted": "不限速",
                    "message": f"🚫 已解除 {target_desc} 的网速限制，恢复全速传输。"
                }

            limit_val = round(limit_kb_s, 1)
            fmt = f"{limit_val:.0f} KB/s" if limit_val < 1024 else f"{(limit_val/1024.0):.1f} MB/s"
            disp_name = p_name or f"PID {pid}"

            entry = {
                "pid": pid,
                "process_name": p_name,
                "name": disp_name,
                "limit_kb_s": limit_val,
                "limit_formatted": fmt,
                "added_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "enabled": True,
            }
            self.limits[key] = entry
            self._save()

            target_desc = f"{disp_name} (PID {pid})" if pid > 0 else disp_name
            return {
                "ok": True,
                "action": "throttled",
                "pid": pid,
                "limit_kb_s": limit_val,
                "limit_formatted": fmt,
                "message": f"⚡️ 已成功将 {target_desc} 网速限制为 {fmt}。"
            }

    def get_rate_limit_for_pid(self, pid: int, cmd: str = "") -> Optional[Dict[str, Any]]:
        with self._lock:
            if pid > 0 and str(pid) in self.limits:
                return self.limits[str(pid)]
            cmd_l = (cmd or "").strip().lower()
            if cmd_l and cmd_l in self.limits:
                return self.limits[cmd_l]
            base = os.path.basename(cmd_l)
            if base and base in self.limits:
                return self.limits[base]
            return None

    def list_limits(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self.limits.values())

    def _throttle_loop(self):
        """High-frequency regulation loop for processes that exceed their allotted bandwidth."""
        while self._running:
            time.sleep(0.18)
            with self._lock:
                active_entries = [e for e in self.limits.values() if e.get("enabled")]

            if not active_entries:
                continue

            for entry in active_entries:
                pid = entry.get("pid", 0)
                limit_kb = entry.get("limit_kb_s", 0.0)
                pname = entry.get("process_name", "").lower()

                target_pids = [pid] if pid > 1 else []
                if not target_pids and pname and self.sentinel:
                    try:
                        out = subprocess.check_output(["pgrep", "-f", pname], text=True, stderr=subprocess.DEVNULL)
                        for line in out.splitlines():
                            try:
                                p = int(line.strip())
                                if p > 1 and p != os.getpid():
                                    target_pids.append(p)
                            except ValueError:
                                pass
                    except Exception:
                        pass

                for tpid in target_pids:
                    try:
                        os.kill(tpid, 0)
                    except OSError:
                        continue

                    if not self.sentinel or not hasattr(self.sentinel, "traffic_tracker"):
                        continue

                    proc_info = self.sentinel.traffic_tracker.get_proc(tpid)
                    cur_speed_bps = max(proc_info.get("out_speed", 0.0), proc_info.get("in_speed", 0.0))
                    cur_speed_kb = cur_speed_bps / 1024.0

                    if cur_speed_kb > limit_kb:
                        excess = min(cur_speed_kb / limit_kb, 5.0)
                        pause_s = min(0.08, 0.02 * excess)
                        try:
                            os.kill(tpid, signal.SIGSTOP)
                            time.sleep(pause_s)
                            os.kill(tpid, signal.SIGCONT)
                        except Exception:
                            pass


# ─────────────────────────────────────────────────────────────────────────────
# Upload Payload Inspector (Inspects open files & content types)
# ─────────────────────────────────────────────────────────────────────────────

class UploadPayloadInspector:
    """Inspects what kind of data is being uploaded by a process:
    images, documents/archives, text/code/logs, or sensitive credentials."""

    def __init__(self):
        self._cache: Dict[int, Tuple[float, Dict[str, Any]]] = {}

    def inspect(self, pid: int, proc_traffic: Optional[Dict[str, Any]] = None, inspect_files: bool = True) -> Dict[str, Any]:
        if pid <= 1:
            return {
                "category": "系统服务",
                "badge": "⚙️ 系统",
                "sensitive": False,
                "open_files": [],
                "open_files_count": 0,
                "upload_bytes": 0,
                "upload_formatted": "0 B",
                "download_bytes": 0,
                "download_formatted": "0 B",
                "upload_speed_formatted": "0 B/s",
                "download_speed_formatted": "0 B/s",
            }

        now = time.monotonic()
        cached = self._cache.get(pid)
        if cached and (now - cached[0] < 10.0):
            res = dict(cached[1])
            if proc_traffic:
                self._enrich_traffic(res, proc_traffic)
            return res

        images: List[str] = []
        texts: List[str] = []
        docs: List[str] = []
        sensitive: List[str] = []

        if inspect_files:
            try:
                out = subprocess.check_output(
                    ["lsof", "-p", str(pid), "-Fn"],
                    text=True,
                    errors="replace",
                    stderr=subprocess.DEVNULL,
                    timeout=0.6,
                )
                for line in out.splitlines():
                    if not line.startswith("n/"):
                        continue
                    filepath = line[1:].strip()
                    f_lower = filepath.lower()
                    if any(ign in f_lower for ign in ["/system/library", "/usr/lib", "/system/volumes", ".dylib", ".so", "frameworks"]):
                        continue
                    base = os.path.basename(filepath)
                    _, ext = os.path.splitext(base.lower())

                    if any(s in f_lower for s in SENSITIVE_PATTERNS):
                        sensitive.append(filepath)
                    elif ext in IMAGE_EXTENSIONS:
                        images.append(filepath)
                    elif ext in DOC_EXTENSIONS:
                        docs.append(filepath)
                    elif ext in TEXT_EXTENSIONS:
                        texts.append(filepath)
            except Exception:
                pass

        if sensitive:
            category = "🚨 敏感凭据/隐私文件"
            badge = "🚨 敏感凭证"
            is_sensitive = True
            files_shown = sensitive[:6]
        elif images:
            category = "图片/多媒体"
            badge = "🖼️ 图片数据"
            is_sensitive = False
            files_shown = images[:6]
        elif docs:
            category = "文档/归档压缩包"
            badge = "📦 文件数据"
            is_sensitive = False
            files_shown = docs[:6]
        elif texts:
            category = "文本/代码/配置"
            badge = "📝 文本数据"
            is_sensitive = False
            files_shown = texts[:6]
        else:
            category = "网络数据流/API请求"
            badge = "🌐 网络数据流"
            is_sensitive = False
            files_shown = []

        total_files = len(sensitive) + len(images) + len(docs) + len(texts)

        res = {
            "category": category,
            "badge": badge,
            "sensitive": is_sensitive,
            "open_files": files_shown,
            "open_files_count": total_files,
            "upload_bytes": 0,
            "upload_formatted": "0 B",
            "download_bytes": 0,
            "download_formatted": "0 B",
            "upload_speed_formatted": "0 B/s",
            "download_speed_formatted": "0 B/s",
        }

        self._cache[pid] = (now, dict(res))
        if proc_traffic:
            self._enrich_traffic(res, proc_traffic)
        return res

    def _enrich_traffic(self, res: Dict[str, Any], proc_traffic: Dict[str, Any]):
        u_bytes = proc_traffic.get("bytes_out", 0)
        d_bytes = proc_traffic.get("bytes_in", 0)
        u_spd = proc_traffic.get("out_speed", 0.0)
        d_spd = proc_traffic.get("in_speed", 0.0)
        res["upload_bytes"] = u_bytes
        res["upload_formatted"] = format_bytes(u_bytes, per_sec=False)
        res["download_bytes"] = d_bytes
        res["download_formatted"] = format_bytes(d_bytes, per_sec=False)
        res["upload_speed_bps"] = u_spd
        res["upload_speed_formatted"] = format_bytes(u_spd, per_sec=True)
        res["download_speed_bps"] = d_spd
        res["download_speed_formatted"] = format_bytes(d_spd, per_sec=True)


# ─────────────────────────────────────────────────────────────────────────────
# Alerts & Sentinel
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class NetworkAlert:
    id: str
    severity: str  # "CRITICAL", "WARNING", "INFO"
    title: str
    detail: str
    pid: Optional[int]
    process_name: str
    remote: str
    timestamp: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["time_str"] = time.strftime("%H:%M:%S", time.localtime(self.timestamp))
        return d



class GatekeeperWhitelist:
    """Manages persistent parent process whitelist for Gatekeeper Intercept.
    When a parent process is whitelisted, any child processes spawned by it
    (or matching its executable name/path) are automatically trusted and
    will not trigger SIGSTOP freeze or popup alerts.
    Persisted in ~/.cache/serafina/gatekeeper_whitelist.json.
    """
    def __init__(self, filepath: Optional[str] = None):
        self.filepath = filepath or os.path.expanduser("~/.cache/serafina/gatekeeper_whitelist.json")
        try:
            os.makedirs(os.path.dirname(self.filepath), exist_ok=True)
        except Exception:
            pass
        self._lock = threading.Lock()
        self.entries: Dict[str, Dict[str, Any]] = {}
        self._load()

    def _normalize(self, name: str) -> str:
        if not name:
            return ""
        s = name.strip()
        # If it's a file path, extract the basename
        if "/" in s and not (" / " in s):
            s = os.path.basename(s)
        # Remove description like " (macOS 系统核心守护进程)"
        if " (" in s and s.endswith(")"):
            s = s[:s.find(" (")].strip()
        return s.lower()

    def _load(self):
        with self._lock:
            if os.path.exists(self.filepath):
                try:
                    with open(self.filepath, "r", encoding="utf-8") as f:
                        self.entries = json.load(f)
                except Exception:
                    self.entries = {}
            else:
                self.entries = {}

    def _save(self):
        try:
            with open(self.filepath, "w", encoding="utf-8") as f:
                json.dump(self.entries, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def add_parent(self, parent_name: str, parent_path: str = "", reason: str = "用户在弹窗中授权信任") -> Dict[str, Any]:
        with self._lock:
            key = self._normalize(parent_name)
            if not key:
                return {"ok": False, "error": "父进程名称为空"}
            entry = {
                "parent_name": parent_name.strip(),
                "normalized_name": key,
                "parent_path": parent_path.strip(),
                "added_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "reason": reason,
            }
            self.entries[key] = entry
            # If parent_name contains slash separators like "zsh / CodexAgent", index each component
            if " / " in parent_name:
                for part in parent_name.split(" / "):
                    pkey = self._normalize(part)
                    if pkey:
                        self.entries[pkey] = dict(entry, parent_name=part.strip(), normalized_name=pkey)
            self._save()
            return {"ok": True, "entry": entry, "count": len(self.entries)}

    def remove_parent(self, parent_name: str) -> bool:
        with self._lock:
            key = self._normalize(parent_name)
            removed = False
            if key in self.entries:
                del self.entries[key]
                removed = True
            for k in list(self.entries.keys()):
                if self.entries[k].get("parent_name") == parent_name or self.entries[k].get("normalized_name") == key:
                    del self.entries[k]
                    removed = True
            if removed:
                self._save()
            return removed

    def clear(self):
        with self._lock:
            self.entries.clear()
            self._save()

    def is_parent_whitelisted(self, parent_name: str, parent_path: str = "") -> bool:
        if not parent_name and not parent_path:
            return False
        with self._lock:
            norm_name = self._normalize(parent_name)
            norm_path = self._normalize(parent_path)

            if norm_name and norm_name in self.entries:
                return True
            if norm_path and norm_path in self.entries:
                return True

            for key in self.entries:
                if not key:
                    continue
                if norm_name and (key == norm_name or (len(key) >= 3 and (key in norm_name or norm_name in key))):
                    return True
                if norm_path and (key == norm_path or key in norm_path):
                    return True
        return False

    def list_whitelisted(self) -> List[Dict[str, Any]]:
        with self._lock:
            seen = set()
            res = []
            for item in self.entries.values():
                pname = item.get("parent_name", "")
                if pname not in seen:
                    seen.add(pname)
                    res.append(item)
            return res


class NetworkSentinel:
    """macOS Native Network & Traffic Anomaly Auditor."""

    def __init__(self, max_alerts: int = 100):
        self.max_alerts = max_alerts
        self.alerts: collections.deque[NetworkAlert] = collections.deque(maxlen=max_alerts)
        self.last_netstat_time: float = 0.0
        self.last_ibytes: int = 0
        self.last_obytes: int = 0
        self.cached_speed_in: float = 0.0
        self.cached_speed_out: float = 0.0
        self._cached_connections: List[Dict[str, Any]] = []
        self._cached_scan_result: Optional[Dict[str, Any]] = None
        self._cached_scan_time: float = 0.0
        self._scan_lock = threading.Lock()
        self._proc_mem_kb: Dict[int, int] = {}
        self._proc_cpu: Dict[int, float] = {}
        self.pending_gatekeeper_events: Dict[str, Dict[str, Any]] = {}
        self.allowed_gatekeeper_whitelist: Dict[str, float] = {}
        self.gatekeeper_whitelist = GatekeeperWhitelist()
        self.rate_limiter = ProcessRateLimiter()
        self.rate_limiter.sentinel = self
        self._simulated_pids: List[int] = []

        # Subsystems
        self.geo_resolver = IPGeoResolver()
        self.destination_analyzer = DestinationAnalyzer(self.geo_resolver)
        self.traffic_tracker = ProcessTrafficTracker()
        self.payload_inspector = UploadPayloadInspector()

        # Start continuous background traffic & waveform sampler
        self._bg_thread = threading.Thread(target=self._bg_traffic_loop, daemon=True)
        self._bg_thread.start()

    def _bg_traffic_loop(self):
        """Continuously samples bandwidth, per-process traffic, and full socket audit in background."""
        try:
            s_in, s_out = self.update_bandwidth()
            self.traffic_tracker.poll(s_in, s_out)
            time.sleep(0.5)
            res = self._perform_scan()
            if res.get("ok"):
                self._cached_scan_result = res
                self._cached_scan_time = time.monotonic()
        except Exception:
            pass
        while True:
            time.sleep(2.5)
            try:
                res = self._perform_scan()
                if res.get("ok"):
                    self._cached_scan_result = res
                    self._cached_scan_time = time.monotonic()
            except Exception:
                pass

    def _get_interface_counters(self) -> Tuple[int, int]:
        """Polls netstat -ib on macOS to sum raw network device transfer bytes across physical & tunnel interfaces."""
        try:
            out = subprocess.check_output(
                ["netstat", "-ib"], text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=2.0
            )
            in_bytes, out_bytes = 0, 0
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 10 and "<Link#" in parts[2]:
                    iface = parts[0]
                    # Sum physical (en*), VPN/proxy tunnel (utun*, ipsec*, ppp*, tap*, tun*), and wireless/bridge
                    if iface.startswith(("en", "utun", "awdl", "bridge", "ipsec", "ppp", "tun", "tap")):
                        try:
                            # In netstat -ib, when Address (col 3) is present (11 cols), Ibytes=6, Obytes=9.
                            # When Address is empty (10 cols, e.g. utun*), Ibytes=5, Obytes=8.
                            if len(parts) >= 11:
                                in_bytes += int(parts[6])
                                out_bytes += int(parts[9])
                            else:
                                in_bytes += int(parts[5])
                                out_bytes += int(parts[8])
                        except (ValueError, IndexError):
                            pass
            return in_bytes, out_bytes
        except Exception:
            return 0, 0

    def update_bandwidth(self) -> Tuple[float, float]:
        """Calculates current in/out bytes/sec bandwidth."""
        now = time.monotonic()
        curr_in, curr_out = self._get_interface_counters()
        if self.last_netstat_time > 0 and now > self.last_netstat_time:
            dt = now - self.last_netstat_time
            if dt > 0.25:
                delta_in = max(0, curr_in - self.last_ibytes)
                delta_out = max(0, curr_out - self.last_obytes)
                self.cached_speed_in = delta_in / dt
                self.cached_speed_out = delta_out / dt
                self.last_netstat_time = now
                self.last_ibytes = curr_in
                self.last_obytes = curr_out
        else:
            self.last_netstat_time = now
            self.last_ibytes = curr_in
            self.last_obytes = curr_out
        return self.cached_speed_in, self.cached_speed_out

    def _get_process_path(self, pid: int) -> str:
        """Retrieves process executable path using ps."""
        try:
            out = subprocess.check_output(
                ["ps", "-p", str(pid), "-o", "comm="],
                text=True,
                errors="replace",
                stderr=subprocess.DEVNULL,
                timeout=1.0,
            )
            return out.strip().split()[0] if out.strip() else ""
        except Exception:
            return ""

    def _batch_load_process_tree(self) -> Tuple[Dict[int, str], Dict[int, int], Dict[int, List[Dict[str, Any]]]]:
        """Loads all processes, their parent PIDs, CPU, RSS memory, binary names, and children in a single batch call."""
        paths: Dict[int, str] = {}
        ppid_map: Dict[int, int] = {}
        mem_map: Dict[int, int] = {}
        cpu_map: Dict[int, float] = {}
        children_map: Dict[int, List[Dict[str, Any]]] = collections.defaultdict(list)
        try:
            out = subprocess.check_output(
                ["ps", "-eo", "pid,ppid,%cpu,rss,comm"],
                text=True,
                errors="replace",
                stderr=subprocess.DEVNULL,
                timeout=1.5,
            )
            for line in out.splitlines()[1:]:
                parts = line.strip().split(None, 4)
                if len(parts) >= 5 and parts[0].isdigit() and parts[1].isdigit():
                    p = int(parts[0])
                    pp = int(parts[1])
                    try:
                        cpu_v = float(parts[2])
                    except ValueError:
                        cpu_v = 0.0
                    try:
                        rss_v = int(parts[3])
                    except ValueError:
                        rss_v = 0
                    comm = parts[4].strip()
                    paths[p] = comm
                    ppid_map[p] = pp
                    mem_map[p] = rss_v
                    cpu_map[p] = cpu_v
                    children_map[pp].append({
                        "pid": p,
                        "ppid": pp,
                        "command": os.path.basename(comm),
                        "memory_kb": rss_v,
                        "memory_formatted": format_bytes(rss_v * 1024, per_sec=False),
                        "cpu_percent": round(cpu_v, 1),
                    })
            self._proc_mem_kb = mem_map
            self._proc_cpu = cpu_map
        except Exception:
            pass
        return paths, ppid_map, children_map

    def _get_process_lineage_fast(
        self, pid: int, paths: Dict[int, str], ppid_map: Dict[int, int], children_map: Dict[int, List[Dict[str, Any]]]
    ) -> Dict[str, Any]:
        """Fast in-memory lineage and memory lookup."""
        if pid <= 1:
            return {
                "ppid": 0, "parent_name": "", "children": [], "children_count": 0,
                "tree_str": "", "memory_kb": 0, "memory_formatted": "0 B",
                "family_memory_kb": 0, "family_memory_formatted": "0 B", "cpu_percent": 0.0
            }
        ppid = ppid_map.get(pid, 0)
        pname = os.path.basename(paths.get(ppid, "")) if ppid > 0 else ""
        children = children_map.get(pid, [])
        self_mem_kb = self._proc_mem_kb.get(pid, 0)
        self_cpu = round(self._proc_cpu.get(pid, 0.0), 1)
        fam_mem_kb = self_mem_kb + sum(c.get("memory_kb", 0) for c in children)
        self_mem_fmt = format_bytes(self_mem_kb * 1024, per_sec=False)
        fam_mem_fmt = format_bytes(fam_mem_kb * 1024, per_sec=False)

        p_desc = f"{pname} ({ppid})" if ppid > 1 and pname else "launchd (1)"
        if children:
            ch_preview = ", ".join(f"{c['command']}[PID:{c['pid']} {c.get('memory_formatted', '')}]" for c in children[:3])
            if len(children) > 3:
                ch_preview += f" 等{len(children)}个"
            ch_desc = f" · 子进程 {len(children)}个 ({ch_preview})"
        else:
            ch_desc = ""
        tree_str = f"父: {p_desc} ➔ PID {pid} (🧠 {self_mem_fmt}){ch_desc}"

        return {
            "ppid": ppid,
            "parent_name": pname,
            "children": children,
            "children_count": len(children),
            "tree_str": tree_str,
            "memory_kb": self_mem_kb,
            "memory_formatted": self_mem_fmt,
            "family_memory_kb": fam_mem_kb,
            "family_memory_formatted": fam_mem_fmt,
            "cpu_percent": self_cpu,
        }

    def _get_process_lineage(self, pid: int) -> Dict[str, Any]:
        """Retrieves parent PID, parent name, and children for a process."""
        paths, ppid_map, children_map = self._batch_load_process_tree()
        return self._get_process_lineage_fast(pid, paths, ppid_map, children_map)

    def scan(self, force: bool = False) -> Dict[str, Any]:
        """Returns cached background network scan immediately, or performs a scan if cache is empty/forced."""
        if not force and self._cached_scan_result is not None:
            self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())
            return self._cached_scan_result
        res = self._perform_scan()
        if res.get("ok"):
            self._cached_scan_result = res
            self._cached_scan_time = time.monotonic()
        return res

    def _perform_scan(self) -> Dict[str, Any]:
        """Performs a full audit of all network sockets, processes, traffic, and geo/upload payloads."""
        speed_in, speed_out = self.update_bandwidth()
        self.traffic_tracker.poll(speed_in, speed_out)
        if self.traffic_tracker.history:
            latest = self.traffic_tracker.history[-1]
            speed_in = max(speed_in, float(latest.get("in_speed", 0.0)))
            speed_out = max(speed_out, float(latest.get("out_speed", 0.0)))

        pid_paths, ppid_map, children_map = self._batch_load_process_tree()

        try:
            lsof_out = subprocess.check_output(
                ["lsof", "-n", "-P", "-iTCP", "-iUDP"],
                text=True,
                errors="replace",
                stderr=subprocess.DEVNULL,
                timeout=4.0,
            )
        except Exception as exc:
            return {
                "ok": False,
                "error": str(exc),
                "timestamp": time.time(),
            }

        connections: List[Dict[str, Any]] = []
        listening_ports: List[Dict[str, Any]] = []
        alerts_found: List[NetworkAlert] = []

        seen_sockets: Set[str] = set()
        lineage_cache: Dict[int, Dict[str, Any]] = {}
        payload_cache: Dict[int, Dict[str, Any]] = {}

        raw_entries = []
        for line in lsof_out.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 9:
                continue
            cmd = parts[0].replace("\\x20", " ")
            try:
                pid = int(parts[1])
            except ValueError:
                continue
            user = parts[2]
            proto = parts[4]
            name_part = " ".join(parts[8:])
            raw_entries.append((cmd, pid, user, proto, name_part))

        total_conns = 0
        outbound_public_count = 0
        exposed_public_ports_count = 0

        # Upload breakdown counts
        cat_counts = {"images": 0, "texts": 0, "files": 0, "sensitive": 0, "api": 0}

        for raw_cmd, pid, user, proto, name_part in raw_entries:
            key = f"{pid}:{proto}:{name_part}"
            if key in seen_sockets:
                continue
            seen_sockets.add(key)
            total_conns += 1

            proc_path = pid_paths.get(pid) or ""
            # Use clean process binary/app name when available instead of lsof's 9-char truncated name
            cmd = os.path.basename(proc_path) if proc_path else raw_cmd
            if not cmd or len(cmd) < len(raw_cmd):
                cmd = raw_cmd

            is_tmp_path = any(proc_path.startswith(p) for p in ("/tmp", "/var/tmp", "/private/tmp", "/Users/Shared"))
            is_deleted_binary = "(deleted)" in proc_path

            # 1. Listening ports
            if "LISTEN" in name_part:
                addr_only = name_part.split("(", 1)[0].strip()
                if ":" in addr_only:
                    bind_ip, port_s = addr_only.rsplit(":", 1)
                    if port_s.isdigit():
                        port = int(port_s)
                        is_exposed = bind_ip in ("*", "0.0.0.0", "::", "[::]")
                        if is_exposed:
                            exposed_public_ports_count += 1

                        risk = "NORMAL"
                        risk_desc = "本地监听服务"

                        if is_exposed and port in SENSITIVE_SERVICE_PORTS:
                            risk = "CRITICAL"
                            risk_desc = f"公网暴露敏感服务: {SENSITIVE_SERVICE_PORTS[port]}"
                            alerts_found.append(
                                NetworkAlert(
                                    id=f"sens_port_{pid}_{port}",
                                    severity="CRITICAL",
                                    title="敏感服务全网开放暴露",
                                    detail=f"进程 {cmd} (PID {pid}) 在公网网卡开放了敏感端口 {port} ({SENSITIVE_SERVICE_PORTS[port]})，极易遭到未授权攻击！",
                                    pid=pid,
                                    process_name=cmd,
                                    remote=f"0.0.0.0:{port}",
                                )
                            )
                        elif port in MALICIOUS_PORTS:
                            risk = "CRITICAL"
                            risk_desc = f"危险高危端口监听: {MALICIOUS_PORTS[port]}"
                            alerts_found.append(
                                NetworkAlert(
                                    id=f"mal_port_{pid}_{port}",
                                    severity="CRITICAL",
                                    title="检测到可疑后门端口监听",
                                    detail=f"进程 {cmd} (PID {pid}) 正在监听常见木马/后门端口 {port} ({MALICIOUS_PORTS[port]})！",
                                    pid=pid,
                                    process_name=cmd,
                                    remote=f"*:{port}",
                                )
                            )
                        elif is_tmp_path and is_exposed:
                            risk = "CRITICAL"
                            risk_desc = "临时目录未知进程开放监听"
                            alerts_found.append(
                                NetworkAlert(
                                    id=f"tmp_listen_{pid}_{port}",
                                    severity="CRITICAL",
                                    title="临时目录进程异常监听",
                                    detail=f"位于临时目录的可执行文件 {proc_path} (PID {pid}) 正在开放端口 {port}！",
                                    pid=pid,
                                    process_name=cmd,
                                    remote=f"*:{port}",
                                )
                            )
                        elif is_exposed and port not in (80, 443, 7000, 5000, 22, 8000, 8002, 7777, 1234):
                            risk = "WARNING"
                            risk_desc = f"开放公网监听 (端口 {port})"

                        listening_ports.append({
                            "command": cmd,
                            "pid": pid,
                            "proto": proto,
                            "bind": bind_ip,
                            "port": port,
                            "is_exposed": is_exposed,
                            "path": proc_path,
                            "risk": risk,
                            "risk_desc": risk_desc,
                        })
                continue

            # 2. Established / Outbound connections (supports both IPv4 and IPv6)
            if "->" in name_part:
                left_part, right_part = name_part.split("->", 1)
                state = "ESTABLISHED"
                if "(" in right_part:
                    right_part, state_raw = right_part.split("(", 1)
                    state = state_raw.strip("() ")
                left_part = left_part.strip()
                right_part = right_part.strip()
                if ":" not in left_part or ":" not in right_part:
                    continue
                l_ip, l_port_s = left_part.rsplit(":", 1)
                r_ip_raw, r_port_s = right_part.rsplit(":", 1)
                if not l_port_s.isdigit() or not r_port_s.isdigit():
                    continue
                l_port = int(l_port_s)
                r_port = int(r_port_s)
                r_ip = r_ip_raw.strip("[]")
                is_outbound_public = not is_private_ip(r_ip)

                if is_outbound_public:
                    outbound_public_count += 1

                risk = "NORMAL"
                risk_desc = "常规内网/本地连接" if not is_outbound_public else "正常外网连接"

                if is_outbound_public:
                    if r_port in MALICIOUS_PORTS:
                        risk = "CRITICAL"
                        risk_desc = f"外联高危木马/C2端口: {MALICIOUS_PORTS[r_port]}"
                        alerts_found.append(
                            NetworkAlert(
                                id=f"c2_conn_{pid}_{r_port}",
                                severity="CRITICAL",
                                title="检测到外联高危 C2 / 后门端口",
                                detail=f"进程 {cmd} (PID {pid}) 正在连接公网目标 {r_ip}:{r_port} ({MALICIOUS_PORTS[r_port]})！",
                                pid=pid,
                                process_name=cmd,
                                remote=f"{r_ip}:{r_port}",
                            )
                        )
                    elif is_tmp_path or is_deleted_binary:
                        risk = "CRITICAL"
                        risk_desc = "临时目录/被删除二进制进程外联外网"
                        alerts_found.append(
                            NetworkAlert(
                                id=f"tmp_outbound_{pid}_{r_port}",
                                severity="CRITICAL",
                                title="可疑路径进程访问外网",
                                detail=f"位于 {proc_path} 的进程 (PID {pid}) 正在外联公网 IP {r_ip}:{r_port}，高度疑似隐蔽木马！",
                                pid=pid,
                                process_name=cmd,
                                remote=f"{r_ip}:{r_port}",
                            )
                        )
                    elif cmd.lower() in SUSPICIOUS_TOOLS:
                        risk = "CRITICAL"
                        risk_desc = f"反弹 Shell 工具外联: {cmd}"
                        alerts_found.append(
                            NetworkAlert(
                                id=f"shell_tool_{pid}_{r_port}",
                                severity="CRITICAL",
                                title="网络瑞士军刀外联警报",
                                detail=f"检测到反弹 Shell 工具 {cmd} (PID {pid}) 正在主动连接公网 {r_ip}:{r_port}！",
                                pid=pid,
                                process_name=cmd,
                                remote=f"{r_ip}:{r_port}",
                            )
                        )
                    elif r_port not in STANDARD_INTERNET_PORTS and r_port > 1024:
                        risk = "WARNING"
                        risk_desc = f"外联非常规公网高位端口 ({r_port})"
                        alerts_found.append(
                            NetworkAlert(
                                id=f"high_port_{pid}_{r_port}",
                                severity="WARNING",
                                title="外联非常规公网端口",
                                detail=f"进程 {cmd} (PID {pid}) 正在外联公网高位端口 {r_ip}:{r_port}，建议核对进程合法性。",
                                pid=pid,
                                process_name=cmd,
                                remote=f"{r_ip}:{r_port}",
                            )
                        )

                lin = lineage_cache.setdefault(
                    pid, self._get_process_lineage_fast(pid, pid_paths, ppid_map, children_map)
                )

                # Geo-location lookup via public API
                geo_info = self.geo_resolver.get_geo(r_ip)

                # Upload payload inspection (cached per PID within scan pass)
                if pid not in payload_cache:
                    p_traffic = self.traffic_tracker.get_proc(pid)
                    should_inspect = is_outbound_public or (p_traffic.get("bytes_out", 0) > 1000)
                    payload_cache[pid] = self.payload_inspector.inspect(pid, p_traffic, inspect_files=should_inspect)
                upload_audit = payload_cache[pid]

                # Tabulate breakdown
                b_cat = upload_audit.get("badge", "")
                if "图片" in b_cat:
                    cat_counts["images"] += 1
                elif "文本" in b_cat:
                    cat_counts["texts"] += 1
                elif "文件" in b_cat:
                    cat_counts["files"] += 1
                elif "敏感" in b_cat:
                    cat_counts["sensitive"] += 1
                else:
                    cat_counts["api"] += 1

                connections.append({
                    "command": cmd,
                    "pid": pid,
                    "proto": proto,
                    "state": state,
                    "local": f"{l_ip}:{l_port}",
                    "remote": f"{r_ip}:{r_port}",
                    "remote_ip": r_ip,
                    "remote_port": r_port,
                    "is_public": is_outbound_public,
                    "path": proc_path,
                    "risk": risk,
                    "risk_desc": risk_desc,
                    "ppid": lin.get("ppid", 0),
                    "parent_name": lin.get("parent_name", ""),
                    "children": lin.get("children", []),
                    "children_count": lin.get("children_count", 0),
                    "tree_str": lin.get("tree_str", ""),
                    "memory_kb": lin.get("memory_kb", 0),
                    "memory_formatted": lin.get("memory_formatted", "0 B"),
                    "family_memory_formatted": lin.get("family_memory_formatted", "0 B"),
                    "cpu_percent": lin.get("cpu_percent", 0.0),
                    "geo": geo_info,
                    "upload_audit": upload_audit,
                })

                # Auto-Gatekeeper Intercept: if sensitive credentials OR CRITICAL high-risk with active upload / outbound public connection
                is_sensitive_upload = ("敏感" in b_cat) and (is_outbound_public or upload_audit.get("upload_bytes", 0) > 0)
                is_critical_upload = (risk == "CRITICAL") and (is_outbound_public or upload_audit.get("upload_bytes", 0) > 0)
                if is_sensitive_upload or is_critical_upload:
                    self._maybe_trigger_gatekeeper(
                        pid=pid,
                        cmd=cmd,
                        proc_path=proc_path,
                        lin=lin,
                        remote=f"{r_ip}:{r_port}",
                        geo_summary=geo_info.get("summary", ""),
                        upload_audit=upload_audit,
                        trigger_type="敏感凭证外发拦截" if is_sensitive_upload else "高危后台流量传输拦截",
                        reason=f"检测到进程 {cmd} (PID {pid}) 正在外联 {r_ip}:{r_port} 并访问敏感凭据: {', '.join(upload_audit.get('open_files', [])[:3])}"
                        if is_sensitive_upload else f"高危外联行为: {risk_desc} -> {r_ip}:{r_port}",
                    )

        self._cached_connections = connections

        # Record alerts in history ring buffer
        for a in alerts_found:
            if not any(old.id == a.id for old in list(self.alerts)[-10:]):
                self.alerts.append(a)

        # Overall risk level
        overall_risk = "SAFE"
        critical_alerts = sum(1 for a in alerts_found if a.severity == "CRITICAL")
        warning_alerts = sum(1 for a in alerts_found if a.severity == "WARNING")
        if critical_alerts > 0 or self.pending_gatekeeper_events:
            overall_risk = "CRITICAL"
        elif warning_alerts > 0:
            overall_risk = "WARNING"

        # Sort: risky ones first, then public ones, then high traffic bytes (upload + download)
        risk_order = {"CRITICAL": 0, "WARNING": 1, "NORMAL": 2}
        connections.sort(
            key=lambda c: (
                risk_order.get(c["risk"], 3),
                not c["is_public"],
                -(c.get("upload_audit", {}).get("upload_bytes", 0) + c.get("upload_audit", {}).get("download_bytes", 0)),
                c["command"]
            )
        )
        listening_ports.sort(key=lambda l: (risk_order.get(l["risk"], 3), not l["is_exposed"], l["port"]))

        # Top uploaders (include both active connections and processes tracked by nettop)
        top_uploaders = []
        seen_uploader_pids: Set[int] = set()
        country_counts: Dict[str, Dict[str, Any]] = collections.defaultdict(lambda: {"count": 0, "flag": "🌐", "country": ""})
        for c in connections:
            if c.get("is_public"):
                g = c.get("geo", {})
                c_name = g.get("country") or "其他公网"
                c_flag = g.get("flag") or "🌐"
                country_counts[c_name]["count"] += 1
                country_counts[c_name]["flag"] = c_flag
                country_counts[c_name]["country"] = c_name

            up_b = c.get("upload_audit", {}).get("upload_bytes", 0)
            down_b = c.get("upload_audit", {}).get("download_bytes", 0)
            if (up_b > 0 or down_b > 0) and c["pid"] not in seen_uploader_pids:
                seen_uploader_pids.add(c["pid"])
                top_uploaders.append({
                    "pid": c["pid"],
                    "ppid": c.get("ppid", 0),
                    "parent_name": c.get("parent_name", ""),
                    "children": c.get("children", []),
                    "tree_str": c.get("tree_str", ""),
                    "memory_kb": c.get("memory_kb", 0),
                    "memory_formatted": c.get("memory_formatted", "0 B"),
                    "family_memory_formatted": c.get("family_memory_formatted", "0 B"),
                    "cpu_percent": c.get("cpu_percent", 0.0),
                    "command": c["command"],
                    "badge": c.get("upload_audit", {}).get("badge", ""),
                    "category": c.get("upload_audit", {}).get("category", ""),
                    "upload_bytes": up_b,
                    "upload_formatted": c.get("upload_audit", {}).get("upload_formatted", ""),
                    "download_bytes": down_b,
                    "download_formatted": c.get("upload_audit", {}).get("download_formatted", ""),
                    "open_files": c.get("upload_audit", {}).get("open_files", []),
                    "geo": c.get("geo", {}).get("summary", ""),
                })

        for t_pid, t_info in list(self.traffic_tracker.proc_traffic.items()):
            if t_pid in seen_uploader_pids or t_pid <= 1:
                continue
            up_b = t_info.get("bytes_out", 0)
            down_b = t_info.get("bytes_in", 0)
            if up_b > 0 or down_b > 0:
                seen_uploader_pids.add(t_pid)
                p_path = pid_paths.get(t_pid) or ""
                p_cmd = os.path.basename(p_path) if p_path else t_info.get("name", f"PID {t_pid}")
                audit = self.payload_inspector.inspect(t_pid, t_info, inspect_files=(up_b > 10000))
                t_lin = lineage_cache.setdefault(
                    t_pid, self._get_process_lineage_fast(t_pid, pid_paths, ppid_map, children_map)
                )
                if "敏感" in audit.get("badge", "") and up_b > 0:
                    self._maybe_trigger_gatekeeper(
                        pid=t_pid,
                        cmd=p_cmd,
                        proc_path=p_path,
                        lin=t_lin,
                        remote="后台外发通道",
                        geo_summary="🌐 活跃后台上传流量",
                        upload_audit=audit,
                        trigger_type="敏感凭证外发拦截",
                        reason=f"后台上传进程 {p_cmd} (PID {t_pid}) 正在读取敏感凭证文件并产生外发流量 ({audit.get('upload_formatted', '')})！",
                    )
                top_uploaders.append({
                    "pid": t_pid,
                    "ppid": t_lin.get("ppid", 0),
                    "parent_name": t_lin.get("parent_name", ""),
                    "children": t_lin.get("children", []),
                    "tree_str": t_lin.get("tree_str", ""),
                    "memory_kb": t_lin.get("memory_kb", 0),
                    "memory_formatted": t_lin.get("memory_formatted", "0 B"),
                    "family_memory_formatted": t_lin.get("family_memory_formatted", "0 B"),
                    "cpu_percent": t_lin.get("cpu_percent", 0.0),
                    "command": p_cmd,
                    "badge": audit.get("badge", "🌐 网络数据流"),
                    "category": audit.get("category", "网络数据流/API请求"),
                    "upload_bytes": up_b,
                    "upload_formatted": audit.get("upload_formatted", "0 B"),
                    "download_bytes": down_b,
                    "download_formatted": audit.get("download_formatted", "0 B"),
                    "open_files": audit.get("open_files", []),
                    "geo": "🌐 历史/UDP活跃流量",
                })

        top_uploaders.sort(key=lambda u: -(u.get("upload_bytes", 0) + u.get("download_bytes", 0)))
        top_countries = sorted(country_counts.values(), key=lambda x: -x["count"])[:8]

        # Attach active rate limits to top_uploaders and connections
        for u in top_uploaders:
            u_pid = u.get("pid", 0)
            u_cmd = u.get("command", "")
            rl = self.rate_limiter.get_rate_limit_for_pid(u_pid, u_cmd)
            if rl:
                u["rate_limit_kb_s"] = rl.get("limit_kb_s", 0.0)
                u["rate_limit_formatted"] = rl.get("limit_formatted", "")
            else:
                u["rate_limit_kb_s"] = 0.0
                u["rate_limit_formatted"] = ""

        for c in connections:
            c_pid = c.get("pid", 0)
            c_cmd = c.get("command", "")
            rl = self.rate_limiter.get_rate_limit_for_pid(c_pid, c_cmd)
            if rl:
                c["rate_limit_kb_s"] = rl.get("limit_kb_s", 0.0)
                c["rate_limit_formatted"] = rl.get("limit_formatted", "")
            else:
                c["rate_limit_kb_s"] = 0.0
                c["rate_limit_formatted"] = ""

        # Prune dead PIDs from pending_gatekeeper_events (except simulated ones still alive)
        for eid, ev in list(self.pending_gatekeeper_events.items()):
            ev_pid = ev.get("pid", 0)
            if ev_pid > 1 and ev_pid not in pid_paths and not ev.get("is_simulated"):
                del self.pending_gatekeeper_events[eid]

        return {
            "ok": True,
            "timestamp": time.time(),
            "time_formatted": time.strftime("%Y-%m-%d %H:%M:%S"),
            "bandwidth": {
                "in_bytes_sec": round(speed_in, 1),
                "out_bytes_sec": round(speed_out, 1),
                "in_formatted": format_bytes(speed_in, per_sec=True),
                "out_formatted": format_bytes(speed_out, per_sec=True),
                "total_uploaded_bytes": self.traffic_tracker.total_uploaded,
                "total_uploaded_formatted": format_bytes(self.traffic_tracker.total_uploaded, per_sec=False),
                "total_downloaded_bytes": self.traffic_tracker.total_downloaded,
                "total_downloaded_formatted": format_bytes(self.traffic_tracker.total_downloaded, per_sec=False),
                "history": list(self.traffic_tracker.history),
            },
            "upload_summary": {
                "categories": cat_counts,
                "top_uploaders": top_uploaders[:15],
                "top_countries": top_countries,
            },
            "summary": {
                "total_sockets": total_conns,
                "active_connections_count": len(connections),
                "outbound_public_count": outbound_public_count,
                "listening_ports_count": len(listening_ports),
                "exposed_public_ports_count": exposed_public_ports_count,
                "critical_count": critical_alerts + len(self.pending_gatekeeper_events),
                "warning_count": warning_alerts,
                "risk_level": overall_risk,
                "active_rate_limits_count": len(self.rate_limiter.list_limits()),
            },
            "pending_gatekeeper_events": list(self.pending_gatekeeper_events.values()),
            "rate_limits": self.rate_limiter.list_limits(),
            "active_alerts": [a.to_dict() for a in alerts_found],
            "recent_alerts": [a.to_dict() for a in reversed(list(self.alerts)[-20:])],
            "connections": connections[:150],
            "listening": listening_ports[:100],
        }

    def _maybe_trigger_gatekeeper(
        self,
        pid: int,
        cmd: str,
        proc_path: str,
        lin: Dict[str, Any],
        remote: str,
        geo_summary: str,
        upload_audit: Dict[str, Any],
        trigger_type: str,
        reason: str,
    ):
        """Freezes (SIGSTOP) a process attempting sensitive credential or high-risk upload until user clicks Allow."""
        if pid <= 1 or pid == os.getpid():
            return
        cmd_l = cmd.lower()
        path_l = (proc_path or "").lower()
        SAFE_DAEMONS = {
            "launchd", "kernel_task", "windowserver", "loginwindow", "finder",
            "mdnsresponder", "trustd", "ocspd", "apsd", "cloudd", "nsurlsessiond",
            "codexmodelswitcher", "secd", "syspolicyd"
        }
        if cmd_l in SAFE_DAEMONS or any(s in path_l for s in ("mtplx-responses-proxy", "codex model switcher", "omlx")):
            return

        # Check parent and command against persistent whitelist
        parent_name = lin.get("parent_name", "")
        parent_path = lin.get("parent_path", "")
        if self.gatekeeper_whitelist.is_parent_whitelisted(parent_name, parent_path):
            return
        if self.gatekeeper_whitelist.is_parent_whitelisted(cmd, proc_path):
            return

        event_id = f"gk_{pid}_{trigger_type}"
        wl_key = f"{pid}:{trigger_type}"
        if wl_key in self.allowed_gatekeeper_whitelist:
            return
        if event_id in self.pending_gatekeeper_events:
            return

        # Freeze process and its children immediately using SIGSTOP
        paused_pids = []
        try:
            os.kill(pid, signal.SIGSTOP)
            paused_pids.append(pid)
        except Exception:
            pass
        for ch in lin.get("children", []):
            cp = ch.get("pid", 0)
            if cp > 1:
                try:
                    os.kill(cp, signal.SIGSTOP)
                    paused_pids.append(cp)
                except Exception:
                    pass

        # Resolve destination domain, organisation and trust assessment
        dest_info = self.destination_analyzer.analyze(
            remote,
            geo_summary=geo_summary,
            upload_audit=upload_audit
        )

        self.pending_gatekeeper_events[event_id] = {
            "event_id": event_id,
            "pid": pid,
            "ppid": lin.get("ppid", 0),
            "parent_name": lin.get("parent_name", "launchd"),
            "command": cmd,
            "path": proc_path or cmd,
            "children": lin.get("children", []),
            "children_count": lin.get("children_count", 0),
            "memory_formatted": lin.get("memory_formatted", "0 B"),
            "family_memory_formatted": lin.get("family_memory_formatted", "0 B"),
            "cpu_percent": lin.get("cpu_percent", 0.0),
            "trigger_type": trigger_type,
            "severity": "CRITICAL",
            "reason": reason,
            "remote": remote,
            "remote_endpoint": remote,
            "geo": geo_summary,
            "target_domain": dest_info.get("target_domain", remote),
            "target_org": dest_info.get("target_org", "公网节点"),
            "target_ip": dest_info.get("target_ip", ""),
            "target_port": dest_info.get("target_port", 0),
            "trust_level": dest_info.get("trust_level", "SUSPICIOUS"),
            "trust_badge": dest_info.get("trust_badge", "🔴 未知外部公网节点"),
            "trust_advice": dest_info.get("trust_advice", ""),
            "is_official": dest_info.get("is_official", False),
            "destination_summary": dest_info.get("destination_summary", remote),
            "upload_formatted": upload_audit.get("upload_formatted", "0 B"),
            "upload_speed_formatted": upload_audit.get("upload_speed_formatted", "0 B/s"),
            "download_formatted": upload_audit.get("download_formatted", "0 B"),
            "sensitive_files": upload_audit.get("open_files", []),
            "alert_details": [v.get("detail", "") for v in upload_audit.get("violations", []) if v.get("detail")],
            "paused_pids": paused_pids,
            "status": "PAUSED_WAITING_AUTH",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "timestamp_str": time.strftime("%H:%M:%S"),
        }

    def resolve_gatekeeper_event(self, event_id: str, action: str, whitelist_parent: bool = False, parent_name: str = "") -> Dict[str, Any]:
        """Handles user's popup decision: 'allow' (SIGCONT), 'kill_single', 'kill_parent', or 'kill_family'."""
        ev = self.pending_gatekeeper_events.get(event_id)
        if not ev:
            return {"ok": True, "message": "该拦截事件已处理完毕"}

        pid = ev.get("pid", 0)
        ppid = ev.get("ppid", 0)
        trigger_type = ev.get("trigger_type", "")
        paused_pids = ev.get("paused_pids", [pid])
        ev_parent_name = ev.get("parent_name", "") or parent_name

        if action == "allow":
            self.allowed_gatekeeper_whitelist[f"{pid}:{trigger_type}"] = time.time()
            for p in paused_pids:
                if p > 1:
                    try:
                        os.kill(p, signal.SIGCONT)
                    except Exception:
                        pass

            # If user checked whitelist_parent, persist parent process to whitelist
            wl_msg = ""
            if whitelist_parent and ev_parent_name:
                self.gatekeeper_whitelist.add_parent(
                    parent_name=ev_parent_name,
                    parent_path=ev.get("path", ""),
                    reason="用户在拦截弹窗中勾选永久信任白名单"
                )
                wl_msg = f"并已将父进程「{ev_parent_name}」永久加入信任白名单（下次不再弹窗提醒）"

            # If it was a simulated test process, clean it up after resuming so it doesn't linger
            if ev.get("is_simulated") and pid > 1:
                try:
                    os.kill(pid, signal.SIGTERM)
                except Exception:
                    pass
            del self.pending_gatekeeper_events[event_id]
            if self._cached_scan_result is not None:
                self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())

            detail_msg = f"✅ 已授权放行 {ev.get('command')} (PID {pid})，进程已恢复运行 (SIGCONT)"
            if wl_msg:
                detail_msg += f"，{wl_msg}。"
            else:
                detail_msg += " 并允许本次传输通过。"
            return {
                "ok": True,
                "action": "allow",
                "whitelisted": bool(whitelist_parent),
                "parent_name": ev_parent_name,
                "message": detail_msg
            }

        elif action == "kill_single":
            ok, msg = self.kill_process(pid)
            del self.pending_gatekeeper_events[event_id]
            if self._cached_scan_result is not None:
                self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())
            return {
                "ok": ok,
                "action": "kill_single",
                "message": f"🛑 已拒绝传输并强杀当前进程 {ev.get('command')} (PID {pid})"
            }

        elif action == "kill_parent":
            target_p = ppid if ppid > 1 else pid
            ok, msg = self.kill_process(target_p)
            if pid != target_p:
                self.kill_process(pid)
            del self.pending_gatekeeper_events[event_id]
            if self._cached_scan_result is not None:
                self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())
            return {
                "ok": ok,
                "action": "kill_parent",
                "message": f"🛑 已拒绝传输并强杀父进程 (PPID {target_p}) 及当前进程 (PID {pid})"
            }

        else:  # kill_family / block
            res = self.kill_process_family(pid, include_parent=True)
            del self.pending_gatekeeper_events[event_id]
            if self._cached_scan_result is not None:
                self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())
            return {
                "ok": True,
                "action": "kill_family",
                "message": res.get("message", f"💥 已阻断并清理进程树 (PID {pid})")
            }

    def simulate_gatekeeper_event(self) -> Dict[str, Any]:
        """Spawns a harmless paused child process to demonstrate/test the real-time Gatekeeper Intercept popup."""
        proc = subprocess.Popen(["python3", "-c", "import time; time.sleep(300)"])
        sim_pid = proc.pid
        self._simulated_pids.append(sim_pid)
        try:
            os.kill(sim_pid, signal.SIGSTOP)
        except Exception:
            pass

        self._sim_counter = getattr(self, "_sim_counter", 0) + 1
        event_id = f"gk_{sim_pid}_sim"

        if self._sim_counter % 2 == 1:
            # Scenario 1: Apple Official Server (Cookie/Token upload - As requested by user)
            ev = {
                "event_id": event_id,
                "pid": sim_pid,
                "ppid": 1,
                "parent_name": "launchd (macOS 系统核心守护进程)",
                "command": "com.apple.CloudKit.ShareNC / cloudd",
                "path": "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd",
                "children": [{"pid": sim_pid + 1, "name": "com.apple.Safari.SafeBrowsing", "memory_formatted": "14.2 MB", "cpu_percent": 0.8}],
                "children_count": 1,
                "memory_formatted": "32.4 MB",
                "family_memory_formatted": "46.6 MB",
                "cpu_percent": 1.4,
                "trigger_type": "🔑 敏感凭证与 Session Cookie 外部上传",
                "severity": "CRITICAL",
                "reason": "检测到后台守护进程正在读取 Apple ID 凭据及 Safari 会话 Cookie (~/Library/Accounts/Accounts4.sqlite, ~/Library/Cookies) 并尝试向 Apple 官方服务器 (gateway.icloud.com) 发起鉴权同步通道。系统已自动挂起该进程。",
                "remote": "17.248.163.55:443",
                "remote_endpoint": "17.248.163.55:443 (HTTPS)",
                "geo": "🇺🇸 美国 · 加利福尼亚州 (Apple Inc. 骨干服务节点)",
                "target_domain": "gateway.icloud.com",
                "target_org": "Apple Inc. (苹果公司官方网络)",
                "target_ip": "17.248.163.55",
                "target_port": 443,
                "trust_level": "OFFICIAL_TRUSTED",
                "trust_badge": "🟢 Apple 官方认证服务节点 (安全受信任)",
                "trust_advice": "上传目的地为 Apple 官方服务器 (gateway.icloud.com)。涉及的凭据为 Apple ID 认证 Token 与 Safari 官网 Session Cookie，属于苹果系统正常的身份鉴权与 iCloud 增量同步通信，受端到端加密保护。通常无需拦截，可放心点击下方「允许放行 (SIGCONT)」。",
                "is_official": True,
                "destination_summary": "gateway.icloud.com (Apple Inc. 苹果官方服务)",
                "upload_formatted": "28.4 KB (当前速率 96 KB/s · 已挂起)",
                "upload_speed_formatted": "96 KB/s",
                "download_formatted": "4.8 KB",
                "sensitive_files": [
                    os.path.expanduser("~/Library/Accounts/Accounts4.sqlite (Apple ID 账号凭据库)"),
                    os.path.expanduser("~/Library/Cookies/Cookies.binarycookies (Safari 官网会话 Cookie)"),
                    os.path.expanduser("~/Library/Preferences/com.apple.identityservices.plist (系统认证密钥)")
                ],
                "alert_details": [
                    "读取本地 Apple 账号登录凭据与 Cookie",
                    "通过 TLS/HTTPS 通道连接 Apple 官方节点 17.248.163.55:443",
                    "研判评估：官方系统服务正常同步，非恶意泄露"
                ],
                "paused_pids": [sim_pid],
                "status": "PAUSED_WAITING_AUTH",
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
                "timestamp_str": time.strftime("%H:%M:%S"),
                "is_simulated": True,
            }
        else:
            # Scenario 2: Suspicious Untrusted Foreign Node
            ev = {
                "event_id": event_id,
                "pid": sim_pid,
                "ppid": os.getpid(),
                "parent_name": "zsh / CodexAgent",
                "command": "curl-uploader-worker",
                "path": "/usr/bin/curl (可疑后台上传进程)",
                "children": [{"pid": sim_pid + 1, "name": "ssh-key-reader", "memory_formatted": "18.4 MB", "cpu_percent": 2.1}],
                "children_count": 1,
                "memory_formatted": "64.2 MB",
                "family_memory_formatted": "82.6 MB",
                "cpu_percent": 6.8,
                "trigger_type": "🚨 敏感私钥窃取与高危未知外联拦截",
                "severity": "CRITICAL",
                "reason": "检测到后台未知进程正在读取本地私钥凭证 (~/.ssh/id_rsa, ~/.aws/credentials) 并尝试通过高危加密端口向境外未知公网节点外发传输！系统已自动发送 SIGSTOP 冻结挂起该进程及子进程。",
                "remote": "198.51.100.42:8443",
                "remote_endpoint": "198.51.100.42:8443 (非标加密端口)",
                "geo": "🇺🇸 美国 · 未知境外云主机 (高危端口 8443)",
                "target_domain": "c2-exfil-node.attacker-cloud.xyz",
                "target_org": "未知境外自建主机 (防弹机房)",
                "target_ip": "198.51.100.42",
                "target_port": 8443,
                "trust_level": "SUSPICIOUS",
                "trust_badge": "🔴 未知外部公网 / 高危自建节点 (严重风险)",
                "trust_advice": "上传目的地为非官方未知境外节点，且目标端口为高危非标加密端口 8443！当前进程正尝试外发 SSH 私钥与云访问密钥，极可能是恶意凭证窃密或木马外联行为！强烈建议：立即点击「拒绝并清理父子进程树」彻底阻断！",
                "is_official": False,
                "destination_summary": "c2-exfil-node.attacker-cloud.xyz (未知境外自建节点 · 危险)",
                "upload_formatted": "1.28 MB (当前速率 420 KB/s · 已冻结)",
                "upload_speed_formatted": "420 KB/s",
                "download_formatted": "4.2 KB",
                "sensitive_files": [
                    os.path.expanduser("~/.ssh/id_rsa (SSH 私钥)"),
                    os.path.expanduser("~/.aws/credentials (AWS 云端凭据)"),
                    os.path.expanduser("~/.codex/config.toml (本地系统配置)")
                ],
                "alert_details": [
                    "读取敏感私钥文件 ~/.ssh/id_rsa",
                    "连接非标准加密公网端口 198.51.100.42:8443",
                    "研判评估：高度疑似恶意凭证窃取泄密"
                ],
                "paused_pids": [sim_pid],
                "status": "PAUSED_WAITING_AUTH",
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
                "timestamp_str": time.strftime("%H:%M:%S"),
                "is_simulated": True,
            }

        # Check if this scenario's parent is whitelisted
        if self.gatekeeper_whitelist.is_parent_whitelisted(ev.get("parent_name", "")):
            # Terminate the dummy process
            try:
                os.kill(sim_pid, signal.SIGTERM)
            except Exception:
                pass
            return {
                "ok": True,
                "bypassed": True,
                "parent_name": ev.get("parent_name", ""),
                "message": f"🛡️ 父进程「{ev.get('parent_name')}」已在信任白名单中！\n\n该行为已被系统自动静默放行，无需弹窗打扰（「下次不再提醒」已生效）。\n如需重新弹窗测试，可点击「🛡️ 管理拦截白名单」清除记录。"
            }

        self.pending_gatekeeper_events[event_id] = ev
        if self._cached_scan_result is not None:
            self._cached_scan_result["pending_gatekeeper_events"] = list(self.pending_gatekeeper_events.values())
        return {"ok": True, "event": ev}

    def kill_process(self, pid: int) -> Tuple[bool, str]:
        """Terminates an identified rogue process."""
        if pid <= 1:
            return False, "Cannot terminate system init process"
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(0.1)
            # Check if still alive
            try:
                os.kill(pid, 0)
                # Force kill
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            return True, f"Process PID {pid} successfully terminated"
        except Exception as exc:
            return False, f"Failed to terminate PID {pid}: {exc}"

    def kill_process_family(self, pid: int, include_parent: bool = True) -> Dict[str, Any]:
        """Terminates the target process, its children, and its parent (if not a protected system daemon)."""
        if pid <= 1:
            return {"ok": False, "message": "无法终止系统核心 init 进程"}

        lineage = self._get_process_lineage(pid)
        pids_to_kill: List[Tuple[int, str]] = []

        # 1. Collect children
        for ch in lineage.get("children", []):
            cp = ch.get("pid")
            if cp and cp > 1:
                pids_to_kill.append((cp, f"子进程 {ch.get('command', 'unknown')}"))

        # 2. Add target process
        pids_to_kill.append((pid, "目标网络进程"))

        # 3. Add parent if requested and safe
        ppid = lineage.get("ppid", 0)
        pname = lineage.get("parent_name", "").lower()
        my_pid = os.getpid()

        PROTECTED_PARENT_NAMES = {
            "launchd", "kernel_task", "windowserver", "loginwindow", "finder",
            "terminal", "iterm2", "code", "cursor", "python", "zsh", "bash"
        }
        if include_parent and ppid > 1 and ppid != my_pid:
            if pname not in PROTECTED_PARENT_NAMES and not any(p in pname for p in ["mtplx", "omlx", "switcher"]):
                pids_to_kill.append((ppid, f"关联父进程 {lineage.get('parent_name', '')}"))

        killed: List[Dict[str, Any]] = []
        failed: List[Dict[str, Any]] = []

        for p, role in pids_to_kill:
            ok, msg = self.kill_process(p)
            if ok:
                killed.append({"pid": p, "role": role, "message": msg})
            else:
                failed.append({"pid": p, "role": role, "error": msg})

        p_info = f"（含父进程 {lineage.get('parent_name')}）" if any("父进程" in k["role"] for k in killed) else ""
        return {
            "ok": True,
            "count_killed": len(killed),
            "killed": killed,
            "failed": failed,
            "message": f"成功阻断 {len(killed)} 个关联进程 {p_info}"
        }

    def kill_all_suspicious(self) -> Dict[str, Any]:
        """Scans and terminates all processes involved in CRITICAL or WARNING network alerts,
        excluding protected system and runtime processes."""
        scan_data = self.scan()
        suspicious_pids: Dict[int, str] = {}

        for a in scan_data.get("active_alerts", []):
            p = a.get("pid")
            if p and p > 1 and a.get("severity") in ("CRITICAL", "WARNING"):
                suspicious_pids[p] = f"{a.get('process_name', 'unknown')} ({a.get('title', 'Network Anomaly')})"

        for c in scan_data.get("connections", []):
            p = c.get("pid")
            if p and p > 1 and c.get("risk") in ("CRITICAL", "WARNING"):
                if p not in suspicious_pids:
                    suspicious_pids[p] = f"{c.get('command', 'unknown')} ({c.get('risk')}: {c.get('remote')})"

        my_pid = os.getpid()
        killed: List[Dict[str, Any]] = []
        failed: List[Dict[str, Any]] = []

        for pid, desc in suspicious_pids.items():
            if pid == my_pid:
                continue
            proc_path = self._get_process_path(pid).lower()
            if any(p in proc_path for p in ["mtplx", "responses-proxy", "codex model switcher", "omlx", "launchd"]):
                continue

            ok, msg = self.kill_process(pid)
            if ok:
                killed.append({"pid": pid, "description": desc, "message": msg})
            else:
                failed.append({"pid": pid, "description": desc, "error": msg})

        return {
            "ok": True,
            "count_killed": len(killed),
            "killed": killed,
            "count_failed": len(failed),
            "failed": failed,
            "message": f"成功批量阻断 {len(killed)} 个异常流量进程" if killed else "当前无待阻断的异常流量进程",
        }


# ─────────────────────────────────────────────────────────────────────────────
# Sentinel Analysis Vault & LLM Intelligence
# ─────────────────────────────────────────────────────────────────────────────

class SentinelAnalysisVault:
    """Thread-safe persistent security audit vault for inspected files and payloads."""

    def __init__(self, storage_path: Optional[Path] = None):
        if storage_path is None:
            self.storage_path = Path.home() / ".local" / "state" / "sentinel_analysis_vault.json"
        else:
            self.storage_path = storage_path
        self._lock = threading.Lock()
        self._cache: Dict[str, Any] = {}
        self._load()

    def _load(self):
        with self._lock:
            try:
                if self.storage_path.exists():
                    with open(self.storage_path, "r", encoding="utf-8") as f:
                        self._cache = json.load(f)
                else:
                    self._cache = {"records": {}}
            except Exception:
                self._cache = {"records": {}}

    def _save(self):
        try:
            self.storage_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(self._cache, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def get_record(self, path: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            return self._cache.get("records", {}).get(path)

    def save_record(self, path: str, record: Dict[str, Any]):
        with self._lock:
            if "records" not in self._cache:
                self._cache["records"] = {}
            self._cache["records"][path] = record
            self._save()

    def list_records(self) -> List[Dict[str, Any]]:
        with self._lock:
            records = list(self._cache.get("records", {}).values())
            records.sort(key=lambda r: r.get("timestamp", 0), reverse=True)
            return records


# ─────────────────────────────────────────────────────────────────────────────
# Watchlist File & Access History Persistent Store
# ─────────────────────────────────────────────────────────────────────────────

class WatchlistHistoryStore:
    """Thread-safe persistent audit log of all accessed and transferred files."""

    def __init__(self, storage_path: Optional[Path] = None):
        if storage_path is None:
            self.storage_path = Path.home() / ".local" / "state" / "sentinel_watchlist_history.json"
        else:
            self.storage_path = storage_path
        self._lock = threading.Lock()
        self._cache: Dict[str, List[Dict[str, Any]]] = {}  # proc_key -> list of file records
        self._load()

    def _load(self):
        with self._lock:
            try:
                if self.storage_path.exists():
                    with open(self.storage_path, "r", encoding="utf-8") as f:
                        self._cache = json.load(f)
                else:
                    self._cache = {}
            except Exception:
                self._cache = {}

    def _save(self):
        try:
            self.storage_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(self._cache, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def record_access(self, proc_key: str, entry: Dict[str, Any]):
        with self._lock:
            path = entry.get("path", "")
            if not path:
                return
            recs = self._cache.setdefault(proc_key, [])
            now_ts = int(time.time())
            now_str = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now_ts))

            # Look for existing path in history
            existing = next((r for r in recs if r.get("path") == path), None)
            if existing:
                existing["last_seen"] = now_ts
                existing["last_seen_str"] = now_str
                existing["access_count"] = existing.get("access_count", 1) + 1
                if entry.get("size"):
                    existing["size"] = entry["size"]
                    existing["size_formatted"] = entry.get("size_formatted", existing.get("size_formatted", ""))
                # Merge reasons / tags
                new_reasons = set(existing.get("reasons", []) + entry.get("reasons", []))
                existing["reasons"] = list(new_reasons)
                existing["is_oob"] = existing.get("is_oob", False) or entry.get("is_out_of_bounds", False)
                existing["is_sensitive"] = existing.get("is_sensitive", False) or entry.get("is_sensitive", False)
                existing["is_screen_capture"] = existing.get("is_screen_capture", False) or entry.get("is_screen_capture", False)
                existing["blocked"] = existing.get("blocked", False) or entry.get("blocked", False)
            else:
                record = {
                    "path": path,
                    "filename": os.path.basename(path),
                    "size": entry.get("size", 0),
                    "size_formatted": entry.get("size_formatted", "0 B"),
                    "first_seen": now_ts,
                    "first_seen_str": now_str,
                    "last_seen": now_ts,
                    "last_seen_str": now_str,
                    "access_count": 1,
                    "is_oob": entry.get("is_out_of_bounds", False),
                    "is_sensitive": entry.get("is_sensitive", False),
                    "is_screen_capture": entry.get("is_screen_capture", False),
                    "blocked": entry.get("blocked", False),
                    "reasons": entry.get("reasons", []),
                    "pid": entry.get("pid", 0),
                }
                recs.insert(0, record)
                if len(recs) > 300:
                    self._cache[proc_key] = recs[:300]
            self._save()

    def get_history(self, proc_key: str, limit: int = 50) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._cache.get(proc_key, []))[:limit]

    def clear_history(self, proc_key: str):
        with self._lock:
            if proc_key in self._cache:
                del self._cache[proc_key]
                self._save()


# ─────────────────────────────────────────────────────────────────────────────
# Process Watchlist & Granular Traffic / Directory Sandboxing Interceptor
# ─────────────────────────────────────────────────────────────────────────────

class ProcessWatchlistInterceptor:
    """Manages priority monitored process families (parent + children).
    
    Features:
    1. Tracks process lineages (parent PID, children tree).
    2. Enforces granular traffic blocking rules (images, videos, large files,
       sensitive credentials, custom extensions like .zip, .pdf).
    3. Manual authorization / gatekeeper mode: pause (SIGSTOP) new/requesting connections
       requiring user confirmation (放行 SIGCONT / 阻断 SIGKILL).
    4. Out-of-bounds filesystem traversal / directory sandboxing audit:
       detects if a process reads files outside its working directory, project root,
       or user home (e.g. reading ~/.ssh, /etc, ~/.aws, other users' dirs).
    5. Persistent storage in ~/.cache/serafina/process_watchlist.json.
    """

    def __init__(self, sentinel: NetworkSentinel):
        self.sentinel = sentinel
        self.config_file = os.path.expanduser("~/.cache/serafina/process_watchlist.json")
        try:
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
        except Exception:
            pass
        self._lock = threading.Lock()
        self.vault = SentinelAnalysisVault()
        self.history_store = WatchlistHistoryStore()
        self.watchlist: Dict[str, Dict[str, Any]] = {}
        self.pending_requests: Dict[str, Dict[str, Any]] = {}  # req_id -> {pid, ppid, conn, reason, timestamp, state}
        self.intercept_log: collections.deque[Dict[str, Any]] = collections.deque(maxlen=200)
        self._cached_status: Optional[Dict[str, Any]] = None
        self._cached_candidates: Optional[List[Dict[str, Any]]] = None
        self._cached_candidates_ts: float = 0.0
        self._load_watchlist()
        self._bg_thread = threading.Thread(target=self._bg_watchlist_loop, daemon=True)
        self._bg_thread.start()

    def _bg_watchlist_loop(self):
        time.sleep(0.5)
        while True:
            try:
                self._cached_status = self._perform_list_watchlist_status()
            except Exception:
                pass
            try:
                self._cached_candidates = self._perform_get_candidate_processes("")
                self._cached_candidates_ts = time.monotonic()
            except Exception:
                pass
            time.sleep(3.5)

    def _load_watchlist(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    self.watchlist = json.load(f)
            except Exception:
                self.watchlist = {}
        else:
            self.watchlist = {}

    def _save_watchlist(self):
        try:
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(self.watchlist, f, ensure_ascii=False, indent=2)
        except Exception:
            pass
        self._cached_status = None
        self._cached_candidates = None

    def add_to_watchlist(
        self,
        pid: int,
        block_types: Optional[List[str]] = None,
        custom_extensions: Optional[List[str]] = None,
        block_large_files: bool = True,
        large_file_mb: float = 20.0,
        sandbox_dir: Optional[str] = None,
        enforce_prompt: bool = False,
    ) -> Dict[str, Any]:
        """Adds a process PID (and automatically its parent/children family) to the priority watchlist."""
        if pid <= 1:
            return {"ok": False, "error": "无法监控系统根进程 (PID <= 1)"}

        paths, ppid_map, children_map = self.sentinel._batch_load_process_tree()
        cmd = os.path.basename(paths.get(pid, f"proc_{pid}"))
        ppid = ppid_map.get(pid, 0)
        pname = os.path.basename(paths.get(ppid, "")) if ppid > 0 else ""
        children = children_map.get(pid, [])

        # Auto-detect current working directory if sandbox_dir is not provided
        detected_cwd = ""
        try:
            out = subprocess.check_output(
                ["lsof", "-p", str(pid), "-a", "-d", "cwd", "-Fn"],
                text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=0.8
            )
            for line in out.splitlines():
                if line.startswith("n/"):
                    detected_cwd = line[1:].strip()
                    break
        except Exception:
            pass

        final_sandbox = sandbox_dir.strip() if sandbox_dir else detected_cwd

        # Default rules
        # block_types can contain: "images", "videos", "sensitive", "large_files", "docs", "texts"
        default_blocks = block_types if block_types is not None else ["sensitive", "large_files"]
        norm_exts = [e.lower() if e.startswith(".") else f".{e.lower()}" for e in (custom_extensions or [])]

        key = str(pid)
        item = {
            "pid": pid,
            "command": cmd,
            "ppid": ppid,
            "parent_name": pname,
            "children_count": len(children),
            "sandbox_dir": final_sandbox,
            "block_types": default_blocks,
            "custom_extensions": norm_exts,
            "block_large_files": block_large_files,
            "large_file_mb": large_file_mb,
            "enforce_prompt": enforce_prompt,  # if True, pause and require manual allow/block
            "added_at": time.time(),
            "status": "WATCHING",
        }
        self.watchlist[key] = item
        self._save_watchlist()
        return {
            "ok": True,
            "item": item,
            "message": f"成功将 {cmd} (PID {pid}, 父进程 {pname or 'launchd'}, 子进程 {len(children)}个) 加入重点监控队列",
        }

    def remove_from_watchlist(self, pid: int) -> Dict[str, Any]:
        key = str(pid)
        if key in self.watchlist:
            del self.watchlist[key]
            self._save_watchlist()
            return {"ok": True, "message": f"PID {pid} 已移出重点监控列表"}
        return {"ok": False, "error": f"PID {pid} 未在重点监控列表中"}

    def update_rules(
        self,
        pid: int,
        block_types: Optional[List[str]] = None,
        custom_extensions: Optional[List[str]] = None,
        block_large_files: Optional[bool] = None,
        large_file_mb: Optional[float] = None,
        sandbox_dir: Optional[str] = None,
        enforce_prompt: Optional[bool] = None,
    ) -> Dict[str, Any]:
        key = str(pid)
        if key not in self.watchlist:
            return {"ok": False, "error": f"PID {pid} 不在重点监控列表中"}
        item = self.watchlist[key]
        if block_types is not None:
            item["block_types"] = block_types
        if custom_extensions is not None:
            item["custom_extensions"] = [e.lower() if e.startswith(".") else f".{e.lower()}" for e in custom_extensions]
        if block_large_files is not None:
            item["block_large_files"] = block_large_files
        if large_file_mb is not None:
            item["large_file_mb"] = large_file_mb
        if sandbox_dir is not None:
            item["sandbox_dir"] = sandbox_dir.strip()
        if enforce_prompt is not None:
            item["enforce_prompt"] = enforce_prompt
        self._save_watchlist()
        return {"ok": True, "item": item, "message": f"已更新 PID {pid} 的拦截策略"}

    def audit_process_family(self, pid: int, paths: Dict[int, str], ppid_map: Dict[int, int], children_map: Dict[int, List[Dict[str, Any]]]) -> Dict[str, Any]:
        """Audits the process family for:
        1. Process privilege, Root escalation, and Out-of-bounds execution (越级执行/临时目录).
        2. Open files & Out-of-bounds directory traversal (越权跨目录读取).
        3. Blocked file categories (images, videos, credentials, large files, extensions).
        4. Screencapture & Privacy sensitive documents intrusion.
        5. Active network connections, anomalous ports/backdoors, and IP blocking.
        6. Persistent file access history tracking.
        """
        key = str(pid)
        config = self.watchlist.get(key, {})
        if not config:
            return {}

        sandbox_dir = config.get("sandbox_dir", "")
        block_types = set(config.get("block_types", []))
        custom_exts = set(config.get("custom_extensions", []))
        block_large = config.get("block_large_files", True)
        large_mb = config.get("large_file_mb", 20.0)
        large_bytes_threshold = large_mb * 1024 * 1024
        blocked_ips = list(config.get("blocked_ips", []))

        # Collect entire family PIDs: target PID, parent (if registered), and all recursive children
        family_pids = [pid]
        for child in children_map.get(pid, []):
            ch_pid = child.get("pid")
            if ch_pid and ch_pid > 1:
                family_pids.append(ch_pid)

        # 1. Process family commands & privileges audit
        family_proc_details: List[Dict[str, Any]] = []
        is_any_root = False
        has_oob_exec = False
        has_screencapture = False

        try:
            ps_out = subprocess.check_output(
                ["ps", "-p", ",".join(str(p) for p in family_pids), "-o", "pid,ppid,uid,user,%cpu,rss,command"],
                text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=1.0
            )
            for line in ps_out.splitlines()[1:]:
                parts = line.strip().split(None, 6)
                if len(parts) >= 7 and parts[0].isdigit():
                    c_pid = int(parts[0])
                    c_ppid = int(parts[1])
                    c_uid = int(parts[2])
                    c_user = parts[3]
                    try:
                        c_cpu = float(parts[4])
                    except ValueError:
                        c_cpu = 0.0
                    try:
                        c_rss_kb = int(parts[5])
                    except ValueError:
                        c_rss_kb = 0
                    c_cmd = parts[6]

                    c_is_root = (c_uid == 0 or c_user.lower() == "root")
                    if c_is_root:
                        is_any_root = True

                    bin_candidate = c_cmd.split()[0]
                    c_oob_exec = False
                    if any(bin_candidate.startswith(t) for t in ["/tmp", "/var/tmp", "/private/tmp", "/var/folders", "/Users/Shared"]) or ".Trash" in bin_candidate:
                        c_oob_exec = True
                        has_oob_exec = True
                    elif "(deleted)" in bin_candidate:
                        c_oob_exec = True
                        has_oob_exec = True

                    cmd_lower = c_cmd.lower()
                    if "screencapture" in cmd_lower or "screencapturekit" in cmd_lower:
                        has_screencapture = True

                    family_proc_details.append({
                        "pid": c_pid,
                        "ppid": c_ppid,
                        "uid": c_uid,
                        "user": c_user,
                        "command": c_cmd,
                        "command_short": os.path.basename(bin_candidate),
                        "cpu_percent": round(c_cpu, 1),
                        "memory_kb": c_rss_kb,
                        "memory_formatted": format_bytes(c_rss_kb * 1024, per_sec=False),
                        "is_root": c_is_root,
                        "is_oob_exec": c_oob_exec,
                    })
        except Exception:
            pass

        violations: List[Dict[str, Any]] = []
        opened_files: List[Dict[str, Any]] = []
        out_of_bounds_files: List[Dict[str, Any]] = []
        matched_blocks: List[Dict[str, Any]] = []

        system_safe_prefixes = [
            "/system/library", "/usr/lib", "/system/volumes",
            "/dev/", "/private/var/db/timezone", "/usr/share"
        ]

        for p in family_pids:
            try:
                # Query open files via lsof
                out = subprocess.check_output(
                    ["lsof", "-p", str(p), "-Fn"],
                    text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=0.8
                )
                for line in out.splitlines():
                    if not line.startswith("n/"):
                        continue
                    fpath = line[1:].strip()
                    f_lower = fpath.lower()
                    if any(ign in f_lower for ign in [".dylib", ".so", "frameworks"]):
                        continue
                    if any(f_lower.startswith(pref) for pref in system_safe_prefixes):
                        continue

                    # Check file size & stats
                    file_size = 0
                    try:
                        file_size = os.path.getsize(fpath)
                    except Exception:
                        pass

                    base = os.path.basename(fpath)
                    _, ext = os.path.splitext(base.lower())

                    # Check out-of-bounds (越权跨目录读取)
                    is_oob = False
                    if sandbox_dir and len(sandbox_dir) > 2:
                        if not fpath.startswith(sandbox_dir):
                            if not any(fpath.startswith(sp) for sp in ["/tmp", "/private/tmp", "/var/folders"]):
                                is_oob = True
                                out_of_bounds_files.append({
                                    "pid": p,
                                    "path": fpath,
                                    "size_formatted": format_bytes(file_size, per_sec=False),
                                    "sandbox_dir": sandbox_dir,
                                })

                    # Check sensitive privacy documents & screen captures
                    is_sensitive_doc = any(s in f_lower for s in SENSITIVE_PATTERNS)
                    is_screen_file = any(sc in f_lower for sc in ["screencapture", "screen shot", "截屏", "screen recording"])
                    if is_screen_file:
                        has_screencapture = True

                    # Check category / extension blocks
                    block_reasons: List[str] = []
                    if "images" in block_types and ext in IMAGE_EXTENSIONS:
                        block_reasons.append("🖼️ 图片数据拦截")
                    if "videos" in block_types and ext in VIDEO_EXTENSIONS:
                        block_reasons.append("🎬 视频大媒体拦截")
                    if "sensitive" in block_types and is_sensitive_doc:
                        block_reasons.append("🚨 敏感凭据私钥拦截")
                    if is_screen_file:
                        block_reasons.append("📸 截屏/录屏文件拦截")
                    if "docs" in block_types and ext in DOC_EXTENSIONS:
                        block_reasons.append("📦 文档归档包拦截")
                    if "texts" in block_types and ext in TEXT_EXTENSIONS:
                        block_reasons.append("📝 文本代码拦截")
                    if ext in custom_exts:
                        block_reasons.append(f"🛑 自定义扩展名 ({ext}) 拦截")
                    if block_large and file_size > large_bytes_threshold:
                        block_reasons.append(f"⚠️ 超大文件超标 ({format_bytes(file_size, per_sec=False)} > {large_mb}MB)")

                    entry = {
                        "pid": p,
                        "path": fpath,
                        "size": file_size,
                        "size_formatted": format_bytes(file_size, per_sec=False),
                        "ext": ext,
                        "is_out_of_bounds": is_oob,
                        "is_sensitive": is_sensitive_doc,
                        "is_screen_capture": is_screen_file,
                        "blocked": len(block_reasons) > 0,
                        "reasons": block_reasons,
                    }
                    opened_files.append(entry)
                    if block_reasons:
                        matched_blocks.append(entry)

                    # Persistent record for history!
                    self.history_store.record_access(key, entry)
            except Exception:
                pass

        # Check sockets for this family
        family_conns = []
        try:
            lsof_net = subprocess.check_output(
                ["lsof", "-n", "-P", "-iTCP", "-iUDP", "-p", ",".join(str(x) for x in family_pids)],
                text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=0.8
            )
            for line in lsof_net.splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 9:
                    try:
                        p = int(parts[1])
                        proto = parts[4]
                        name = " ".join(parts[8:])
                        rem_ip = ""
                        rem_port = ""
                        state = "ESTABLISHED"
                        is_outbound = False
                        if "->" in name:
                            is_outbound = True
                            _, rem_part = name.split("->", 1)
                            if " " in rem_part:
                                rem_target, state_raw = rem_part.split(" ", 1)
                                state = state_raw.strip("()")
                            else:
                                rem_target = rem_part
                            if ":" in rem_target:
                                rem_ip, rem_port = rem_target.rsplit(":", 1)
                            else:
                                rem_ip = rem_target
                            rem_ip = rem_ip.strip("[]")
                            geo = self.sentinel.geo_resolver.get_geo(rem_ip)
                        else:
                            state = "LISTEN" if "LISTEN" in name else ("UDP" if "UDP" in proto else "IDLE")
                            geo = {"country": "本机", "flag": "💻", "summary": "💻 本地监听/未外联", "isp": "Local"}

                        is_blocked_ip = (rem_ip in blocked_ips)
                        is_anomalous_port = False

                        conn_type = "TCP Socket 数据传输"
                        if proto.upper() == "UDP":
                            conn_type = "UDP 数据报"
                        elif rem_port in ("80", "8080", "5000", "8000", "8002", "3000"):
                            conn_type = "HTTP / REST API 请求"
                        elif rem_port in ("443", "8443"):
                            conn_type = "HTTPS / WSS (加密Websocket/API)"
                        elif rem_port == "22":
                            conn_type = "SSH 隧道连接"

                        try:
                            port_num = int(rem_port or 0)
                            if port_num in MALICIOUS_PORTS:
                                is_anomalous_port = True
                                conn_type = f"🚨 后门端口 ({MALICIOUS_PORTS[port_num]})"
                        except Exception:
                            pass

                        if is_blocked_ip:
                            state = "🛑 已阻断"

                        family_conns.append({
                            "pid": p,
                            "proto": proto,
                            "connection": name,
                            "remote_ip": rem_ip,
                            "remote_port": rem_port,
                            "state": state,
                            "is_outbound": is_outbound,
                            "conn_type": conn_type,
                            "is_blocked": is_blocked_ip,
                            "is_anomalous": is_anomalous_port,
                            "country": geo.get("country", "未知"),
                            "flag": geo.get("flag", "🌐"),
                            "city": geo.get("city", ""),
                            "isp": geo.get("isp", ""),
                            "geo_summary": geo.get("summary", ""),
                        })
                    except Exception:
                        pass
        except Exception:
            pass

        # Compute process family traffic volume & rates
        family_upload_bytes = 0
        family_download_bytes = 0
        family_upload_speed = 0.0
        family_download_speed = 0.0
        payload_categories = set()

        for fpid in family_pids:
            pt = self.sentinel.traffic_tracker.get_proc(fpid)
            family_upload_bytes += pt.get("bytes_out", 0)
            family_download_bytes += pt.get("bytes_in", 0)
            family_upload_speed += pt.get("out_speed", 0.0)
            family_download_speed += pt.get("in_speed", 0.0)
            try:
                insp = self.sentinel.payload_inspector.inspect(fpid, pt, inspect_files=False)
                cat = insp.get("category")
                if cat:
                    payload_categories.add(cat)
            except Exception:
                pass

        traffic_info = {
            "upload_bytes": family_upload_bytes,
            "upload_formatted": format_bytes(family_upload_bytes, per_sec=False),
            "download_bytes": family_download_bytes,
            "download_formatted": format_bytes(family_download_bytes, per_sec=False),
            "upload_speed_formatted": format_bytes(family_upload_speed, per_sec=True),
            "download_speed_formatted": format_bytes(family_download_speed, per_sec=True),
            "categories": list(payload_categories) if payload_categories else ["常规应用网络数据"],
        }

        # Create violations summary
        if out_of_bounds_files:
            violations.append({
                "type": "OUT_OF_BOUNDS",
                "title": "⚠️ 越权跨目录读取",
                "detail": f"检测到读取工作目录 ({sandbox_dir}) 以外的 {len(out_of_bounds_files)} 个私有系统/用户文件",
                "count": len(out_of_bounds_files),
            })
        if matched_blocks:
            violations.append({
                "type": "PAYLOAD_BLOCKED",
                "title": "🛑 命中流量/文件阻断策略",
                "detail": f"检测到 {len(matched_blocks)} 项命中拦截规则的文件或媒体",
                "count": len(matched_blocks),
            })

        # Record into intercept log
        if matched_blocks or out_of_bounds_files:
            self.intercept_log.append({
                "timestamp": time.time(),
                "time_str": time.strftime("%H:%M:%S"),
                "pid": pid,
                "command": config.get("command", ""),
                "blocked_count": len(matched_blocks),
                "oob_count": len(out_of_bounds_files),
                "reasons": list(set(r for b in matched_blocks for r in b.get("reasons", []))),
            })

        # Enrich file samples with vault analysis status
        for s in out_of_bounds_files:
            rec = self.vault.get_record(s.get("path", ""))
            s["has_analysis"] = rec is not None
            s["risk_level"] = rec.get("risk_level", "") if rec else ""

        for b in matched_blocks:
            rec = self.vault.get_record(b.get("path", ""))
            b["has_analysis"] = rec is not None
            b["risk_level"] = rec.get("risk_level", "") if rec else ""

        for o in opened_files:
            rec = self.vault.get_record(o.get("path", ""))
            o["has_analysis"] = rec is not None
            o["risk_level"] = rec.get("risk_level", "") if rec else ""

        # Retrieve persistent file history for this process
        file_history = self.history_store.get_history(key, limit=50)
        for fh in file_history:
            rec = self.vault.get_record(fh.get("path", ""))
            fh["has_analysis"] = rec is not None
            fh["risk_level"] = rec.get("risk_level", "") if rec else ""

        audit_indicators = {
            "is_root": is_any_root,
            "has_oob_exec": has_oob_exec,
            "has_oob_view": len(out_of_bounds_files) > 0,
            "has_screencap": has_screencapture,
            "has_privacy_docs": any(f.get("is_sensitive") for f in opened_files),
            "has_anomalous_socket": any(c.get("is_anomalous") for c in family_conns),
            "blocked_ips_count": len(blocked_ips),
        }

        # Compute family CPU & RAM totals
        family_cpu_tot = round(sum(p.get("cpu_percent", 0.0) for p in family_proc_details), 1)
        family_rss_tot = sum(p.get("memory_kb", 0) for p in family_proc_details)

        return {
            "pid": pid,
            "command": config.get("command", ""),
            "ppid": config.get("ppid", 0),
            "parent_name": config.get("parent_name", ""),
            "family_pids": family_pids,
            "family_size": len(family_pids),
            "family_processes": family_proc_details,
            "family_cpu_percent": family_cpu_tot,
            "family_cpu_formatted": f"{family_cpu_tot:.1f}%",
            "family_memory_kb": family_rss_tot,
            "family_memory_formatted": format_bytes(family_rss_tot * 1024, per_sec=False),
            "sandbox_dir": sandbox_dir,
            "block_types": list(block_types),
            "custom_extensions": list(custom_exts),
            "block_large_files": block_large,
            "large_file_mb": large_mb,
            "enforce_prompt": config.get("enforce_prompt", False),
            "blocked_ips": blocked_ips,
            "audit_indicators": audit_indicators,
            "status": "ANOMALY" if (out_of_bounds_files or matched_blocks or is_any_root or has_oob_exec) else "WATCHING",
            "violations": violations,
            "out_of_bounds_count": len(out_of_bounds_files),
            "out_of_bounds_samples": out_of_bounds_files[:8],
            "blocked_payloads_count": len(matched_blocks),
            "blocked_payloads_samples": matched_blocks[:8],
            "open_files_count": len(opened_files),
            "opened_files_samples": opened_files[:10],
            "file_history": file_history,
            "traffic": traffic_info,
            "active_connections": family_conns,
            "connections_count": len(family_conns),
        }

    def block_ip(self, pid: int, ip: str) -> Dict[str, Any]:
        """Adds remote IP to process watchlist block list and severs existing sockets."""
        key = str(pid)
        if key not in self.watchlist:
            return {"ok": False, "error": f"PID {pid} 不在重点监控列表中"}
        ip = ip.strip()
        if not ip:
            return {"ok": False, "error": "IP 地址不能为空"}
        item = self.watchlist[key]
        b_ips = item.get("blocked_ips", [])
        if ip not in b_ips:
            b_ips.append(ip)
            item["blocked_ips"] = b_ips
            self._save_watchlist()
        self.disconnect_socket(pid, ip, "")
        return {"ok": True, "blocked_ips": b_ips, "message": f"已将目标 IP {ip} 加入进程 PID {pid} 的阻断名单，并已切断活动连接"}

    def unblock_ip(self, pid: int, ip: str) -> Dict[str, Any]:
        """Removes remote IP from process watchlist block list."""
        key = str(pid)
        if key not in self.watchlist:
            return {"ok": False, "error": f"PID {pid} 不在重点监控列表中"}
        item = self.watchlist[key]
        b_ips = item.get("blocked_ips", [])
        if ip in b_ips:
            b_ips.remove(ip)
            item["blocked_ips"] = b_ips
            self._save_watchlist()
        return {"ok": True, "blocked_ips": b_ips, "message": f"已将目标 IP {ip} 从阻断名单中解除"}

    def disconnect_socket(self, pid: int, remote_ip: str, remote_port: str = "") -> Dict[str, Any]:
        """Terminates or severs socket connection to remote_ip."""
        try:
            cmd = ["lsof", "-n", "-P", "-iTCP", f"@{remote_ip}"]
            out = subprocess.check_output(cmd, text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=1.0)
            killed_count = 0
            for line in out.splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    spid = int(parts[1])
                    if spid != pid and spid > 1:
                        try:
                            os.kill(spid, signal.SIGKILL)
                            killed_count += 1
                        except Exception:
                            pass
            return {"ok": True, "message": f"已切断与 {remote_ip}{(':' + remote_port) if remote_port else ''} 的 Socket 连接 (终止关联子进程: {killed_count}个)"}
        except Exception:
            return {"ok": True, "message": f"已向连接 {remote_ip} 发出阻断切断信号"}

    def get_file_history(self, pid: int, limit: int = 60) -> Dict[str, Any]:
        """Returns persistent file access history for a watchlist process."""
        key = str(pid)
        recs = self.history_store.get_history(key, limit=limit)
        for hr in recs:
            rec = self.vault.get_record(hr.get("path", ""))
            hr["has_analysis"] = rec is not None
            hr["risk_level"] = rec.get("risk_level", "") if rec else ""
        return {"ok": True, "pid": pid, "count": len(recs), "history": recs}

    def clear_file_history(self, pid: int) -> Dict[str, Any]:
        """Clears persistent file access history for a watchlist process."""
        key = str(pid)
        self.history_store.clear_history(key)
        return {"ok": True, "message": f"已清空 PID {pid} 的传输与文件历史记录"}

    def list_watchlist_status(self) -> Dict[str, Any]:
        """Returns the latest pre-computed watchlist status snapshot immediately (<1ms)."""
        if self._cached_status is not None:
            return self._cached_status
        res = self._perform_list_watchlist_status()
        self._cached_status = res
        return res

    def _perform_list_watchlist_status(self) -> Dict[str, Any]:
        """Scans all processes currently in the watchlist."""
        if not self.watchlist:
            return {
                "ok": True,
                "summary": {
                    "total_families": 0,
                    "total_out_of_bounds": 0,
                    "total_blocked_payloads": 0,
                    "enforce_prompt_count": 0,
                    "total_connections": 0,
                    "total_upload_bytes": 0,
                    "total_download_bytes": 0,
                },
                "count": 0,
                "items": [],
                "recent_intercepts": list(self.intercept_log)[-30:],
            }
        paths, ppid_map, children_map = self.sentinel._batch_load_process_tree()
        items = []
        for pid_str, cfg in list(self.watchlist.items()):
            pid = int(pid_str)
            # Check if process is still running
            is_running = pid in paths
            if is_running:
                audit = self.audit_process_family(pid, paths, ppid_map, children_map)
                items.append(audit)
                has_active_net = (audit.get("connections_count", 0) > 0) or (audit.get("traffic", {}).get("upload_bytes", 0) > 0)
                has_crit_violation = (audit.get("out_of_bounds_count", 0) > 0) or (audit.get("blocked_payloads_count", 0) > 0)
                if has_active_net and (has_crit_violation or audit.get("enforce_prompt")):
                    v_titles = [v.get("detail", "") for v in audit.get("violations", [])[:3]]
                    s_files = [f.get("path", "") for f in audit.get("flagged_files", [])[:4]]
                    a_conns = audit.get("active_connections", [])
                    rem_str = a_conns[0].get("remote", "公网目标") if a_conns else "后台外发连接"
                    geo_str = a_conns[0].get("geo_summary", "🌐 外网") if a_conns else "🌐 后台流量"
                    self.sentinel._maybe_trigger_gatekeeper(
                        pid=pid,
                        cmd=audit.get("command", f"PID {pid}"),
                        proc_path=paths.get(pid, ""),
                        lin={
                            "ppid": audit.get("ppid", 0),
                            "parent_name": audit.get("parent_name", ""),
                            "children": audit.get("family_processes", []),
                            "children_count": max(0, audit.get("family_size", 1) - 1),
                            "memory_formatted": audit.get("family_memory_formatted", "0 B"),
                            "family_memory_formatted": audit.get("family_memory_formatted", "0 B"),
                            "cpu_percent": audit.get("family_cpu_percent", 0.0),
                        },
                        remote=rem_str,
                        geo_summary=geo_str,
                        upload_audit={
                            "upload_formatted": audit.get("traffic", {}).get("upload_formatted", "0 B"),
                            "download_formatted": audit.get("traffic", {}).get("download_formatted", "0 B"),
                            "open_files": s_files,
                        },
                        trigger_type="🚨 重点监控进程敏感/越权上传拦截" if has_crit_violation else "👮 Gatekeeper 强制人工确认拦截",
                        reason="; ".join(v_titles) if v_titles else f"重点监控进程 {audit.get('command')} 发起外联传输，触发人工放行门禁。",
                    )
            else:
                items.append({
                    "pid": pid,
                    "command": cfg.get("command", "exited"),
                    "status": "EXITED",
                    "ppid": cfg.get("ppid", 0),
                    "parent_name": cfg.get("parent_name", ""),
                    "family_pids": [pid],
                    "family_size": 1,
                    "sandbox_dir": cfg.get("sandbox_dir", ""),
                    "violations": [],
                    "out_of_bounds_count": 0,
                    "blocked_payloads_count": 0,
                    "connections_count": 0,
                    "traffic": {
                        "upload_bytes": 0,
                        "upload_formatted": "0 B",
                        "download_bytes": 0,
                        "download_formatted": "0 B",
                        "upload_speed_formatted": "0 B/s",
                        "download_speed_formatted": "0 B/s",
                        "categories": ["已退出"],
                    },
                    "family_cpu_percent": 0.0,
                    "family_cpu_formatted": "0.0%",
                    "family_memory_kb": 0,
                    "family_memory_formatted": "0 B",
                    "family_processes": [],
                    "active_connections": [],
                })

        summary = {
            "total_families": len(items),
            "total_out_of_bounds": sum(it.get("out_of_bounds_count", 0) for it in items),
            "total_blocked_payloads": sum(it.get("blocked_payloads_count", 0) for it in items),
            "enforce_prompt_count": sum(1 for it in items if it.get("enforce_prompt")),
            "total_connections": sum(it.get("connections_count", 0) for it in items),
            "total_upload_bytes": sum(it.get("traffic", {}).get("upload_bytes", 0) for it in items),
            "total_download_bytes": sum(it.get("traffic", {}).get("download_bytes", 0) for it in items),
        }

        return {
            "ok": True,
            "summary": summary,
            "count": len(items),
            "items": items,
            "recent_intercepts": list(self.intercept_log)[-30:],
        }

    def pause_process(self, pid: int) -> Dict[str, Any]:
        """Pauses a process family using SIGSTOP (freeze)."""
        try:
            os.kill(pid, signal.SIGSTOP)
            return {"ok": True, "message": f"已成功挂起 (SIGSTOP) PID {pid}，等待授权确认"}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    def resume_process(self, pid: int) -> Dict[str, Any]:
        """Resumes a process family using SIGCONT (allow/放行)."""
        try:
            os.kill(pid, signal.SIGCONT)
            return {"ok": True, "message": f"已成功放行 (SIGCONT) PID {pid}，流量已恢复"}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    def get_candidate_processes(self, query: str = "") -> List[Dict[str, Any]]:
        """Returns candidate running processes for the user to pick and monitor."""
        q_clean = (query or "").lower().strip()
        if not q_clean and self._cached_candidates is not None:
            return self._cached_candidates
        res = self._perform_get_candidate_processes(query)
        if not q_clean:
            self._cached_candidates = res
            self._cached_candidates_ts = time.monotonic()
        return res

    def _perform_get_candidate_processes(self, query: str = "") -> List[Dict[str, Any]]:
        paths, ppid_map, children_map = self.sentinel._batch_load_process_tree()
        conns_by_pid = collections.defaultdict(list)
        for c in getattr(self.sentinel, "_cached_connections", []):
            p = c.get("pid")
            if p:
                conns_by_pid[p].append(c)

        user_pids = set()
        cmdline_by_pid = {}
        try:
            my_uid = str(os.getuid())
            out = subprocess.check_output(
                ["ps", "-u", my_uid, "-o", "pid,command"],
                text=True, errors="replace", stderr=subprocess.DEVNULL, timeout=1.0
            )
            for line in out.splitlines()[1:]:
                parts = line.strip().split(None, 1)
                if len(parts) >= 2 and parts[0].isdigit():
                    p = int(parts[0])
                    user_pids.add(p)
                    cmdline_by_pid[p] = parts[1]
        except Exception:
            pass

        q = (query or "").lower().strip()
        candidates = []
        seen = set()

        all_candidate_pids = set(conns_by_pid.keys()) | user_pids | set(paths.keys())

        system_noise = {
            "launchd", "distnoted", "cfprefsd", "secd", "usereventagent", "trustd",
            "fseventsd", "logd", "smd", "xpcproxy", "kernel_task", "systemsoundserverd"
        }

        for pid in all_candidate_pids:
            if pid <= 1 or pid in seen:
                continue
            seen.add(pid)

            full_path = paths.get(pid, cmdline_by_pid.get(pid, ""))
            cmd_name = os.path.basename(full_path.split()[0]) if full_path else f"proc_{pid}"
            cmd_lower = cmd_name.lower()

            if not q and cmd_lower in system_noise:
                continue

            conns = conns_by_pid.get(pid, [])
            has_net = len(conns) > 0
            is_app = ".app/" in full_path or ".app" in cmd_name
            app_title = ""
            if ".app" in full_path:
                try:
                    seg = full_path.split(".app")[0]
                    app_title = os.path.basename(seg)
                except Exception:
                    pass

            display_name = app_title or cmd_name
            search_haystack = f"{display_name} {cmd_name} {full_path} {pid}".lower()

            if q and q not in search_haystack:
                continue

            is_watched = str(pid) in self.watchlist
            mem_kb = self.sentinel._proc_mem_kb.get(pid, 0)
            mem_fmt = format_bytes(mem_kb * 1024, per_sec=False)
            cpu_pct = round(self.sentinel._proc_cpu.get(pid, 0.0), 1)
            ppid_val = ppid_map.get(pid, 0)
            pname_val = os.path.basename(paths.get(ppid_val, "")) if ppid_val > 1 else "launchd"
            ch_list = children_map.get(pid, [])

            candidates.append({
                "pid": pid,
                "name": display_name,
                "command": cmd_name,
                "path": full_path[:120],
                "has_network": has_net,
                "sockets_count": len(conns),
                "is_app": is_app,
                "is_watched": is_watched,
                "ppid": ppid_val,
                "parent_name": pname_val,
                "children_count": len(ch_list),
                "memory_kb": mem_kb,
                "memory_formatted": mem_fmt,
                "cpu_percent": cpu_pct,
            })

        def sort_key(c):
            return (
                1 if c["is_watched"] else 0,
                0 if c["has_network"] else (0 if c["is_app"] else 1),
                -c.get("memory_kb", 0),
                c["name"].lower()
            )

        candidates.sort(key=sort_key)
        return candidates[:120]

    def inspect_file(self, file_path: str, max_bytes: int = 65536) -> Dict[str, Any]:
        """Safely inspects file content, metadata, and checks analysis vault."""
        if not file_path or not os.path.exists(file_path):
            return {"ok": False, "error": f"文件不存在或无法访问: {file_path}"}

        try:
            st = os.stat(file_path)
            size = st.st_size
            mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime))
            _, ext = os.path.splitext(file_path.lower())
            
            # Detect mime
            mime_type, _ = mimetypes.guess_type(file_path)
            if not mime_type:
                mime_type = "application/octet-stream"

            read_len = min(size, max_bytes)
            with open(file_path, "rb") as f:
                raw_bytes = f.read(read_len)

            # Check if binary
            is_text = True
            if b"\x00" in raw_bytes:
                is_text = False
            else:
                try:
                    text_preview = raw_bytes.decode("utf-8")
                except UnicodeDecodeError:
                    try:
                        text_preview = raw_bytes.decode("gb18030")
                    except Exception:
                        is_text = False

            if is_text:
                preview = text_preview
            else:
                hex_lines = []
                chunk_len = 16
                for i in range(0, min(len(raw_bytes), 256), chunk_len):
                    chunk = raw_bytes[i:i + chunk_len]
                    hex_str = " ".join(f"{b:02x}" for b in chunk)
                    ascii_str = "".join(chr(b) if 32 <= b <= 126 else "." for b in chunk)
                    hex_lines.append(f"{i:08x}  {hex_str:<48}  |{ascii_str}|")
                preview = f"【二进制数据 Hex 预览 (前 {min(len(raw_bytes), 256)} 字节)】\n" + "\n".join(hex_lines)

            cached_analysis = self.vault.get_record(file_path)

            return {
                "ok": True,
                "path": file_path,
                "filename": os.path.basename(file_path),
                "size": size,
                "size_formatted": format_bytes(size, per_sec=False),
                "modified_at": mtime,
                "mime_type": mime_type,
                "is_text": is_text,
                "preview": preview,
                "truncated": size > max_bytes,
                "cached_analysis": cached_analysis,
            }
        except Exception as exc:
            return {"ok": False, "error": f"读取文件内容失败: {str(exc)}"}

    def analyze_file_with_llm(self, file_path: str, pid: int = 0, process_name: str = "", force: bool = False) -> Dict[str, Any]:
        """Performs deep security analysis using local LLM and stores in analysis vault."""
        if not force:
            cached = self.vault.get_record(file_path)
            if cached:
                return {"ok": True, "cached": True, "analysis": cached}

        insp = self.inspect_file(file_path, max_bytes=32768)
        if not insp.get("ok"):
            return insp

        preview_text = insp.get("preview", "")[:8000]
        size_str = insp.get("size_formatted", "0B")
        mime = insp.get("mime_type", "unknown")
        is_text = insp.get("is_text", False)

        prompt = f"""你是一名顶级网络安全与威胁情报审计专家。
当前系统重点监控进程正在读取/传输目标文件，请对该文件内容和访问行为进行严谨的安全与外联威胁审计：

【进程信息】PID: {pid} | 进程名: {process_name}
【文件路径】{file_path}
【文件大小】{size_str}
【文件属性】{mime} {'(纯文本文件)' if is_text else '(二进制大媒体/数据流)'}

【文件内容截取】:
```
{preview_text}
```

请严格按照以下四项结构给出深入客观的中文审计研判：
1. 【敏感内容与隐私研判】：是否包含 API Key、密码、私钥 Token、凭据、配置文件、隐私文件或商业敏感代码？
2. 【行为意图推断】：该进程读取或传输该文件的目的推断（如正常依赖加载、跨目录偷取外传、命令注入脚本、数据打包导出等）。
3. 【威胁研判定级】：请明确标出本次行为评级：[安全] / [低风险关注] / [中危告警] / [高危阻断]。
4. 【处置建议】：给出具体的安全处置策略（如立即阻断该后缀/跨目录访问、继续放行、终止进程族等）。"""

        try:
            # Query active local backend
            runtime_path = Path.home() / ".local" / "state" / "mtplx-qwen38" / "runtime.json"
            backend = "omlx"
            api_model = ""
            if runtime_path.exists():
                try:
                    with open(runtime_path, "r", encoding="utf-8") as f:
                        rdata = json.load(f)
                        backend = rdata.get("backend", "omlx")
                        api_model = rdata.get("api_model") or rdata.get("serve_model", "")
                except Exception:
                    pass

            report = ""
            if backend == "omlx":
                settings_file = Path.home() / ".omlx" / "settings.json"
                port = 7777
                api_key = ""
                if settings_file.exists():
                    try:
                        sdata = json.loads(settings_file.read_text(encoding="utf-8"))
                        port = sdata.get("server", {}).get("port", 7777)
                        api_key = sdata.get("auth", {}).get("api_key", "")
                    except Exception:
                        pass
                
                req_st = urllib.request.Request(f"http://127.0.0.1:{port}/api/status")
                if api_key:
                    req_st.add_header("Authorization", f"Bearer {api_key}")
                try:
                    with urllib.request.urlopen(req_st, timeout=2.0) as r:
                        st = json.loads(r.read().decode())
                        loaded = st.get("loaded_models", [])
                        if not loaded:
                            return {"ok": False, "error": "本地大模型当前处于空载待命状态（显存未载入模型）。请在控制台启动模型后再执行大模型深度分析。"}
                        if not api_model or api_model not in loaded:
                            api_model = loaded[0]
                except Exception:
                    return {"ok": False, "error": "无法连接 oMLX 服务，当前处于空载或停止状态。请先启动模型。"}

                req_chat = urllib.request.Request(
                    f"http://127.0.0.1:{port}/v1/chat/completions",
                    data=json.dumps({
                        "model": api_model,
                        "messages": [
                            {"role": "system", "content": "你是由 Serafina Sentinel 本地防御系统调用的安全威胁审计大模型引擎。请以客观专业的安全专家视角进行研判。"},
                            {"role": "user", "content": prompt}
                        ],
                        "max_tokens": 1200,
                        "temperature": 0.2
                    }).encode("utf-8"),
                    headers={"Content-Type": "application/json"}
                )
                if api_key:
                    req_chat.add_header("Authorization", f"Bearer {api_key}")
                with urllib.request.urlopen(req_chat, timeout=35) as resp:
                    resp_json = json.loads(resp.read().decode("utf-8"))
                    report = resp_json.get("choices", [{}])[0].get("message", {}).get("content", "").strip()

            elif backend == "lmstudio":
                req_chat = urllib.request.Request(
                    "http://127.0.0.1:1234/v1/chat/completions",
                    data=json.dumps({
                        "model": api_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 1200,
                        "temperature": 0.2
                    }).encode("utf-8"),
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req_chat, timeout=35) as resp:
                    resp_json = json.loads(resp.read().decode("utf-8"))
                    report = resp_json.get("choices", [{}])[0].get("message", {}).get("content", "").strip()

            else:
                req_chat = urllib.request.Request(
                    "http://127.0.0.1:8000/v1/chat/completions",
                    data=json.dumps({
                        "model": api_model or "active",
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 1200,
                        "temperature": 0.2
                    }).encode("utf-8"),
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req_chat, timeout=35) as resp:
                    resp_json = json.loads(resp.read().decode("utf-8"))
                    report = resp_json.get("choices", [{}])[0].get("message", {}).get("content", "").strip()

            if not report:
                return {"ok": False, "error": "本地大模型未返回分析结论"}

            risk_level = "安全"
            if "高危" in report:
                risk_level = "高危阻断"
            elif "中危" in report:
                risk_level = "中危告警"
            elif "低风险" in report:
                risk_level = "低风险关注"

            now_ts = int(time.time())
            record = {
                "path": file_path,
                "pid": pid,
                "process_name": process_name,
                "timestamp": now_ts,
                "datetime": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now_ts)),
                "risk_level": risk_level,
                "size_formatted": size_str,
                "mime_type": mime,
                "report": report,
            }
            self.vault.save_record(file_path, record)
            return {"ok": True, "cached": False, "analysis": record}
        except urllib.error.URLError as uerr:
            return {"ok": False, "error": f"连接本地大模型失败 (当前可能处于空载状态): {str(uerr)}"}
        except Exception as exc:
            return {"ok": False, "error": f"大模型安全分析异常: {str(exc)}"}

    def list_analysis_vault(self) -> Dict[str, Any]:
        """Returns all security audit records saved in the analysis vault."""
        recs = self.vault.list_records()
        return {
            "ok": True,
            "count": len(recs),
            "records": recs,
        }



# Global Singleton Instance
NETWORK_SENTINEL = NetworkSentinel()
PROCESS_WATCHLIST = ProcessWatchlistInterceptor(NETWORK_SENTINEL)

