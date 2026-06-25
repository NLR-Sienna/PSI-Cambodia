using Literate

# Cambodia-data-prep.jl is a Literate-format script -> generate & execute its notebook.
Literate.notebook("Cambodia-data-prep.jl", execute = true)

# PSI-Cambodia.jl is a jupytext "percent"-format slideshow deck (carries RISE
# `slideshow={...}` cell metadata). Literate cannot parse jupytext's
# `name=... slideshow={...}` cell metadata (it throws "type Nothing has no field
# captures" in parse_nbmeta), so build this notebook with jupytext -- its native,
# round-trip tool -- which preserves the slide metadata.
run(`jupytext --to notebook --output PSI-Cambodia.ipynb PSI-Cambodia.jl`)
