"""Compare benchmark result files side by side.

    python3 -m agentd.bench.compare results/A.json results/B.json ...
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def cell(task):
    if not task:
        return '—'
    server = task.get('server') or {}
    mark = '✅' if task.get('passed') else ('⏱' if task.get('timed_out') else '❌')
    ratio = server.get('cached_ratio')
    return (f"{mark} {task.get('wall_s', 0):.0f}s · {server.get('requests', 0)} req · "
            f"prefill {server.get('prefill_s', 0):.0f}s · cache {ratio if ratio is not None else '-'}")


def main(paths):
    reports = [json.loads(Path(p).read_text()) for p in paths]
    names = sorted({n for r in reports for n in r['tasks']})
    header = '| task | ' + ' | '.join(r['tag'] for r in reports) + ' |'
    print(header)
    print('|' + '---|' * (len(reports) + 1))
    for name in names:
        print(f'| {name} | ' + ' | '.join(cell(r['tasks'].get(name)) for r in reports) + ' |')
    totals = []
    for r in reports:
        tasks = r['tasks'].values()
        passed = sum(t['passed'] for t in tasks)
        wall = sum(t['wall_s'] for t in tasks)
        prefill = sum((t.get('server') or {}).get('prefill_s', 0) for t in tasks)
        totals.append(f'**{passed}/{len(r["tasks"])}** · {wall:.0f}s · prefill {prefill:.0f}s')
    print('| **total** | ' + ' | '.join(totals) + ' |')


if __name__ == '__main__':
    main(sys.argv[1:])
