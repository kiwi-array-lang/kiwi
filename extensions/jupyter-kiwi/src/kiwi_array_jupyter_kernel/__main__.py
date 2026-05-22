from __future__ import annotations

from ipykernel.kernelapp import IPKernelApp

from .kernel import KiwiKernel


def main() -> None:
    IPKernelApp.launch_instance(kernel_class=KiwiKernel)


if __name__ == "__main__":
    main()
