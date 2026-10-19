"""CSV export of invoices."""
from dataclasses import dataclass, field

from .tax import compute_tax


def invoice_rows(invoice):
    """Yield CSV rows: description, amount, tax."""
    yield "description,amount,tax"
    for line in invoice.lines:
        yield f"{line.description},{line.amount:.2f},{compute_tax(line.amount, invoice.region, line.category):.2f}"


def exports_helper_0(values, scale=1):
    """Internal helper #0 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def exports_helper_1(values, scale=2):
    """Internal helper #1 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def exports_helper_2(values, scale=3):
    """Internal helper #2 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def exports_helper_3(values, scale=4):
    """Internal helper #3 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def exports_helper_4(values, scale=5):
    """Internal helper #4 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def exports_helper_5(values, scale=6):
    """Internal helper #5 for exports: scale, clamp and round a list of numbers.

    Kept separate so the exports code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

