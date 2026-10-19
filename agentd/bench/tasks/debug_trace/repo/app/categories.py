"""Category names are free text in the source files; normalise them."""

ALIASES = {
    "groceries": "food",
    "supermarket": "food",
    "restaurant": "food",
    "bus": "transport",
    "train": "transport",
    "taxi": "transport",
    "power": "utilities",
    "water": "utilities",
}


def normalise(name):
    key = " ".join(name.lower().split())
    return ALIASES.get(key, key or "other")
