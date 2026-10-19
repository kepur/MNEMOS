"""Serafina 5.0 Startup & Login Items Manager for macOS.

Comprehensive auditing and control of:
  * User LaunchAgents (~/Library/LaunchAgents)
  * System LaunchAgents (/Library/LaunchAgents)
  * macOS Login Items (via System Events)
  * Safe toggle mechanism (renaming .plist <-> .plist.disabled & launchctl bootout/bootstrap)
  * Whitelist protection for core system components and model runtime
  * Batch disable for non-essential third-party background services
"""
from __future__ import annotations

import json
import os
import plistlib
import subprocess
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

DISABLED_LOGIN_ITEMS_FILE = Path.home() / ".serafina_disabled_login_items.json"

# Core essential services that must NEVER be batch-disabled
ESSENTIAL_PATTERNS = {
    "local.codex.model-switcher",
    "local.ainervault",
    "mtplx",
    "com.apple.",
    "系统看板",
    "loginwindow",
}

# Category classification mapping
CATEGORY_KEYWORDS = {
    "cloud_disk": ["netdisk", "onedrive", "dropbox", "cloud", "baidunetdisk", "googledrive"],
    "game_launcher": ["epicgames", "steam", "riot", "ea", "battlenet", "gog"],
    "updater": ["updater", "update", "wake", "keystone", "autoupdate", "crashpad"],
    "creative": ["adobe", "ccxprocess", "figma", "blender", "sketch"],
    "developer": ["redis", "docker", "gateway", "runner", "postgres", "mysql", "hermes"],
    "chat_ai": ["claude", "openai", "atlas", "chatgpt", "deepseek"],
    "transfer": ["android", "filetransfer", "airdrop"],
}


def classify_category(name: str, path: str) -> str:
    low = f"{name} {path}".lower()
    for cat, kws in CATEGORY_KEYWORDS.items():
        if any(kw in low for kw in kws):
            return cat
    return "general"


def is_essential_item(name: str, path: str, label: str) -> bool:
    combined = f"{name} {path} {label}".lower()
    return any(p in combined for p in ESSENTIAL_PATTERNS)


FRIENDLY_INFO: Dict[str, Tuple[str, str]] = {
    "netdisk_service": ("百度网盘后台服务", "☁️"),
    "com.epicgames.launcher": ("Epic Games 启动器", "🎮"),
    "com.adobe.ccxprocess": ("Adobe CC 协同后台", "🎨"),
    "com.adobe.AdobeCreativeCloud": ("Adobe Creative Cloud", "🎨"),
    "com.google.GoogleUpdater.wake": ("Google 自动唤醒更新", "🔄"),
    "com.google.keystone.agent": ("Google Keystone 代理", "🔄"),
    "com.google.keystone.xpcservice": ("Google Keystone XPC", "🔄"),
    "com.openai.atlas.update-helper": ("ChatGPT Atlas 更新守护", "🤖"),
    "homebrew.mxcl.redis": ("Redis 本地数据库服务", "⚙️"),
    "local.codex.model-switcher": ("Codex 模型切换器", "❖"),
    "local.ainervault.mtplx-health": ("Serafina 健康监控守护", "🛡️"),
    "local.ainervault.mtplx-qwen38": ("Serafina 30B 模型守护", "🛡️"),
    "ai.hermes.gateway": ("Hermes Agent 网关", "⚙️"),
    "com.ainerops.host-runner": ("AinerOps 宿主执行器", "⚙️"),
    "us.zoom.updater": ("Zoom 会议后台更新", "🔄"),
    "us.zoom.updater.login.check": ("Zoom 登录自检代理", "🔄"),
    "com.microsoft.OneDriveStandaloneUpdater": ("OneDrive 独立更新", "☁️"),
    "com.microsoft.SyncReporter": ("OneDrive 状态分析报告", "☁️"),
    "com.microsoft.update.agent": ("Microsoft AutoUpdate 代理", "🔄"),
    "Android File Transfer Agent": ("Android 文件传输助手", "📱"),
    "Claude": ("Claude AI 桌面客户端", "🤖"),
    "系统看板": ("Serafina 系统监控看板", "📊"),
    "QoderWork": ("Qoder 工作空间守护", "💼"),
    "org.chromium.chromoting": ("Chrome 远程桌面主机", "🖥️"),
}

DEFAULT_CATEGORY_ICONS = {
    "cloud_disk": "☁️",
    "game_launcher": "🎮",
    "creative": "🎨",
    "developer": "⚙️",
    "chat_ai": "🤖",
    "updater": "🔄",
    "transfer": "📱",
    "general": "📦",
}


