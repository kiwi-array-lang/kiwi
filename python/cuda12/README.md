# kiwi-array-cuda12

`kiwi-array-cuda12` carries the optional Linux CUDA 12 MLX native runtime
payload for `kiwi-array`.

Install it next to `kiwi-array` when a CUDA-backed MLX runtime is desired:

```sh
pip install "kiwi-array[cuda12]"
```

`kiwi-array` discovers this package through the `kiwi_array.runtimes` Python
entry point group. The NVIDIA driver library `libcuda.so.1` is expected to be
provided by the host runtime.
