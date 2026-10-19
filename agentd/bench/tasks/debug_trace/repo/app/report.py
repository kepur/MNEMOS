"""Summaries over ledger entries."""
from collections import defaultdict

from . import dates


def _summarise(entries, key):
    totals = defaultdict(float)
    for entry in entries:
        totals[key(entry.day)] += entry.amount
    return {k: round(v, 2) for k, v in sorted(totals.items())}


def weekly_summary(entries):
    """Total spent per ISO week, keys sorted chronologically."""
    return _summarise(entries, dates.week_key)


def monthly_summary(entries):
    """Total spent per calendar month."""
    return _summarise(entries, dates.month_key)


def by_category(entries):
    totals = defaultdict(float)
    for entry in entries:
        totals[entry.category] += entry.amount
    return sorted(((c, round(v, 2)) for c, v in totals.items()), key=lambda cv: (-cv[1], cv[0]))
