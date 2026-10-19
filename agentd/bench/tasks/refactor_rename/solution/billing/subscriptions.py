"""Recurring subscriptions billed monthly."""
from dataclasses import dataclass, field

from .tax import compute_tax


@dataclass
class Subscription:
    plan: str
    monthly: float
    region: str

    def monthly_tax(self):
        return compute_tax(self.monthly, self.region)

    def yearly_cost(self, months_free=0):
        months = 12 - months_free
        return round(months * (self.monthly + self.monthly_tax()), 2)


def subscriptions_helper_0(values, scale=1):
    """Internal helper #0 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def subscriptions_helper_1(values, scale=2):
    """Internal helper #1 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def subscriptions_helper_2(values, scale=3):
    """Internal helper #2 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def subscriptions_helper_3(values, scale=4):
    """Internal helper #3 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def subscriptions_helper_4(values, scale=5):
    """Internal helper #4 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def subscriptions_helper_5(values, scale=6):
    """Internal helper #5 for subscriptions: scale, clamp and round a list of numbers.

    Kept separate so the subscriptions code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

