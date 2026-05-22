# kiwi-array

`kiwi-array` is the Python loader package for Kiwi. It contains the
`kiwi_array.bridge` ctypes wrapper, IPython magics, runtime backend discovery,
and a small `kiwi` CLI launcher that execs the real native CLI from an
installed backend payload.

By default, installing `kiwi-array` also installs `kiwi-array-host`, the
conservative host backend. Accelerated backends are explicit extras:
`kiwi-array[cpu]`, `kiwi-array[metal]`, or `kiwi-array[cuda12]`.

In IPython-compatible hosted notebooks, load the extension and use either the
descriptive or short magic:

```python
%load_ext kiwi_array
```

```text
%%k
x:1 2 3
+/x
```

`%%kiwi` is registered as the explicit alias for `%%k`.

Use the lightweight diagnostics when sharing hosted notebook setup cells:

```python
%kinfo
%ksmoke
```

On a GPU runtime, `%ksmoke --gpu` also pushes a small MLX-backed vector through
the native bridge and evaluates a gradient over it.

Runtime payload packages such as `kiwi-array-host`, `kiwi-array-metal`, and
`kiwi-array-cuda12` register themselves through the `kiwi_array.runtimes` entry
point group. Set `KIWI_RUNTIME=host`, `KIWI_RUNTIME=cpu`,
`KIWI_RUNTIME=metal`, `KIWI_RUNTIME=cuda12`, or leave `KIWI_RUNTIME=auto` to
control runtime selection.

Vega-Lite outputs use the notebook's default light rendering by default. Set
`KIWI_VEGALITE_THEME=dark` before rendering if you want the HTML fallback to use
Vega-Embed's dark theme.
