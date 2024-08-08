# Seamless integration of [git hooks](https://pre-commit.com/) with [Nix](https://nixos.org/nix)

![pre-commit.png](pre-commit.png)

## Features

- **Trivial integration for Nix projects** (wires up a few things behind the scenes)

- Provide a low-overhead build of all the tooling available for the hooks to use
   (naive implementation of calling nix-shell does bring some latency when committing)

- **Common hooks for languages** like Python, Haskell, Elm, etc. [see all hook options](https://devenv.sh/?q=pre-commit.hooks)

- Run hooks **as part of development** and **on during CI**


## Getting started

### devenv.sh

https://devenv.sh/pre-commit-hooks/

## Flakes support

Given the following `flake.nix` example:

```nix
{
  description = "An example project.";

  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

  outputs = { self, nixpkgs, ... }@inputs:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      checks = forAllSystems (system: {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixpkgs-fmt.enable = true;
          };
        };
      });

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
        };
      });
    };
}
```

Add `/.pre-commit-config.yaml` to the `.gitignore`.

To run the all the hooks on CI:

```bash
nix flake check
```

To install pre-commit hooks developers would run:

```bash
nix develop
```

## Nix

1. **Optionally** use binary caches to avoid compilation:

   ```sh
   nix-env -iA cachix -f https://cachix.org/api/v1/install
   cachix use pre-commit-hooks
   ```

1. Integrate hooks to be built as part of `default.nix`:

   ```nix
    let
      nix-pre-commit-hooks = import (builtins.fetchTarball "https://github.com/cachix/pre-commit-hooks.nix/tarball/master");
    in {
      # Configured with the module options defined in `modules/pre-commit.nix`:
      pre-commit-check = nix-pre-commit-hooks.run {
        src = ./.;
        # If your hooks are intrusive, avoid running on each commit with a default_states like this:
        # default_stages = ["manual" "push"];
        hooks = {
          elm-format.enable = true;

          # override a package with a different version
          ormolu.enable = true;
          ormolu.package = pkgs.haskellPackages.ormolu;
          ormolu.settings.defaultExtensions = [ "lhs" "hs" ];

          # some hooks have more than one package, like clippy:
          clippy.enable = true;
          clippy.packageOverrides.cargo = pkgs.cargo;
          clippy.packageOverrides.clippy = tools.clippy;
          # some hooks provide settings
          clippy.settings.allFeatures = true;
        };
      };
    }
   ```

   Run `$ nix-build -A pre-commit-check` to perform the checks as a Nix derivation.

1. Integrate hooks to prepare environment as part of `shell.nix`:

   ```nix
    let
      pre-commit = import ./default.nix;
    in (import <nixpkgs> {}).mkShell {
      shellHook = ''
        ${pre-commit.pre-commit-check.shellHook}
      '';
      buildInputs = pre-commit.pre-commit-check.enabledPackages;
    }
   ```

   Add `/.pre-commit-config.yaml` to `.gitignore`.

   Run `$ nix-shell` to execute `shellHook` which will:

   - build the tools and `.pre-commit-config.yaml` config file symlink which
     references the binaries, for speed and safe garbage collection
   - provide the `pre-commit` executable that `git commit` will invoke

## Optional

### Direnv

`.envrc`:

```conf
use nix
```

## Hooks

### Nix

- [alejandra](https://github.com/kamadorueda/alejandra)
- [deadnix](https://github.com/astro/deadnix)
- [flake-checker](https://github.com/DeterminateSystems/flake-checker)
- [nil](https://github.com/oxalica/nil)
- [nixfmt](https://github.com/serokell/nixfmt/)
- [nixpkgs-fmt](https://github.com/nix-community/nixpkgs-fmt)
- [statix](https://github.com/nerdypepper/statix)

### Haskell

- [cabal-fmt](https://github.com/phadej/cabal-fmt)
- [fourmolu](https://github.com/parsonsmatt/fourmolu)
- [hindent](https://github.com/chrisdone/hindent)
- [hlint](https://github.com/ndmitchell/hlint)
- [hpack](https://github.com/sol/hpack)
- [ormolu](https://github.com/tweag/ormolu)
- [stylish-haskell](https://github.com/jaspervdj/stylish-haskell)

### C/C++/C#/ObjC

- [clang-format](https://clang.llvm.org/docs/ClangFormat.html)
- [clang-tidy](https://clang.llvm.org/extra/clang-tidy/)

You may restrict which languages should be formatted by `clang-format` using
`clang-format.types_or`. For example to check only C and C++ files:

```nix
clang-format = {
  enable = true;
  types_or = lib.mkForce [ "c" "c++" ];
};
```

Otherwise, the default internal list is used which includes everything that
clang-format supports.

### Clojure

- [cljfmt](https://github.com/weavejester/cljfmt)
- [zprint](https://github.com/kkinnear/zprint)

### Elm

- [elm-format](https://github.com/avh4/elm-format)
- [elm-review](https://github.com/jfmengels/elm-review)
- [elm-test](https://github.com/rtfeldman/node-test-runner)

### Elixir

- [credo](https://github.com/rrrene/credo)
- [dialyzer](https://github.com/jeremyjh/dialyxir)
- [mix-format](https://hexdocs.pm/mix/main/Mix.Tasks.Format.html)
- [mix-test](https://hexdocs.pm/mix/1.13/Mix.Tasks.Test.html)

### OCaml

- [dune-fmt](https://dune.build/)
- [dune-opam-sync](https://dune.build/)
- [ocp-indent](http://www.typerex.org/ocp-indent.html)
- [opam-lint](https://opam.ocaml.org/)

### Purescript

- [purty](https://gitlab.com/joneshf/purty)

### JavaScript/TypeScript

- [biome](https://biomejs.dev/)
- denofmt: Runs `deno fmt`
- denolint: Runs `deno lint`
- [eslint](https://github.com/eslint/eslint)
- rome: (alias to the biome hook)

### Python

- [autoflake](https://github.com/PyCQA/autoflake)
- [black](https://github.com/psf/black)
- [check-builtin-literals](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_builtin_literals.py)
- [check-docstring-first](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_docstring_first.py)
- [check-python](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_ast.py)
- [fix-encoding-pragma](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/fix_encoding_pragma.py)
- [flake8](https://github.com/PyCQA/flake8)
- [isort](https://github.com/PyCQA/isort)
- [mypy](https://github.com/python/mypy)
- [name-tests-test](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/tests_should_end_in_test.py)
- [pylint](https://github.com/PyCQA/pylint)
- [pyright](https://github.com/microsoft/pyright)
- [python-debug-statements](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/debug_statement_hook.py)
- [poetry](https://python-poetry.org/docs/pre-commit-hooks)
- [pyupgrade](https://github.com/asottile/pyupgrade)
- [ruff](https://github.com/charliermarsh/ruff)
- [ruff-format](https://github.com/charliermarsh/ruff)
- [sort-requirements-txt](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/requirements_txt_fixer.py)

### PHP

- [phpcbf](https://github.com/squizlabs/PHP_CodeSniffer)
- [php-cs-fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer)
- [phpcs](https://github.com/squizlabs/PHP_CodeSniffer)
- [phpstan](https://github.com/phpstan/phpstan)
- [psalm](https://github.com/vimeo/psalm)

### Rust

- cargo-check: Runs `cargo check`
- [clippy](https://github.com/rust-lang/rust-clippy)
- [rustfmt](https://github.com/rust-lang/rustfmt)

### Golang

- gofmt: Runs `go fmt`
- [golangci-lint](https://golangci-lint.run/)
- gotest: Runs `go test`
- [govet](https://pkg.go.dev/cmd/vet)
- [revive](https://github.com/mgechev/revive)
- [staticcheck](https://github.com/dominikh/go-tools)

### Julia

- [JuiaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl)

### Shell

- [bats](https://github.com/bats-core/bats-core)
- [beautysh](https://github.com/lovesegfault/beautysh)
- [shellcheck](https://github.com/koalaman/shellcheck)
- [shfmt](https://github.com/mvdan/sh)

### LaTeX

- [chktex](https://www.nongnu.org/chktex/)
- [lacheck](https://ctan.org/pkg/lacheck)
- [latexindent](https://github.com/cmhughes/latexindent.pl)

### Lua

- [luacheck](https://github.com/mpeterv/luacheck)
- [lua-ls](https://github.com/LuaLS/lua-language-server)
- [stylua](https://github.com/JohnnyMorganz/StyLua)

### HTML

- [html-tidy](https://github.com/htacg/tidy-html5)

### Markdown

- [markdownlint](https://github.com/DavidAnson/markdownlint)
- [mdl](https://github.com/markdownlint/markdownlint/)
- [mdsh](https://zimbatm.github.io/mdsh/)

### Terraform

- [tofu fmt](https://opentofu.org/docs/cli/commands/fmt/)
- [tflint](https://github.com/terraform-linters/tflint)

### YAML

- [check-yaml](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_yaml.py)
- [sort-simple-yaml](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/sort_simple_yaml.py)
- [yamlfmt](https://github.com/google/yamlfmt)
- [yamllint](https://github.com/adrienverge/yamllint)

### TOML

- [check-toml](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_toml.py)
- [taplo fmt](https://github.com/tamasfe/taplo)

### JSON

- [check-json](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_json.py)
- [pretty-format-json](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/pretty_format_json.py)

### Typst

- [typstfmt](https://github.com/astrale-sharp/typstfmt)
- [typstyle](https://github.com/Enter-tainer/typstyle)

### Fortran

- [fprettify](https://github.com/pseewald/fprettify)

### Spell checker

- [cspell](https://cspell.org/)
- [hunspell](https://github.com/hunspell/hunspell)
- [typos](https://github.com/crate-ci/typos)

### Link checker

- [lychee](https://github.com/lycheeverse/lychee)
- [mkdocs-linkcheck](https://github.com/byrnereese/linkchecker-mkdocs)

### Git

- [annex](https://git-annex.branchable.com/)
- [check-merge-conflicts](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_merge_conflict.py)
- [commitizen](https://github.com/commitizen-tools/commitizen)
- [convco](https://github.com/convco/convco)
- [forbid-new-submodules](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/forbid_new_submodules.py)
- [gptcommit](https://github.com/zurawiki/gptcommit)
- [no-commit-to-branch](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/no_commit_to_branch.py)

### Various other hooks

- [actionlint](https://github.com/rhysd/actionlint)
- [check-added-large-files](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_added_large_files.py)
- [check-case-conflicts](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_case_conflict.py)
- [check-executables-have-shebangs](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_executables_have_shebangs.py)
- [checkmake](https://github.com/mrtazz/checkmake)
- [check-shebang-scripts-are-executable](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_shebang_scripts_are_executable.py)
- [check-symlinks](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_symlinks.py)
- [check-vcs-permalinks](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_vcs_permalinks.py)
- [check-xml](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/check_xml.py)
- [cmake-format](https://cmake-format.readthedocs.io/en/latest/)
- [crystal](https://crystal-lang.org/reference/man/crystal#crystal-tool-format)
- [detect-aws-credentials](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/detect_aws_credentials.py)
- [detect-private-keys](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/detect_private_key.py)
- `dhall format`: built-in formatter
- [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker)
- [end-of-file-fixer](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/end_of_file_fixer.py)
- [fix-byte-order-marker](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/fix_byte_order_marker.py)
- [hadolint](https://github.com/hadolint/hadolint)
- [headache](https://github.com/frama-c/headache)
- [mixed-line-endings](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/mixed_line_ending.py)
- [mkdocs-linkcheck](https://github.com/byrnereese/linkchecker-mkdocs)
- [prettier](https://prettier.io)
- [sort-file-contents](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/file_contents_sorter.py)
- [tagref](https://github.com/stepchowfun/tagref)
- [topiary](https://github.com/tweag/topiary)
- [treefmt](https://github.com/numtide/treefmt)
- [trim-trailing-whitespace](https://github.com/pre-commit/pre-commit-hooks/blob/main/pre_commit_hooks/trailing_whitespace_fixer.py)

### Custom hooks

Sometimes it is useful to add a project specific command as an extra check that
is not part of the pre-defined set of hooks provided by this project.

Example configuration:

```nix
 let
   nix-pre-commit-hooks = import (builtins.fetchTarball "https://github.com/cachix/pre-commit-hooks.nix/tarball/master");
 in {
   pre-commit-check = nix-pre-commit-hooks.run {
     hooks = {
       # ...

       # Example custom hook for a C project using Make:
       unit-tests = {
         enable = true;

         # The name of the hook (appears on the report table):
         name = "Unit tests";

         # The command to execute (mandatory):
         entry = "make check";

         # The pattern of files to run on (default: "" (all))
         # see also https://pre-commit.com/#hooks-files
         files = "\\.(c|h)$";

         # List of file types to run on (default: [ "file" ] (all files))
         # see also https://pre-commit.com/#filtering-files-with-types
         # You probably only need to specify one of `files` or `types`:
         types = [ "text" "c" ];

         # Exclude files that were matched by these patterns (default: [ ] (none)):
         excludes = [ "irrelevant\\.c" ];

         # The language of the hook - tells pre-commit
         # how to install the hook (default: "system")
         # see also https://pre-commit.com/#supported-languages
         language = "system";

         # Set this to false to not pass the changed files
         # to the command (default: true):
         pass_filenames = false;

         # Which git hooks the command should run for (default: [ "pre-commit" ]):
         stages = ["pre-push"];
       };
     };
   };
 }
```

Custom hooks are defined with the same schema as [pre-defined
hooks](modules/pre-commit.nix).


## Contributing hooks

Everyone is encouraged to add new hooks.

<!-- TODO generate option docs -->
Have a look at the [existing hooks](modules/hooks.nix) and the [options](modules/pre-commit.nix).

There's no guarantee the hook will be accepted, but the general guidelines are:

- Nix closure of the tool should be small e.g. `< 50MB`. A problematic example:

```sh
  $ du -sh $(nix-build -A go)
  463M  /nix/store/v4ys4lrjngf62lvvrdbs7r9kbxh9nqaa-go-1.18.6
```

- The tool must not be very specific (e.g. language tooling is OK, but project specific tooling is not)
- The tool needs to live in a separate repository (even if a simple bash script, unless it's a oneliner)
