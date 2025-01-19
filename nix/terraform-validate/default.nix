{ writeScriptBin, opentofu }:

writeScriptBin "terraform-validate" ''#!/usr/bin/env bash
set -x
  for arg in "$@"; do
    dirname "$arg"
  done \
    | sort \
    | uniq \
    | while read dir; do
        ${opentofu}/bin/tofu -chdir="$dir" validate
      done
''
