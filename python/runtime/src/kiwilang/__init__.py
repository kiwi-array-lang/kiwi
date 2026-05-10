from __future__ import annotations

__version__ = "0.2.33"


def load_ipython_extension(ipython):
    from .notebook import load_ipython_extension as load

    load(ipython)
