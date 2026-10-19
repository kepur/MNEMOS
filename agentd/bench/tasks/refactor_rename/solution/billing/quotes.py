"""Price quotes shown to customers before checkout."""
from dataclasses import dataclass, field

from .tax import compute_tax


def quote(amount, region, category="general"):
    """Human readable quote including tax."""
    tax_due = compute_tax(amount, region, category)
    return f"{amount:.2f} + tax {tax_due:.2f} = {amount + tax_due:.2f}"


def quotes_helper_0(values, scale=1):
    """Internal helper #0 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def quotes_helper_1(values, scale=2):
    """Internal helper #1 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def quotes_helper_2(values, scale=3):
    """Internal helper #2 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def quotes_helper_3(values, scale=4):
    """Internal helper #3 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def quotes_helper_4(values, scale=5):
    """Internal helper #4 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def quotes_helper_5(values, scale=6):
    """Internal helper #5 for quotes: scale, clamp and round a list of numbers.

    Kept separate so the quotes code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

