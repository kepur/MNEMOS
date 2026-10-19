"""Small text statistics helpers."""
import re

_WORD = re.compile(r"[a-z0-9]+(?:'[a-z]+)*")


def words(text):
    """Return the words in ``text``, lowercased, without punctuation.

    Rules:
    - Letters and digits form words; every other character separates words.
    - An apostrophe between two letters stays inside the word ("don't" is
      one word), any other apostrophe is a separator.
    - Hyphens separate words ("well-known" -> "well", "known").
    """
    return _WORD.findall(text.lower())


def word_count(text):
    return len(words(text))


def top_words(text, n=3):
    """Return the ``n`` most frequent words as ``(word, count)`` pairs.

    Higher counts come first; words with the same count are ordered
    alphabetically.
    """
    counts = {}
    for w in words(text):
        counts[w] = counts.get(w, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:n]