def resolve_display_info(name: str, label: str, cat: str) -> Tuple[str, str]:
    if name in FRIENDLY_INFO:
        return FRIENDLY_INFO[name]
    if label in FRIENDLY_INFO:
        return FRIENDLY_INFO[label]
    for k, v in FRIENDLY_INFO.items():
        if k in name or k in label:
            return v
    return name, DEFAULT_CATEGORY_ICONS.get(cat, "📦")


@dataclass
class StartupItem:
    id: str
    name: str
    display_name: str
    icon: str
    label: str
    item_type: str  # "launch_agent" | "login_item"
    scope: str      # "user" | "system"
    file_path: str
    target_exec: str
    enabled: bool
    running: bool
    pid: Optional[int]
    is_essential: bool
    can_toggle: bool
    category: str
    summary_note: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class StartupManager:
    """Manages macOS LaunchAgents and Login Items."""

    def __init__(self):
        self.user_uid = os.getuid()

    def _get_running_launchctl_services(self) -> Dict[str, int]:
        """Maps launchctl label to PID (or 0 if loaded without active PID)."""
        mapping: Dict[str, int] = {}
        try:
            out = subprocess.check_output(["launchctl", "list"], text=True, timeout=2.5)
            for line in out.splitlines()[1:]:
                parts = line.split("\t")
                if len(parts) >= 3:
                    pid_str, _, label = parts[0], parts[1], parts[2]
                    try:
                        mapping[label] = int(pid_str) if pid_str != "-" else 0
                    except ValueError:
                        mapping[label] = 0
        except Exception:
            pass
        return mapping

    def _parse_plist(self, plist_path: Path) -> Dict[str, Any]:
        """Safely parses a launchd plist file."""
        try:
            with open(plist_path, "rb") as f:
                return plistlib.load(f)
        except Exception:
            return {}

    def _load_disabled_login_items(self) -> Dict[str, str]:
        """Loads saved disabled login items mapping: {name: path}."""
        if not DISABLED_LOGIN_ITEMS_FILE.exists():
            return {}
        try:
            with open(DISABLED_LOGIN_ITEMS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _save_disabled_login_items(self, mapping: Dict[str, str]) -> None:
        try:
            with open(DISABLED_LOGIN_ITEMS_FILE, "w", encoding="utf-8") as f:
                json.dump(mapping, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def _get_active_login_items(self) -> List[Tuple[str, str]]:
        """Queries active Login Items via AppleScript."""
        cmd = """
tell application "System Events"
    set outList to {}
    try
        set allItems to every login item
        repeat with anItem in allItems
            set itemName to name of anItem
            set itemPath to ""
            try
                set itemPath to path of anItem
            end try
            set end of outList to itemName & ":::" & itemPath
        end repeat
    end try
    return outList
end tell
"""
        try:
            res = subprocess.check_output(["osascript", "-e", cmd], text=True, timeout=3.5).strip()
            items: List[Tuple[str, str]] = []
            if res:
                for entry in res.split(", "):
                    if ":::" in entry:
                        n, p = entry.split(":::", 1)
                        clean_path = p.strip()
                        if clean_path == "missing value":
                            clean_path = ""
                        items.append((n.strip(), clean_path))
            return items
        except Exception:
            return []

    def list_items(self) -> Dict[str, Any]:
        """Audits all LaunchAgents and Login Items on this Mac."""
        running_services = self._get_running_launchctl_services()
        items: List[StartupItem] = []

        # 1. Audit User LaunchAgents (~/Library/LaunchAgents)
        user_agents_dir = Path.home() / "Library/LaunchAgents"
        if user_agents_dir.exists():
            for p in sorted(user_agents_dir.glob("*.plist*")):
                is_disabled = p.name.endswith(".disabled")
                is_plist = p.name.endswith(".plist") or is_disabled
                if not is_plist:
                    continue

                data = self._parse_plist(p)
                label = data.get("Label") or p.name.replace(".plist.disabled", "").replace(".plist", "")
                args = data.get("ProgramArguments") or []
                prog = data.get("Program") or (args[0] if args else "")

                # Check if running
                pid: Optional[int] = None
                running = False
                if label in running_services:
                    p_num = running_services[label]
                    if p_num > 0:
                        pid = p_num
                        running = True
                    else:
                        running = True  # Loaded in launchd

                enabled = not is_disabled
                essential = is_essential_item(p.name, prog, label)
                cat = classify_category(p.name, prog)

                item_id = f"launchagent:user:{p.name}"
                stem = p.name.replace(".plist.disabled", "").replace(".plist", "")
                disp_name, icon = resolve_display_info(stem, label, cat)
                items.append(StartupItem(
                    id=item_id,
                    name=stem,
                    display_name=disp_name,
                    icon=icon,
                    label=label,
                    item_type="launch_agent",
                    scope="user",
                    file_path=str(p),
                    target_exec=str(prog),
                    enabled=enabled,
                    running=running,
                    pid=pid,
                    is_essential=essential,
                    can_toggle=True,
                    category=cat,
                    summary_note="用户开机守护进程 (LaunchAgent)"
                ))

        # 2. Audit System LaunchAgents (/Library/LaunchAgents)
        sys_agents_dir = Path("/Library/LaunchAgents")
        if sys_agents_dir.exists():
            for p in sorted(sys_agents_dir.glob("*.plist*")):
                is_disabled = p.name.endswith(".disabled")
                is_plist = p.name.endswith(".plist") or is_disabled
                if not is_plist:
                    continue

                data = self._parse_plist(p)
                label = data.get("Label") or p.name.replace(".plist.disabled", "").replace(".plist", "")
                args = data.get("ProgramArguments") or []
                prog = data.get("Program") or (args[0] if args else "")

                pid: Optional[int] = None
                running = False
                if label in running_services:
                    p_num = running_services[label]
                    if p_num > 0:
                        pid = p_num
                        running = True
                    else:
                        running = True

                enabled = not is_disabled
                essential = is_essential_item(p.name, prog, label)
                cat = classify_category(p.name, prog)

                # /Library is root-owned, so user cannot toggle without sudo
                can_toggle = os.access(p.parent, os.W_OK) and os.access(p, os.W_OK)

                item_id = f"launchagent:system:{p.name}"
                stem = p.name.replace(".plist.disabled", "").replace(".plist", "")
                disp_name, icon = resolve_display_info(stem, label, cat)
                items.append(StartupItem(
                    id=item_id,
                    name=stem,
                    display_name=disp_name,
                    icon=icon,
                    label=label,
                    item_type="launch_agent",
                    scope="system",
                    file_path=str(p),
                    target_exec=str(prog),
                    enabled=enabled,
                    running=running,
                    pid=pid,
                    is_essential=essential,
                    can_toggle=can_toggle,
                    category=cat,
                    summary_note="系统级全局代理 (/Library/LaunchAgents)"
                ))

        # 3. Audit macOS Login Items
        active_login = self._get_active_login_items()
        disabled_login = self._load_disabled_login_items()

        # Active Login Items
        for name, path_str in active_login:
            essential = is_essential_item(name, path_str, name)
            cat = classify_category(name, path_str)
            item_id = f"loginitem:{name}"
            disp_name, icon = resolve_display_info(name, name, cat)
            items.append(StartupItem(
                id=item_id,
                name=name,
                display_name=disp_name,
                icon=icon,
                label=name,
                item_type="login_item",
                scope="user",
                file_path=path_str,
                target_exec=path_str,
                enabled=True,
                running=True,
                pid=None,
                is_essential=essential,
                can_toggle=True,
                category=cat,
                summary_note="macOS 桌面登录自启项"
            ))

        # Disabled Login Items
        for name, path_str in disabled_login.items():
            # If not already present in active
            if any(item.name == name and item.item_type == "login_item" for item in items):
                continue
            essential = is_essential_item(name, path_str, name)
            cat = classify_category(name, path_str)
            item_id = f"loginitem:{name}"
            disp_name, icon = resolve_display_info(name, name, cat)
            items.append(StartupItem(
                id=item_id,
                name=name,
                display_name=disp_name,
                icon=icon,
                label=name,
                item_type="login_item",
                scope="user",
                file_path=path_str,
                target_exec=path_str,
                enabled=False,
                running=False,
                pid=None,
                is_essential=essential,
                can_toggle=True,
                category=cat,
                summary_note="已禁用的 macOS 登录自启项"
            ))

        # Summary
        total = len(items)
        enabled_count = sum(1 for i in items if i.enabled)
        disabled_count = sum(1 for i in items if not i.enabled)
        running_count = sum(1 for i in items if i.running)
        essential_count = sum(1 for i in items if i.is_essential)
        third_party_enabled = sum(1 for i in items if i.enabled and not i.is_essential and i.can_toggle)

        return {
            "ok": True,
            "timestamp": time.time(),
            "summary": {
                "total": total,
                "enabled_count": enabled_count,
                "disabled_count": disabled_count,
                "running_count": running_count,
                "essential_count": essential_count,
                "third_party_enabled_count": third_party_enabled,
            },
            "items": [i.to_dict() for i in items],
        }

    def toggle_item(self, item_id: str, enable: bool) -> Tuple[bool, str]:
        """Toggles a single startup item."""
        if item_id.startswith("launchagent:user:"):
            filename = item_id.replace("launchagent:user:", "")
            user_dir = Path.home() / "Library/LaunchAgents"

            if enable:
                target_file = user_dir / filename
                if not target_file.exists():
                    # check if exists with .disabled
                    if not filename.endswith(".disabled"):
                        target_file = user_dir / f"{filename}.disabled"
                if not target_file.exists():
                    return False, f"未找到指定的文件: {filename}"

                # Rename to .plist
                dest_name = target_file.name.replace(".disabled", "")
                dest_file = user_dir / dest_name
                try:
                    if target_file != dest_file:
                        target_file.rename(dest_file)
                    # Load in launchd
                    subprocess.run(["launchctl", "bootstrap", f"gui/{self.user_uid}", str(dest_file)],
                                   capture_output=True, text=True, timeout=2.0)
                    return True, f"已启用启动项: {dest_name}"
                except Exception as exc:
                    return False, f"启用失败: {exc}"
            else:
                # Disable
                target_file = user_dir / filename
                if not target_file.exists() and filename.endswith(".disabled"):
                    return True, "该项已经是禁用状态"
                if not target_file.exists():
                    return False, f"未找到指定的文件: {filename}"

                # Extract label
                data = self._parse_plist(target_file)
                label = data.get("Label") or target_file.stem

                # Check essential
                prog = data.get("Program") or ""
                if is_essential_item(target_file.name, prog, label):
                    return False, f"无法禁用核心受保护服务: {label}"

                # Unload from launchd
                try:
                    subprocess.run(["launchctl", "bootout", f"gui/{self.user_uid}/{label}"],
                                   capture_output=True, text=True, timeout=2.0)
                except Exception:
                    pass

                # Rename to .disabled
                dest_file = user_dir / f"{target_file.name}.disabled"
                try:
                    if not target_file.name.endswith(".disabled"):
                        target_file.rename(dest_file)
                    return True, f"已关闭启动项: {target_file.name}"
                except Exception as exc:
                    return False, f"关闭失败: {exc}"

        elif item_id.startswith("loginitem:"):
            item_name = item_id.replace("loginitem:", "")
            disabled_map = self._load_disabled_login_items()

            if is_essential_item(item_name, "", item_name) and not enable:
                return False, f"无法禁用受保护的系统登录项: {item_name}"

            if enable:
                # Re-add login item if path exists
                saved_path = disabled_map.get(item_name, "")
                if saved_path and saved_path != "missing value" and os.path.exists(saved_path):
                    cmd = f'tell application "System Events" to make login item at end with properties {{path:"{saved_path}", hidden:false}}'
                    try:
                        subprocess.run(["osascript", "-e", cmd], check=True, capture_output=True, timeout=3.0)
                    except Exception as exc:
                        return False, f"恢复登录项失败: {exc}"
                if item_name in disabled_map:
                    del disabled_map[item_name]
                    self._save_disabled_login_items(disabled_map)
                return True, f"已启用登录项: {item_name}"
            else:
                # Get path first
                active_items = dict(self._get_active_login_items())
                item_path = active_items.get(item_name, "")
                if item_path:
                    disabled_map[item_name] = item_path
                    self._save_disabled_login_items(disabled_map)

                # Remove from System Events
                cmd = f'tell application "System Events" to delete login item "{item_name}"'
                try:
                    subprocess.run(["osascript", "-e", cmd], capture_output=True, text=True, timeout=3.0)
                    return True, f"已关闭登录项: {item_name}"
                except Exception as exc:
                    return False, f"关闭登录项失败: {exc}"

        return False, f"不支持或未识别的启动项类型: {item_id}"

    def batch_disable_non_essential(self) -> Dict[str, Any]:
        """Disables all third-party, non-essential user LaunchAgents and Login Items."""
        status = self.list_items()
        disabled_items: List[str] = []
        skipped_items: List[str] = []
        failed_items: List[Dict[str, str]] = []

        for item in status.get("items", []):
            item_id = item["id"]
            name = item["name"]
            is_essential = item["is_essential"]
            can_toggle = item["can_toggle"]
            enabled = item["enabled"]

            if not enabled:
                continue

            if is_essential or not can_toggle:
                skipped_items.append(f"{name} (受保护核心服务)")
                continue

            # Attempt disable
            ok, msg = self.toggle_item(item_id, enable=False)
            if ok:
                disabled_items.append(name)
            else:
                failed_items.append({"name": name, "reason": msg})

        return {
            "ok": True,
            "count_disabled": len(disabled_items),
            "disabled_items": disabled_items,
            "skipped_protected_count": len(skipped_items),
            "skipped_items": skipped_items,
            "failed_items": failed_items,
            "message": f"成功批量关闭 {len(disabled_items)} 项自启程序，保护跳过 {len(skipped_items)} 项核心服务",
        }


# Global Singleton Instance
STARTUP_MANAGER = StartupManager()
