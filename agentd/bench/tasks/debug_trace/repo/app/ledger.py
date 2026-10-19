"""Load ledger entries from CSV-like lines: date,amount,category"""
from dataclasses import dataclass
from datetime import date

from . import categories, dates


@dataclass(frozen=True)
class Entry:
    day: date
    amount: float
    category: str


def parse_line(line):
    parts = [p.strip() for p in line.split(",")]
    if len(parts) != 3:
        raise ValueError(f"expected 3 fields: {line!r}")
    day, amount, category = parts
    return Entry(dates.parse(day), round(float(amount), 2), categories.normalise(category))


def load(lines):
    entries = []
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        try:
            entries.append(parse_line(line))
        except ValueError as exc:
            raise ValueError(f"line {number}: {exc}") from None
    return entries
