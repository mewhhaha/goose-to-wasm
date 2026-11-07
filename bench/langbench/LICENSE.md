The unchanged `mandelbrot.c` and `workload.yaml` come from Guillaume Leroy's
[langbench](https://github.com/leroyguillaume/langbench), revision
`f00181bd514606b140bf76ac461694a438c88270`.

Upstream declares MIT in `Cargo.toml` (`package.license = "MIT"`) and at the
end of `README.md`. Its author field is
`Guillaume Leroy <pro.guillaume.leroy@gmail.com>`. There is no LICENSE file
in that revision; this note records the declaration without inventing a notice.

`mandelbrot.goose` is a local scalar translation of that kernel. The exact
adaptations and input hashes are recorded in `manifest.json`.
