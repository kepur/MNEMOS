import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from textstats import top_words, word_count, words  # noqa: E402


class WordsTests(unittest.TestCase):
    def test_punctuation_is_removed(self):
        self.assertEqual(words("Hello, world! Hello."), ["hello", "world", "hello"])

    def test_inner_apostrophe_kept(self):
        self.assertEqual(words("Don't stop"), ["don't", "stop"])

    def test_outer_apostrophes_removed(self):
        self.assertEqual(words("'quoted' words'"), ["quoted", "words"])

    def test_hyphen_splits(self):
        self.assertEqual(words("well-known fact"), ["well", "known", "fact"])

    def test_digits_are_words(self):
        self.assertEqual(words("route 66, exit 9"), ["route", "66", "exit", "9"])

    def test_count(self):
        self.assertEqual(word_count("a-b c... d!"), 4)


class TopWordsTests(unittest.TestCase):
    def test_ties_alphabetical(self):
        text = "pear apple pear apple fig kiwi"
        self.assertEqual(top_words(text, 3), [("apple", 2), ("pear", 2), ("fig", 1)])

    def test_counts_ignore_case_and_punctuation(self):
        self.assertEqual(top_words("Go! go, GO. stop", 1), [("go", 3)])


if __name__ == "__main__":
    unittest.main()
