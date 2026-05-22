from __future__ import annotations

from setuptools import setup
from setuptools.dist import Distribution
from wheel.bdist_wheel import bdist_wheel as _bdist_wheel


class BinaryDistribution(Distribution):
    def has_ext_modules(self) -> bool:
        return True


class BdistWheel(_bdist_wheel):
    def finalize_options(self) -> None:
        super().finalize_options()
        self.root_is_pure = False
        self.python_tag = "py3"

    def get_tag(self) -> tuple[str, str, str]:
        _, _, plat = super().get_tag()
        return "py3", "none", plat


setup(cmdclass={"bdist_wheel": BdistWheel}, distclass=BinaryDistribution)
