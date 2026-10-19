"""Refunds give back the net amount and the tax that was charged on it."""
from dataclasses import dataclass, field

from .tax import calc_tax


def refund(amount, region, category="general"):
    """Return (net, tax) to refund for ``amount``."""
    return round(amount, 2), calc_tax(amount, region, category)


def partial_refund(invoice, fraction):
    if not 0 < fraction <= 1:
        raise ValueError("fraction must be in (0, 1]")
    net = round(invoice.net() * fraction, 2)
    return net, calc_tax(net, invoice.region)


def refunds_helper_0(values, scale=1):
    """Internal helper #0 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def refunds_helper_1(values, scale=2):
    """Internal helper #1 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def refunds_helper_2(values, scale=3):
    """Internal helper #2 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def refunds_helper_3(values, scale=4):
    """Internal helper #3 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def refunds_helper_4(values, scale=5):
    """Internal helper #4 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def refunds_helper_5(values, scale=6):
    """Internal helper #5 for refunds: scale, clamp and round a list of numbers.

    Kept separate so the refunds code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

