"""Prints every non-ASCII character used in the app's scripts and content (font subset input).
Extra characters that are built at runtime (formatting) are listed in EXTRA."""
import glob

EXTRA = "°·²½θμ−…←→"
files = glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("experiments/**/*.gd", recursive=True) \
    + glob.glob("content/**/*.json", recursive=True)
chars = set(EXTRA)
for path in files:
    with open(path, encoding="utf-8") as handle:
        chars.update(c for c in handle.read() if ord(c) > 126)
print("".join(sorted(chars)))
