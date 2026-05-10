# kiwilang

`kiwilang` is the Python runtime package for Kiwi. It contains the small
`kiwi_bridge` ctypes wrapper plus, in platform wheels, the native
`libkiwi_bridge` runtime and its bundled dynamic dependencies.

Source checkouts can still build and load `libkiwi_bridge` from
`../../zig-out/lib`. Wheel installs should not need Zig, MLX headers, or a Kiwi
source tree.

In IPython-compatible hosted notebooks, load the extension and use either the
descriptive or short magic:

```python
%load_ext kiwilang
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

Vega-Lite outputs use the notebook's default light rendering by default. Set
`KIWI_VEGALITE_THEME=dark` before rendering if you want the HTML fallback to use
Vega-Embed's dark theme.
