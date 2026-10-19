"""Aggregate tax reports."""
from dataclasses import dataclass, field

from .tax import compute_tax


def tax_by_region(sales):
    """``sales`` is a list of (region, amount, category); return {region: tax}."""
    totals = {}
    for region, amount, category in sales:
        totals[region] = round(totals.get(region, 0.0) + compute_tax(amount, region, category), 2)
    return dict(sorted(totals.items()))


def effective_rate(sales):
    gross = sum(amount for _, amount, _ in sales)
    if not gross:
        return 0.0
    return round(sum(compute_tax(a, r, c) for r, a, c in sales) / gross, 4)


def reports_helper_0(values, scale=1):
    """Internal helper #0 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def reports_helper_1(values, scale=2):
    """Internal helper #1 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def reports_helper_2(values, scale=3):
    """Internal helper #2 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def reports_helper_3(values, scale=4):
    """Internal helper #3 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def reports_helper_4(values, scale=5):
    """Internal helper #4 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def reports_helper_5(values, scale=6):
    """Internal helper #5 for reports: scale, clamp and round a list of numbers.

    Kept separate so the reports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

