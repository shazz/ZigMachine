"""CARTS/shelf.txt: the board's own shelf plus the new carts' lines, never a second header."""

from __future__ import annotations

from collections.abc import Callable

from .errors import CardError


def _files(text: str, where: str) -> list[str]:
    """The FILE of every line; a comment only before the first line, no FILE twice."""
    files: list[str] = []
    for n, line in enumerate(text.splitlines(), 1):
        if line.startswith("#"):
            if files:
                raise CardError(f"{where}:{n}: a comment line in the middle of the shelf")
            continue
        if not line.strip():
            raise CardError(f"{where}:{n}: an empty line")
        files.append(line.split("\t")[0])
    if dup := sorted({f for f in files if files.count(f) > 1}):
        raise CardError(f"{where}: duplicate shelf lines: {', '.join(dup)}")
    return files


def merge(board_shelf: str, tags: list[str], record_for: Callable[[str], tuple[str, ...]]) -> tuple[str, list[str]]:
    """(the new shelf.txt, the tags it added). A cart already listed keeps the board's line."""
    have = set(_files(board_shelf, "the board's shelf.txt"))
    text = board_shelf if board_shelf.endswith("\n") or not board_shelf else board_shelf + "\n"
    added = []
    for tag in tags:
        rec = record_for(tag)
        if rec[0] in have:
            continue
        have.add(rec[0])
        text += "\t".join(rec) + "\n"
        added.append(tag)
    _files(text, "the merged shelf.txt")  # what we write must pass what we read
    return text, added
