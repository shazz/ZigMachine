"""The one error the tool raises: a refusal, printed and turned into a non-zero exit."""

from __future__ import annotations


class CardError(Exception):
    """A file or request the tool refuses (wrong board, version skew, a name that exists, ...)."""
