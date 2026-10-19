"""Process CPU & Memory Resource Monitor with Parent-Child Family Aggregation.

Granularly tracks:
1. Per-process CPU % and RSS Memory usage.
2. Parent-child process tree (PPID -> PID -> Children).
3. Family total CPU & RAM aggregation.
4. Identifies user applications (.app) vs system processes vs background daemons.
"""

import os
import subprocess
import collections
import time
from typing import Dict, List, Any, Tuple, Optional


def format_bytes(b: int) -> str:
    if b < 1024:
        return f"{b} B"
    elif b < 1024 * 1024:
        return f"{b / 1024.0:.1f} KB"
    elif b < 1024 * 1024 * 1024:
        return f"{b / (1024.0 * 1024.0):.1f} MB"
    else:
        return f"{b / (1024.0 * 1024.0 * 1024.0):.2f} GB"


class ProcessResourceMonitor:
    def __init__(self):
        self._last_scan_time = 0.0
        self._cache_data = None
        self._cache_ttl = 1.0  # cache for 1 second to avoid heavy polling
        self._total_ram_bytes = self._get_total_ram()

    def _get_total_ram(self) -> int:
        try:
            out = subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True, stderr=subprocess.DEVNULL)
            return int(out.strip())
        except Exception:
            return 96 * 1024 * 1024 * 1024  # default 96GB

    def scan_all_processes(self) -> Tuple[Dict[int, Dict[str, Any]], Dict[int, List[int]]]:
        """Scans all processes using ps and returns (procs_dict, children_map)."""
        procs: Dict[int, Dict[str, Any]] = {}
        children_map: Dict[int, List[int]] = collections.defaultdict(list)

        try:
            out = subprocess.check_output(
                ["ps", "-eo", "pid,ppid,uid,user,%cpu,rss,comm"],
                text=True, stderr=subprocess.DEVNULL, timeout=1.5
            )
            for line in out.splitlines()[1:]:
                parts = line.strip().split(None, 6)
                if len(parts) >= 7 and parts[0].isdigit() and parts[1].isdigit():
                    p = int(parts[0])
                    pp = int(parts[1])
                    uid = int(parts[2])
                    usr = parts[3]
                    try:
                        cpu = float(parts[4])
                    except ValueError:
                        cpu = 0.0
                    try:
                        rss_kb = int(parts[5])
                    except ValueError:
                        rss_kb = 0
                    comm = parts[6]
                    base_name = os.path.basename(comm)

                    # Extract app name if inside a .app bundle
                    app_name = ""
                    if ".app" in comm:
                        try:
                            seg = comm.split(".app")[0]
                            app_name = os.path.basename(seg)
                        except Exception:
                            pass

                    procs[p] = {
                        "pid": p,
                        "ppid": pp,
                        "uid": uid,
                        "user": usr,
                        "is_root": (uid == 0 or usr == "root"),
                        "cpu_percent": cpu,
                        "rss_kb": rss_kb,
                        "rss_bytes": rss_kb * 1024,
                        "memory_formatted": format_bytes(rss_kb * 1024),
                        "comm": comm,
                        "app_name": app_name,
                        "name": app_name or base_name,
                        "binary_name": base_name,
                        "is_app": bool(app_name or ".app" in comm),
                    }
                    children_map[pp].append(p)
        except Exception:
            pass

        return procs, children_map

    def get_top_process_families(self, sort_by: str = "cpu", limit: int = 35) -> Dict[str, Any]:
        """Aggregates processes by family and returns top consumers sorted by CPU or Memory."""
        now = time.monotonic()
        if self._cache_data and (now - self._last_scan_time < self._cache_ttl):
            data = dict(self._cache_data)
            # Re-sort if sort_by differs
            if sort_by == "memory":
                data["families"] = sorted(data["families"], key=lambda x: x["family_memory_kb"], reverse=True)[:limit]
            else:
                data["families"] = sorted(data["families"], key=lambda x: x["family_cpu_percent"], reverse=True)[:limit]
            return data

        procs, children_map = self.scan_all_processes()
        if not procs:
            return {"ok": False, "error": "无法获取系统进程列表", "families": []}

        # Identify family roots:
        # On macOS, PID 1 (launchd) is the direct parent of almost all user apps and daemons.
        # Direct children of launchd (ppid == 1) or standalone .apps are independent family roots.
        roots_set = set()
        for pid, p in procs.items():
            ppid = p["ppid"]
            if pid == 1:
                roots_set.add(pid)
            elif ppid <= 1:
                roots_set.add(pid)
            elif p["is_app"]:
                # Check if parent is also the same .app
                parent_p = procs.get(ppid)
                if not parent_p or not parent_p.get("is_app") or parent_p.get("app_name") != p.get("app_name"):
                    roots_set.add(pid)

        # In addition, include any standalone high-resource child whose parent is launchd or system
        for pid, p in procs.items():
            if pid not in roots_set and (p["cpu_percent"] > 5.0 or p["rss_kb"] > 300000):
                if p["ppid"] not in roots_set:
                    roots_set.add(pid)

        families = []

        for r_pid in roots_set:
            if r_pid not in procs:
                continue
            r_proc = procs[r_pid]

            family_members = [r_proc]
            seen_in_family = {r_pid}

            # PID 1 (launchd) should not recursively swallow all direct child applications
            if r_pid != 1:
                queue = list(children_map.get(r_pid, []))
                while queue:
                    c_pid = queue.pop(0)
                    if c_pid in seen_in_family or c_pid not in procs:
                        continue
                    seen_in_family.add(c_pid)
                    # If this child is its own distinct app root, don't aggregate it into parent
                    c_proc = procs[c_pid]
                    if c_pid in roots_set and c_proc.get("is_app") and c_proc.get("app_name") != r_proc.get("app_name"):
                        continue
                    family_members.append(c_proc)
                    queue.extend(children_map.get(c_pid, []))

            # Compute family totals
            total_cpu = sum(m["cpu_percent"] for m in family_members)
            total_rss_kb = sum(m["rss_kb"] for m in family_members)
            total_rss_bytes = total_rss_kb * 1024
            mem_pct = (total_rss_bytes / float(self._total_ram_bytes)) * 100.0 if self._total_ram_bytes > 0 else 0.0

            # Format children details (excluding root itself)
            children_details = []
            for m in family_members:
                if m["pid"] != r_pid:
                    children_details.append({
                        "pid": m["pid"],
                        "ppid": m["ppid"],
                        "name": m["binary_name"] or m["name"],
                        "binary_name": m["binary_name"],
                        "cpu_percent": round(m["cpu_percent"], 1),
                        "memory_kb": m["rss_kb"],
                        "memory_formatted": m["memory_formatted"],
                        "is_root": m["is_root"],
                        "comm": m["comm"],
                    })

            # Sort children by CPU then Memory
            children_details.sort(key=lambda x: (x["cpu_percent"], x["memory_kb"]), reverse=True)

            ppid = r_proc["ppid"]
            p_name = os.path.basename(procs[ppid]["comm"]) if ppid in procs else ("launchd" if ppid == 1 else "")

            families.append({
                "pid": r_pid,
                "name": r_proc["name"],
                "binary_name": r_proc["binary_name"],
                "comm": r_proc["comm"],
                "ppid": ppid,
                "parent_name": p_name,
                "is_root": r_proc["is_root"],
                "is_app": r_proc["is_app"],
                "family_size": len(family_members),
                "family_pids": [m["pid"] for m in family_members],
                "family_cpu_percent": round(total_cpu, 1),
                "family_cpu_formatted": f"{total_cpu:.1f}%",
                "family_memory_kb": total_rss_kb,
                "family_memory_bytes": total_rss_bytes,
                "family_memory_formatted": format_bytes(total_rss_bytes),
                "family_memory_percent": round(mem_pct, 1),
                "children": children_details,
                "children_count": len(children_details),
            })

        # Calculate system summary metrics
        total_sys_cpu = round(sum(p["cpu_percent"] for p in procs.values()), 1)
        total_sys_rss_kb = sum(p["rss_kb"] for p in procs.values())
        total_sys_ram_gb = round((total_sys_rss_kb * 1024) / (1024.0 ** 3), 2)
        total_phys_gb = round(self._total_ram_bytes / (1024.0 ** 3), 1)

        result_families = sorted(families, key=lambda x: x["family_cpu_percent"], reverse=True)

        res = {
            "ok": True,
            "timestamp": time.time(),
            "summary": {
                "total_cpu_percent": total_sys_cpu,
                "total_cpu_formatted": f"{total_sys_cpu:.1f}%",
                "total_memory_used_gb": total_sys_ram_gb,
                "total_physical_memory_gb": total_phys_gb,
                "total_memory_percent": round((total_sys_ram_gb / total_phys_gb) * 100.0, 1) if total_phys_gb > 0 else 0.0,
                "total_processes_count": len(procs),
                "total_families_count": len(families),
            },
            "families": result_families,
        }

        self._cache_data = res
        self._last_scan_time = now

        if sort_by == "memory":
            res_copy = dict(res)
            res_copy["families"] = sorted(families, key=lambda x: x["family_memory_kb"], reverse=True)[:limit]
            return res_copy
        else:
            res_copy = dict(res)
            res_copy["families"] = result_families[:limit]
            return res_copy

    def get_family_resources(self, pid: int) -> Dict[str, Any]:
        """Fetches detailed CPU and Memory resource breakdown for a specific PID and its children."""
        procs, children_map = self.scan_all_processes()
        if pid not in procs:
            return {
                "ok": False,
                "pid": pid,
                "family_cpu_percent": 0.0,
                "family_cpu_formatted": "0.0%",
                "family_memory_formatted": "0 B",
                "members": [],
            }

        target = procs[pid]
        family_pids = [pid]
        queue = list(children_map.get(pid, []))
        seen = {pid}

        while queue:
            c = queue.pop(0)
            if c not in seen and c in procs:
                seen.add(c)
                family_pids.append(c)
                queue.extend(children_map.get(c, []))

        members = [procs[p] for p in family_pids if p in procs]
        tot_cpu = sum(m["cpu_percent"] for m in members)
        tot_rss_kb = sum(m["rss_kb"] for m in members)

        return {
            "ok": True,
            "pid": pid,
            "family_size": len(members),
            "family_cpu_percent": round(tot_cpu, 1),
            "family_cpu_formatted": f"{tot_cpu:.1f}%",
            "family_memory_kb": tot_rss_kb,
            "family_memory_formatted": format_bytes(tot_rss_kb * 1024),
            "members": [
                {
                    "pid": m["pid"],
                    "ppid": m["ppid"],
                    "name": m["name"],
                    "cpu_percent": round(m["cpu_percent"], 1),
                    "memory_formatted": m["memory_formatted"],
                    "is_root": m["is_root"],
                    "command": m["comm"],
                }
                for m in members
            ],
        }


PROCESS_RESOURCE_MONITOR = ProcessResourceMonitor()
