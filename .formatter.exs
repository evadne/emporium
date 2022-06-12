[
  import_deps: [:phoenix, :membrane_core],
  inputs: [
    "apps/*/{lib,config,test}/**/*.{ex,exs}",
    "apps/*/priv/*/seeds.exs",
    "apps/*/mix.exs",
    "*.{ex,exs}",
    "{config,lib,scripts,test}/**/*.{ex,exs}"
  ],
  subdirectories: ["priv/*/migrations"]
]
