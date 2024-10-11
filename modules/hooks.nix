{ config, lib, pkgs, hookModule, ... }:
let
  inherit (config) hooks tools settings;
  cfg = config;
  inherit (lib) flatten mapAttrs mapAttrsToList mkDefault mkOption mkRemovedOptionModule mkRenamedOptionModule types;

  cargoManifestPathArg =
    lib.optionalString
      (settings.rust.cargoManifestPath != null)
      "--manifest-path ${lib.escapeShellArg settings.rust.cargoManifestPath}";

  mkCmdArgs = predActionList:
    lib.concatStringsSep
      " "
      (builtins.foldl'
        (acc: entry:
          acc ++ lib.optional (builtins.elemAt entry 0) (builtins.elemAt entry 1))
        [ ]
        predActionList);

  migrateBinPathToPackage = hook: binPath:
    if hook.settings.binPath == null
    then "${hook.package}${binPath}"
    else hook.settings.binPath;

  texliveCombine = pkgs.texlive.combine (
    lib.mergeAttrsList
      (
        map
          (package: { ${package} = pkgs.texlive.${package}; })
          (
            builtins.filter
              (hook: hooks.${hook}.enable)
              [ "chktex" "lacheck" "latexindent" ]
          )
      )
    // { inherit (pkgs.texlive) scheme-minimal; }
  );
in
{
  imports =
    # Rename `settings.<name>.package` to `hooks.<name>.package`
    map (name: mkRenamedOptionModule [ "settings" name "package" ] [ "hooks" name "package" ]) [ "alejandra" "eclint" "flynt" "mdl" "treefmt" ]
    # These options were renamed in 20fbe2c9731810b1020572a2cb6cbf64e3dd3873 to avoid shadowing
    ++ map (name: mkRenamedOptionModule [ "settings" name "config" ] [ "hooks" name "settings" "configuration" ]) [ "lua-ls" "markdownlint" "typos" "vale" ]
    ++ [
      (mkRemovedOptionModule [ "settings" "yamllint" "relaxed" ] ''
        This option has been removed. Use `hooks.yamllint.settings.preset = "relaxed"`.
      '')
    ]
    # Manually rename options that had a package or a config option
    ++ flatten (mapAttrsToList (name: map (o: mkRenamedOptionModule [ "settings" name o ] [ "hooks" name "settings" o ])) {
      "alejandra" = [ "check" "exclude" "threads" "verbosity" ];
      "eclint" = [ "fix" "summary" "color" "exclude" "verbosity" ];
      "flynt" = [ "aggressive" "binPath" "dry-run" "exclude" "fail-on-change" "line-length" "no-multiline" "quiet" "string" "transform-concats" "verbose" ];
      "mdl" = [ "configPath" "git-recurse" "ignore-front-matter" "json" "rules" "rulesets" "show-aliases" "warnings" "skip-default-ruleset" "style" "tags" "verbose" ];
      "lua-ls" = [ "checklevel" ];
      "typos" = [ "binary" "color" "configPath" "diff" "exclude" "format" "hidden" "ignored-words" "locale" "no-check-filenames" "no-check-files" "no-unicode" "quiet" "verbose" "write" ];
      "vale" = [ "configPath" "flags" ];
      "yamllint" = [ "configPath" ];
    })
    # Rename `rome` hook to `biome`, since `biome` was being used in both hooks
    ++ [ (mkRenamedOptionModule [ "settings" "rome" ] [ "hooks" "biome" "settings" ]) ]
    # Rename the remaining `settings.<name>` to `hooks.<name>.settings`
    ++ map (name: mkRenamedOptionModule [ "settings" name ] [ "hooks" name "settings" ])
      [ "ansible-lint" "autoflake" "biome" "clippy" "cmake-format" "credo" "deadnix" "denofmt" "denolint" "dune-fmt" "eslint" "flake8" "headache" "hlint" "hpack" "isort" "latexindent" "lychee" "mkdocs-linkcheck" "mypy" "nixfmt" "ormolu" "php-cs-fixer" "phpcbf" "phpcs" "phpstan" "prettier" "psalm" "pylint" "pyright" "pyupgrade" "revive" "statix" ];

  options.hookModule = lib.mkOption {
    type = types.deferredModule;
    internal = true;
    description = ''
      Base module that must be loaded into each hook.
    '';
  };

  config.hookModule = {
    imports = [ ./hook.nix ];
    config._module.args.default_stages = cfg.default_stages;
  };
  config._module.args.hookModule = config.hookModule;

  # PLEASE keep this sorted alphabetically.
  options.settings = {
    rust.cargoManifestPath = mkOption {
      type = types.nullOr types.str;
      description = "Path to Cargo.toml";
      default = null;
    };
  };

  # PLEASE keep this sorted alphabetically.
  options.hooks =
    {
      alejandra = mkOption {
        description = "alejandra hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            check =
              mkOption {
                type = types.bool;
                description = "Check if the input is already formatted and disable writing in-place the modified content";
                default = false;
                example = true;
              };
            exclude =
              mkOption {
                type = types.listOf types.str;
                description = "Files or directories to exclude from formatting.";
                default = [ ];
                example = [ "flake.nix" "./templates" ];
              };
            threads =
              mkOption {
                type = types.nullOr types.int;
                description = "Number of formatting threads to spawn.";
                default = null;
                example = 8;
              };
            verbosity =
              mkOption {
                type = types.enum [ "normal" "quiet" "silent" ];
                description = "Whether informational messages or all messages should be hidden or not.";
                default = "normal";
                example = "quiet";
              };
          };
        };
      };
      ansible-lint = mkOption {
        description = "ansible-lint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath = mkOption {
              type = types.str;
              description = "Path to the YAML configuration file.";
              # an empty string translates to use default configuration of the
              # underlying ansible-lint binary
              default = "";
            };
            subdir = mkOption {
              type = types.str;
              description = "Path to the Ansible subdirectory.";
              default = "";
            };
          };
        };
      };
      autoflake = mkOption {
        description = "autoflake hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "Path to autoflake binary.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.autoflake}/bin/autoflake"
                '';
              };

            flags =
              mkOption {
                type = types.str;
                description = "Flags passed to autoflake.";
                default = "--in-place --expand-star-imports --remove-duplicate-keys --remove-unused-variables";
              };
          };
        };
      };
      biome = mkOption {
        description = "biome hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.path;
                description = "`biome` binary path. E.g. if you want to use the `biome` in `node_modules`, use `./node_modules/.bin/biome`.";
                default = null;
                defaultText = "\${tools.biome}/bin/biome";
              };

            write =
              mkOption {
                type = types.bool;
                description = "Whether to edit files inplace.";
                default = true;
              };

            configPath = mkOption {
              type = types.str;
              description = "Path to the configuration JSON file";
              # an empty string translates to use default configuration of the
              # underlying biome binary (i.e biome.json if exists)
              default = "";
            };
          };
        };
      };
      black = mkOption {
        description = "black hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            flags = mkOption {
              type = types.str;
              description = "Flags passed to black. See all available [here](https://black.readthedocs.io/en/stable/usage_and_configuration/the_basics.html#command-line-options).";
              default = "";
              example = "--skip-magic-trailing-comma";
            };
          };
        };
      };
      clippy = mkOption {
        description = "clippy hook";
        type = types.submodule
          ({ config, ... }: {
            imports = [ hookModule ];
            options.packageOverrides = {
              cargo = mkOption {
                type = types.package;
                description = "The cargo package to use";
              };
              clippy = mkOption {
                type = types.package;
                description = "The clippy package to use";
              };
            };
            options.settings = {
              denyWarnings = mkOption {
                type = types.bool;
                description = "Fail when warnings are present";
                default = false;
              };
              offline = mkOption {
                type = types.bool;
                description = "Run clippy offline";
                default = true;
              };
              allFeatures = mkOption {
                type = types.bool;
                description = "Run clippy with --all-features";
                default = false;
              };
              extraArgs = mkOption {
                type = types.str;
                description = "Additional arguments to pass to clippy";
                default = "";
              };
            };

            config.extraPackages = [
              config.packageOverrides.cargo
              config.packageOverrides.clippy
            ];
          });
      };
      cmake-format = mkOption {
        description = "cmake-format hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath = mkOption {
              type = types.str;
              description = "Path to the configuration file (.json,.python,.yaml)";
              default = "";
              example = ".cmake-format.json";
            };
          };
        };
      };
      credo = mkOption {
        description = "credo hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            strict =
              mkOption {
                type = types.bool;
                description = "Whether to auto-promote the changes.";
                default = true;
              };
          };
        };
      };
      deadnix = mkOption {
        description = "deadnix hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            edit =
              mkOption {
                type = types.bool;
                description = "Remove unused code and write to source file.";
                default = false;
              };

            exclude =
              mkOption {
                type = types.listOf types.str;
                description = "Files to exclude from analysis.";
                default = [ ];
              };

            hidden =
              mkOption {
                type = types.bool;
                description = "Recurse into hidden subdirectories and process hidden .*.nix files.";
                default = false;
              };

            noLambdaArg =
              mkOption {
                type = types.bool;
                description = "Don't check lambda parameter arguments.";
                default = false;
              };

            noLambdaPatternNames =
              mkOption {
                type = types.bool;
                description = "Don't check lambda pattern names (don't break nixpkgs `callPackage`).";
                default = false;
              };

            noUnderscore =
              mkOption {
                type = types.bool;
                description = "Don't check any bindings that start with a `_`.";
                default = false;
              };

            quiet =
              mkOption {
                type = types.bool;
                description = "Don't print a dead code report.";
                default = false;
              };
          };
        };
      };
      denofmt = mkOption {
        description = "denofmt hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            write =
              mkOption {
                type = types.bool;
                description = "Whether to edit files inplace.";
                default = true;
              };
            configPath =
              mkOption {
                type = types.str;
                description = "Path to the configuration JSON file";
                # an empty string translates to use default configuration of the
                # underlying deno binary (i.e deno.json or deno.jsonc)
                default = "";
              };
          };
        };
      };
      denolint = mkOption {
        description = "denolint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            format =
              mkOption {
                type = types.enum [ "default" "compact" "json" ];
                description = "Output format.";
                default = "default";
              };

            configPath =
              mkOption {
                type = types.str;
                description = "Path to the configuration JSON file";
                # an empty string translates to use default configuration of the
                # underlying deno binary (i.e deno.json or deno.jsonc)
                default = "";
              };
          };
        };
      };
      dune-fmt = mkOption {
        description = "dune-fmt hook";
        type = types.submodule
          ({ config, ... }: {
            imports = [ hookModule ];
            options.settings = {
              auto-promote =
                mkOption {
                  type = types.bool;
                  description = "Whether to auto-promote the changes.";
                  default = true;
                };

              extraRuntimeInputs =
                mkOption {
                  type = types.listOf types.package;
                  description = "Extra runtimeInputs to add to the environment, eg. `ocamlformat`.";
                  default = [ ];
                };
            };

            config.extraPackages = config.settings.extraRuntimeInputs;
          });
      };
      eclint = mkOption {
        description = "eclint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            fix =
              mkOption {
                type = types.bool;
                description = "Modify files in place rather than showing the errors.";
                default = false;
              };
            summary =
              mkOption {
                type = types.bool;
                description = "Only show number of errors per file.";
                default = false;
              };
            color =
              mkOption {
                type = types.enum [ "auto" "always" "never" ];
                description = "When to generate colored output.";
                default = "auto";
              };
            exclude =
              mkOption {
                type = types.listOf types.str;
                description = "Filter to exclude files.";
                default = [ ];
              };
            verbosity =
              mkOption {
                type = types.enum [ 0 1 2 3 4 ];
                description = "Log level verbosity";
                default = 0;
              };
          };
        };
      };
      eslint = mkOption {
        description = "eslint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.path;
                description =
                  "`eslint` binary path. E.g. if you want to use the `eslint` in `node_modules`, use `./node_modules/.bin/eslint`.";
                default = null;
                defaultText = lib.literalExpression "\${tools.eslint}/bin/eslint";
              };

            extensions =
              mkOption {
                type = types.str;
                description =
                  "The pattern of files to run on, see [https://pre-commit.com/#hooks-files](https://pre-commit.com/#hooks-files).";
                default = "\\.js$";
              };
          };
        };
      };
      flake8 = mkOption {
        description = "flake8 hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "flake8 binary path. Should be used to specify flake8 binary from your Nix-managed Python environment.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.flake8}/bin/flake8"
                '';
              };
            extendIgnore =
              mkOption {
                type = types.listOf types.str;
                description = "List of additional ignore codes";
                default = [ ];
                example = [ "E501" ];
              };
            format =
              mkOption {
                type = types.str;
                description = "Output format.";
                default = "default";
              };
          };
        };
      };
      flynt = mkOption {
        description = "flynt hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            aggressive =
              mkOption {
                type = types.bool;
                description = "Include conversions with potentially changed behavior.";
                default = false;
              };
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "flynt binary path. Can be used to specify the flynt binary from an existing Python environment.";
                default = null;
                defaultText = "\${hooks.flynt.package}/bin/flynt";
              };
            dry-run =
              mkOption {
                type = types.bool;
                description = "Do not change files in-place and print diff instead.";
                default = false;
              };
            exclude =
              mkOption {
                type = types.listOf types.str;
                description = "Ignore files with given strings in their absolute path.";
                default = [ ];
              };
            fail-on-change =
              mkOption {
                type = types.bool;
                description = "Fail when diff is not empty (for linting purposes).";
                default = true;
              };
            line-length =
              mkOption {
                type = types.nullOr types.int;
                description = "Convert expressions spanning multiple lines, only if the resulting single line will fit into this line length limit.";
                default = null;
              };
            no-multiline =
              mkOption {
                type = types.bool;
                description = "Convert only single line expressions.";
                default = false;
              };
            quiet =
              mkOption {
                type = types.bool;
                description = "Run without output.";
                default = false;
              };
            string =
              mkOption {
                type = types.bool;
                description = "Interpret the input as a Python code snippet and print the converted version.";
                default = false;
              };
            transform-concats =
              mkOption {
                type = types.bool;
                description = "Replace string concatenations with f-strings.";
                default = false;
              };
            verbose =
              mkOption {
                type = types.bool;
                description = "Run with verbose output.";
                default = false;
              };
          };
        };
      };
      headache = mkOption {
        description = "headache hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            header-file = mkOption {
              type = types.str;
              description = "Path to the header file.";
              default = ".header";
            };
          };
        };
      };
      hlint = mkOption {
        description = "hlint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            hintFile =
              mkOption {
                type = types.nullOr types.path;
                description = "Path to hlint.yaml. By default, hlint searches for .hlint.yaml in the project root.";
                default = null;
              };
          };
        };
      };
      hpack = mkOption {
        description = "hpack hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            silent =
              mkOption {
                type = types.bool;
                description = "Whether generation should be silent.";
                default = false;
              };
          };
        };
      };
      isort = mkOption {
        description = "isort hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            profile =
              mkOption {
                type = types.enum [ "" "black" "django" "pycharm" "google" "open_stack" "plone" "attrs" "hug" "wemake" "appnexus" ];
                description = "Built-in profiles to allow easy interoperability with common projects and code styles.";
                default = "";
              };
            flags =
              mkOption {
                type = types.str;
                description = "Flags passed to isort. See all available [here](https://pycqa.github.io/isort/docs/configuration/options.html).";
                default = "";
              };
          };
        };
      };
      latexindent = mkOption {
        description = "latexindent hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            flags =
              mkOption {
                type = types.str;
                description = "Flags passed to latexindent. See available flags [here](https://latexindentpl.readthedocs.io/en/latest/sec-how-to-use.html#from-the-command-line)";
                default = "--local --silent --overwriteIfDifferent";
              };
          };
        };
      };
      lacheck = mkOption {
        description = "lacheck hook";
        type = types.submodule {
          imports = [ hookModule ];
        };
      };
      lua-ls = mkOption {
        description = "lua-ls hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            checklevel = mkOption {
              type = types.enum [ "Error" "Warning" "Information" "Hint" ];
              description =
                "The diagnostic check level";
              default = "Warning";
            };
            configuration = mkOption {
              type = types.attrs;
              description =
                "See https://github.com/LuaLS/lua-language-server/wiki/Configuration-File#luarcjson";
              default = { };
            };
          };
        };
      };
      lychee = mkOption {
        description = "lychee hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath =
              mkOption {
                type = types.str;
                description = "Path to the config file.";
                default = "";
              };
            flags =
              mkOption {
                type = types.str;
                description = "Flags passed to lychee. See all available [here](https://lychee.cli.rs/#/usage/cli).";
                default = "";
              };
          };
        };
      };
      markdownlint = mkOption {
        description = "markdownlint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configuration =
              mkOption {
                type = types.attrs;
                description =
                  "See https://github.com/DavidAnson/markdownlint/blob/main/schema/.markdownlint.jsonc";
                default = { };
              };
          };
        };
      };
      mdl = mkOption {
        description = "mdl hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath =
              mkOption {
                type = types.str;
                description = "The configuration file to use.";
                default = "";
              };
            git-recurse =
              mkOption {
                type = types.bool;
                description = "Only process files known to git when given a directory.";
                default = false;
              };
            ignore-front-matter =
              mkOption {
                type = types.bool;
                description = "Ignore YAML front matter.";
                default = false;
              };
            json =
              mkOption {
                type = types.bool;
                description = "Format output as JSON.";
                default = false;
              };
            rules =
              mkOption {
                type = types.listOf types.str;
                description = "Markdown rules to use for linting. Per default all rules are processed.";
                default = [ ];
              };
            rulesets =
              mkOption {
                type = types.listOf types.str;
                description = "Specify additional ruleset files to load.";
                default = [ ];
              };
            show-aliases =
              mkOption {
                type = types.bool;
                description = "Show rule alias instead of rule ID when viewing rules.";
                default = false;
              };
            warnings =
              mkOption {
                type = types.bool;
                description = "Show Kramdown warnings.";
                default = false;
              };
            skip-default-ruleset =
              mkOption {
                type = types.bool;
                description = "Do not load the default markdownlint ruleset. Use this option if you only want to load custom rulesets.";
                default = false;
              };
            style =
              mkOption {
                type = types.str;
                description = "Select which style mdl uses.";
                default = "default";
              };
            tags =
              mkOption {
                type = types.listOf types.str;
                description = "Markdown rules to use for linting containing the given tags. Per default all rules are processed.";
                default = [ ];
              };
            verbose =
              mkOption {
                type = types.bool;
                description = "Increase verbosity.";
                default = false;
              };
          };
        };
      };
      mkdocs-linkcheck = mkOption {
        description = "mkdocs-linkcheck hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.path;
                description = "mkdocs-linkcheck binary path. Should be used to specify the mkdocs-linkcheck binary from your Nix-managed Python environment.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.mkdocs-linkcheck}/bin/mkdocs-linkcheck"
                '';
              };

            path =
              mkOption {
                type = types.str;
                description = "Path to check";
                default = "";
              };

            local-only =
              mkOption {
                type = types.bool;
                description = "Whether to only check local links.";
                default = false;
              };

            recurse =
              mkOption {
                type = types.bool;
                description = "Whether to recurse directories under path.";
                default = false;
              };

            extension =
              mkOption {
                type = types.str;
                description = "File extension to scan for.";
                default = "";
              };

            method =
              mkOption {
                type = types.enum [ "get" "head" ];
                description = "HTTP method to use when checking external links.";
                default = "get";
              };
          };
        };
      };
      mypy = mkOption {
        description = "mypy hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "Mypy binary path. Should be used to specify the mypy executable in an environment containing your typing stubs.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.mypy}/bin/mypy"
                '';
              };
          };
        };
      };
      nixfmt = mkOption {
        description = "Deprecated nixfmt hook";
        visible = false;
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            width =
              mkOption {
                type = types.nullOr types.int;
                description = "Line width.";
                default = null;
              };
          };
        };
      };
      nixfmt-classic = mkOption {
        description = "nixfmt (classic) hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            width =
              mkOption {
                type = types.nullOr types.int;
                description = "Line width.";
                default = null;
              };
          };
        };
      };
      nixfmt-rfc-style = mkOption {
        description = "nixfmt (RFC 166 style) hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            width =
              mkOption {
                type = types.nullOr types.int;
                description = "Line width.";
                default = null;
              };
          };
        };
      };
      no-commit-to-branch = mkOption {
        description = "no-commit-to-branch-hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            branch =
              mkOption {
                description = "Branches to disallow commits to.";
                type = types.listOf types.str;
                default = [ "main" ];
                example = [ "main" "master" ];
              };
            pattern =
              mkOption {
                description = "RegEx patterns for branch names to disallow commits to.";
                type = types.listOf types.str;
                default = [ ];
                example = [ "ma.*" ];
              };
          };
        };
      };
      ormolu = mkOption {
        description = "ormolu hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            defaultExtensions =
              mkOption {
                type = types.listOf types.str;
                description = "Haskell language extensions to enable.";
                default = [ ];
              };
            cabalDefaultExtensions =
              mkOption {
                type = types.bool;
                description = "Use `default-extensions` from `.cabal` files.";
                default = false;
              };
          };
        };
      };
      php-cs-fixer = mkOption {
        description = "php-cs-fixer hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "PHP-CS-Fixer binary path.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.php-cs-fixer}/bin/php-cs-fixer"
                '';
              };
          };
        };
      };
      phpcbf = mkOption {
        description = "phpcbf hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "PHP_CodeSniffer binary path.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.phpcbf}/bin/phpcbf"
                '';
              };
          };
        };
      };
      phpcs = mkOption {
        description = "phpcs hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "PHP_CodeSniffer binary path.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.phpcs}/bin/phpcs"
                '';
              };
          };
        };
      };
      phpstan = mkOption {
        description = "phpstan hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "PHPStan binary path.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.phpstan}/bin/phpstan"
                '';
              };
          };
        };
      };
      # See all CLI flags for prettier [here](https://prettier.io/docs/en/cli.html).
      # See all options for prettier [here](https://prettier.io/docs/en/options.html).
      prettier = mkOption {
        description = "prettier hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                description =
                  "`prettier` binary path. E.g. if you want to use the `prettier` in `node_modules`, use `./node_modules/.bin/prettier`.";
                type = types.nullOr types.path;
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.prettier}/bin/prettier"
                '';
              };
            allow-parens =
              mkOption {
                description = "Include parentheses around a sole arrow function parameter.";
                default = "always";
                type = types.enum [ "always" "avoid" ];
              };
            bracket-same-line =
              mkOption {
                description = "Put > of opening tags on the last line instead of on a new line.";
                type = types.bool;
                default = false;
              };
            cache =
              mkOption {
                description = "Only format changed files.";
                type = types.bool;
                default = false;
              };
            cache-location =
              mkOption {
                description = "Path to the cache file location used by `--cache` flag.";
                type = types.str;
                default = "./node_modules/.cache/prettier/.prettier-cache";
              };
            cache-strategy =
              mkOption {
                description = "Strategy for the cache to use for detecting changed files.";
                type = types.nullOr (types.enum [ "metadata" "content" ]);
                default = null;
              };
            check =
              mkOption {
                description = "Output a human-friendly message and a list of unformatted files, if any.";
                type = types.bool;
                default = false;
              };
            list-different =
              mkOption {
                description = "Print the filenames of files that are different from Prettier formatting.";
                type = types.bool;
                default = true;
              };
            color =
              mkOption {
                description = "Colorize error messages.";
                type = types.bool;
                default = true;
              };
            configPath =
              mkOption {
                description = "Path to a Prettier configuration file (.prettierrc, package.json, prettier.config.js).";
                type = types.str;
                default = "";
              };
            config-precedence =
              mkOption {
                description = "Defines how config file should be evaluated in combination of CLI options.";
                type = types.enum [ "cli-override" "file-override" "prefer-file" ];
                default = "cli-override";
              };
            embedded-language-formatting =
              mkOption {
                description = "Control how Prettier formats quoted code embedded in the file.";
                type = types.enum [ "auto" "off" ];
                default = "auto";
              };
            end-of-line =
              mkOption {
                description = "Which end of line characters to apply.";
                type = types.enum [ "lf" "crlf" "cr" "auto" ];
                default = "lf";
              };
            html-whitespace-sensitivity =
              mkOption {
                description = "How to handle whitespaces in HTML.";
                type = types.enum [ "css" "strict" "ignore" ];
                default = "css";
              };
            ignore-path =
              mkOption {
                description = "Path to a file containing patterns that describe files to ignore.
                By default, prettier looks for `./.gitignore` and `./.prettierignore`.
                Multiple values are accepted.";
                type = types.listOf types.path;
                default = [ ];
              };
            ignore-unknown =
              mkOption {
                description = "Ignore unknown files.";
                type = types.bool;
                default = true;
              };
            insert-pragma =
              mkOption {
                description = "Insert @format pragma into file's first docblock comment.";
                type = types.bool;
                default = false;
              };
            jsx-single-quote =
              mkOption {
                description = "Use single quotes in JSX.";
                type = types.bool;
                default = false;
              };
            log-level =
              mkOption {
                description = "What level of logs to report.";
                type = types.enum [ "silent" "error" "warn" "log" "debug" ];
                default = "log";
                example = "debug";
              };
            no-bracket-spacing =
              mkOption {
                description = "Do not print spaces between brackets.";
                type = types.bool;
                default = false;
              };
            no-config =
              mkOption {
                description = "Do not look for a configuration file.";
                type = types.bool;
                default = false;
              };
            no-editorconfig =
              mkOption {
                description = "Don't take .editorconfig into account when parsing configuration.";
                type = types.bool;
                default = false;
              };
            no-error-on-unmatched-pattern =
              mkOption {
                description = "Prevent errors when pattern is unmatched.";
                type = types.bool;
                default = false;
              };
            no-semi =
              mkOption {
                description = "Do not print semicolons, except at the beginning of lines which may need them.";
                type = types.bool;
                default = false;
              };
            parser =
              mkOption {
                description = "Which parser to use.";
                type = types.enum [ "" "flow" "babel" "babel-flow" "babel-ts" "typescript" "acorn" "espree" "meriyah" "css" "less" "scss" "json" "json5" "json-stringify" "graphql" "markdown" "mdx" "vue" "yaml" "glimmer" "html" "angular" "lwc" ];
                default = "";
              };
            print-width =
              mkOption {
                type = types.int;
                description = "Line length that the printer will wrap on.";
                default = 80;
              };
            prose-wrap =
              mkOption {
                description = "When to or if at all hard wrap prose to print width.";
                type = types.enum [ "always" "never" "preserve" ];
                default = "preserve";
              };
            plugins =
              mkOption {
                description = "Add plugins from paths.";
                type = types.listOf types.str;
                default = [ ];
              };
            quote-props =
              mkOption {
                description = "Change when properties in objects are quoted.";
                type = types.enum [ "as-needed" "consistent" "preserve" ];
                default = "as-needed";
              };
            require-pragma =
              mkOption {
                description = "Require either '@prettier' or '@format' to be present in the file's first docblock comment.";
                type = types.bool;
                default = false;
              };
            single-attribute-per-line =
              mkOption {
                description = "Enforce single attribute per line in HTML, Vue andJSX.";
                type = types.bool;
                default = false;
              };
            single-quote =
              mkOption {
                description = "Number of spaces per indentation-level.";
                type = types.bool;
                default = false;
              };
            tab-width =
              mkOption {
                description = "Line length that the printer will wrap on.";
                type = types.int;
                default = 2;
              };
            trailing-comma =
              mkOption {
                description = "Print trailing commas wherever possible in multi-line comma-separated syntactic structures.";
                type = types.enum [ "all" "es5" "none" ];
                default = "all";
              };
            use-tabs =
              mkOption {
                type = types.bool;
                description = "Indent with tabs instead of spaces.";
                default = false;
              };
            vue-indent-script-and-style =
              mkOption {
                description = "Indent script and style tags in Vue files.";
                type = types.bool;
                default = false;
              };
            with-node-modules =
              mkOption {
                type = types.bool;
                description = "Process files inside 'node_modules' directory.";
                default = false;
              };
            write =
              mkOption {
                description = "Edit files in-place.";
                type = types.bool;
                default = true;
              };
          };
        };
      };
      psalm = mkOption {
        description = "psalm hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "Psalm binary path.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.psalm}/bin/psalm"
                '';
              };
          };
        };
      };
      pylint = mkOption {
        description = "pylint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "Pylint binary path. Should be used to specify Pylint binary from your Nix-managed Python environment.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.pylint}/bin/pylint"
                '';
              };
            reports =
              mkOption {
                type = types.bool;
                description = "Whether to display a full report.";
                default = false;
              };
            score =
              mkOption {
                type = types.bool;
                description = "Whether to activate the evaluation score.";
                default = true;
              };
          };
        };
      };
      pyright = mkOption {
        description = "pyright hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "Pyright binary path. Should be used to specify the pyright executable in an environment containing your typing stubs.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.pyright}/bin/pyright"
                '';
              };
          };
        };
      };
      pyupgrade = mkOption {
        description = "pyupgrade hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binPath =
              mkOption {
                type = types.nullOr types.str;
                description = "pyupgrade binary path. Should be used to specify the pyupgrade binary from your Nix-managed Python environment.";
                default = null;
                defaultText = lib.literalExpression ''
                  "''${tools.pyupgrade}/bin/pyupgrade"
                '';
              };
          };
        };
      };
      reuse = mkOption {
        description = "reuse hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            flags = mkOption {
              type = types.str;
              description = "Flags passed to reuse. For available options run 'reuse lint --help'";
              default = "";
              example = "--json";
            };
          };
        };
      };
      revive = mkOption {
        description = "revive hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath =
              mkOption {
                type = types.str;
                description = "Path to the configuration TOML file.";
                # an empty string translates to use default configuration of the
                # underlying revive binary
                default = "";
              };
          };
        };
      };
      ripsecrets = mkOption {
        description = "ripsecrets hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            additionalPatterns =
              mkOption {
                type = types.listOf types.str;
                description = "Additional regex patterns used to find secrets. If there is a matching group in the regex the matched group will be tested for randomness before being reported as a secret.";
                default = [ ];
              };
          };
        };
      };
      rustfmt = mkOption {
        description = ''
          Additional rustfmt settings

          Override the `rustfmt` and `cargo` packages by setting `hooks.rustfmt.packageOverrides`.

          ```
          hooks.rustfmt.packageOverrides.cargo = pkgs.cargo;
          hooks.rustfmt.packageOverrides.rustfmt = pkgs.rustfmt;
          ```
        '';
        type = types.submodule ({ config, ... }: {
          imports = [ hookModule ];
          options = {
            packageOverrides = {
              cargo = mkOption {
                type = types.package;
                description = "The cargo package to use.";
              };
              rustfmt = mkOption {
                type = types.package;
                description = "The rustfmt package to use.";
              };
            };
            settings =
              let
                nameType = types.strMatching "[][*?!0-9A-Za-z_-]+";
              in
              {
                all = mkOption {
                  type = types.bool;
                  description = "Format all packages, and also their local path-based dependencies";
                  default = true;
                };
                check = mkOption {
                  type = types.bool;
                  description = "Run rustfmt in check mode";
                  default = false;
                };
                color = mkOption {
                  type = types.enum [ "auto" "always" "never" ];
                  description = "Coloring the output";
                  default = "always";
                };
                config = mkOption {
                  type = types.attrs;
                  description = "Override configuration values";
                  default = { };
                  apply = config:
                    let
                      config' = lib.mapAttrsToList
                        (key: value: "${key}=${toString value}")
                        config;
                    in
                    if config != { }
                    then
                      (builtins.concatStringsSep "," config')
                    else
                      null;
                };
                config-path = mkOption {
                  type = types.nullOr types.str;
                  description = "Path to rustfmt.toml config file";
                  default = null;
                };
                emit = mkOption {
                  type = types.nullOr (types.enum [ "files" "stdout" ]);
                  description = "What data to emit and how";
                  default = null;
                };
                files-with-diff = mkOption {
                  type = types.bool;
                  description = "";
                  default = hooks.rustfmt.settings.message-format == "short";
                };
                manifest-path = mkOption {
                  type = types.nullOr types.str;
                  description = "Path to Cargo.toml";
                  default = settings.rust.cargoManifestPath;
                };
                message-format = mkOption {
                  type = types.nullOr (types.enum [ "human" "short" ]);
                  description = "The output format of diagnostic messages";
                  default = null;
                };
                package = mkOption {
                  type = types.listOf nameType;
                  description = "Package(s) to check";
                  default = [ ];
                };
                verbose = mkOption {
                  type = types.bool;
                  description = "Use verbose output";
                  default = false;
                };
              };
          };
          config.extraPackages = [
            config.packageOverrides.cargo
            config.packageOverrides.rustfmt
          ];
        });
      };
      shfmt = mkOption {
        description = "shfmt hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            simplify = mkOption {
              type = types.bool;
              description = "Simplify the code.";
              default = true;
            };
          };
        };
      };
      statix = mkOption {
        description = "statix hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            config =
              mkOption {
                type = types.nullOr types.str;
                description = "Path to statix.toml or its parent directory.";
                default = null;
              };

            format =
              mkOption {
                type = types.enum [ "stderr" "errfmt" "json" ];
                description = "Error Output format.";
                default = "errfmt";
              };

            ignore =
              mkOption {
                type = types.listOf types.str;
                description = "Globs of file patterns to skip.";
                default = [ ];
                example = [ "flake.nix" "_*" ];
              };

            unrestricted =
              mkOption {
                type = types.bool;
                description = "Don't respect .gitignore files.";
                default = false;
                example = true;
              };
          };
        };
      };
      sort-file-contents = mkOption {
        description = "sort-file-contents-hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            ignore-case =
              mkOption {
                type = types.bool;
                description = "Fold lower case to upper case characters.";
                default = false;
              };
            unique =
              mkOption {
                type = types.bool;
                description = "Ensure each line is unique.";
                default = false;
              };
          };
        };
      };
      treefmt = mkOption {
        description = ''
          Treefmt hook.

          Include any additional formatters configured by treefmt as `hooks.treefmt.settings.formatters`.

          ```
          hooks.treefmt.settings.formatters = [
            pkgs.nixpkgs-fmt
            pkgs.black
          ];
          ```

          Override `treefmt` itself by setting `hooks.treefmt.packageOverrides.treefmt`.

          ```
          hooks.treefmt.packageOverrides.treefmt = pkgs.treefmt;
          ```
        '';
        type = types.submodule
          ({ config, ... }:
            {
              imports = [ hookModule ];
              options.packageOverrides = {
                treefmt = mkOption {
                  type = types.package;
                  description = "The treefmt package to use";
                };
              };
              options.settings = {
                formatters = mkOption {
                  type = types.listOf types.package;
                  description = "The formatter packages configured by treefmt";
                  default = [ ];
                };
              };

              config.extraPackages = config.settings.formatters;
            });
      };
      typos = mkOption {
        description = "typos hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            binary =
              mkOption {
                type = types.bool;
                description = "Whether to search binary files.";
                default = false;
              };
            color =
              mkOption {
                type = types.enum [ "auto" "always" "never" ];
                description = "When to use generate output.";
                default = "auto";
              };
            configuration =
              mkOption {
                type = types.str;
                description = "Multiline-string configuration passed as config file. If set, config set in `typos.settings.configPath` gets ignored.";
                default = "";
                example = ''
                  [files]
                  ignore-dot = true

                  [default]
                  binary = false

                  [type.py]
                  extend-glob = []
                '';
              };

            configPath =
              mkOption {
                type = types.str;
                description = "Path to a custom config file.";
                default = "";
                example = ".typos.toml";
              };

            diff =
              mkOption {
                type = types.bool;
                description = "Print a diff of what would change.";
                default = false;
              };

            exclude =
              mkOption {
                type = types.str;
                description = "Ignore files and directories matching the glob.";
                default = "";
                example = "*.nix";
              };

            format =
              mkOption {
                type = types.enum [ "silent" "brief" "long" "json" ];
                description = "Output format to use.";
                default = "long";
              };

            hidden =
              mkOption {
                type = types.bool;
                description = "Search hidden files and directories.";
                default = false;
              };

            ignored-words =
              mkOption {
                type = types.listOf types.str;
                description = "Spellings and words to ignore.";
                default = [ ];
                example = [
                  "MQTT"
                  "mosquitto"
                ];
              };

            locale =
              mkOption {
                type = types.enum [ "en" "en-us" "en-gb" "en-ca" "en-au" ];
                description = "Which language to use for spell checking.";
                default = "en";
              };

            no-check-filenames =
              mkOption {
                type = types.bool;
                description = "Skip verifying spelling in file names.";
                default = false;
              };

            no-check-files =
              mkOption {
                type = types.bool;
                description = "Skip verifying spelling in files.";
                default = false;
              };

            no-unicode =
              mkOption {
                type = types.bool;
                description = "Only allow ASCII characters in identifiers.";
                default = false;
              };

            quiet =
              mkOption {
                type = types.bool;
                description = "Less output per occurrence.";
                default = false;
              };

            verbose =
              mkOption {
                type = types.bool;
                description = "More output per occurrence.";
                default = false;
              };

            write =
              mkOption {
                type = types.bool;
                description = "Fix spelling in files by writing them. Cannot be used with `typos.settings.diff`.";
                default = false;
              };
          };
        };
      };
      vale = mkOption {
        description = "vale hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configuration =
              mkOption {
                type = types.str;
                description = "Multiline-string configuration passed as config file.";
                default = "";
                example = ''
                  MinAlertLevel = suggestion
                  [*]
                  BasedOnStyles = Vale
                '';
              };
            configPath =
              mkOption {
                type = types.str;
                description = "Path to the config file.";
                default = "";
              };
            flags =
              mkOption {
                type = types.str;
                description = "Flags passed to vale.";
                default = "";
              };
          };
        };
      };
      yamlfmt = mkOption {
        description = "yamlfmt hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            configPath =
              mkOption {
                type = types.str;
                description = "Path to a custom configuration file.";
                # An empty string translates to yamlfmt looking for a configuration file in the
                # following locations (by order of preference):
                # a file named .yamlfmt, yamlfmt.yml, yamlfmt.yaml, .yamlfmt.yaml or .yamlfmt.yml in the current working directory
                # See details [here](https://github.com/google/yamlfmt/blob/main/docs/config-file.md#config-file-discovery)
                default = "";
                example = ".yamlfmt";
              };
          };
        };
      };
      yamllint = mkOption {
        description = "yamllint hook";
        type = types.submodule {
          imports = [ hookModule ];
          options.settings = {
            # `list-files` is not useful for a pre-commit hook as it always exits with exit code 0
            # `no-warnings` is not useful for a pre-commit hook as it exits with exit code 2 and the hook
            # therefore fails when warnings level problems are detected but there is no output
            configuration = mkOption {
              type = types.str;
              description = "Multiline-string configuration passed as config file. If set, configuration file set in `yamllint.settings.configPath` gets ignored.";
              default = "";
              example = ''
                ---

                extends: relaxed

                rules:
                  indentation: enable
              '';
            };
            configData = mkOption {
              type = types.str;
              description = "Serialized YAML object describing the configuration.";
              default = "";
              example = "{extends: relaxed, rules: {line-length: {max: 120}}}";
            };
            configPath = mkOption {
              type = types.str;
              description = "Path to a custom configuration file.";
              # An empty string translates to yamllint looking for a configuration file in the
              # following locations (by order of preference):
              # a file named .yamllint, .yamllint.yaml or .yamllint.yml in the current working directory
              # a filename referenced by $YAMLLINT_CONFIG_FILE, if set
              # a file named $XDG_CONFIG_HOME/yamllint/config or ~/.config/yamllint/config, if present
              default = "";
            };
            format = mkOption {
              type = types.enum [ "parsable" "standard" "colored" "github" "auto" ];
              description = "Format for parsing output.";
              default = "auto";
            };
            preset = mkOption {
              type = types.enum [ "default" "relaxed" ];
              description = "The configuration preset to use.";
              default = "default";
            };
            strict = mkOption {
              type = types.bool;
              description = "Return non-zero exit code on warnings as well as errors.";
              default = true;
            };
          };
        };
      };
    };

  config.warnings =
    lib.optional cfg.hooks.rome.enable ''
      The hook `hooks.rome` has been renamed to `hooks.biome`.
    ''
    ++ lib.optional cfg.hooks.nixfmt.enable ''
      The hook `hooks.nixfmt` has been renamed to `hooks.nixfmt-classic`.

      The new RFC 166-style nixfmt is available as `hooks.nixfmt-rfc-style`.
    '';

  # PLEASE keep this sorted alphabetically.
  config.hooks = mapAttrs (_: mapAttrs (_: mkDefault))
    rec {
      actionlint =
        {
          name = "actionlint";
          description = "Static checker for GitHub Actions workflow files";
          files = "^.github/workflows/";
          types = [ "yaml" ];
          package = tools.actionlint;
          entry = "${hooks.actionlint.package}/bin/actionlint";
        };
      alejandra =
        {
          name = "alejandra";
          description = "The Uncompromising Nix Code Formatter";
          package = tools.alejandra;
          entry =
            let
              cmdArgs =
                mkCmdArgs (with hooks.alejandra.settings; [
                  [ check "--check" ]
                  [ (exclude != [ ]) "--exclude ${lib.strings.concatStringsSep " --exclude " (map lib.escapeShellArg (lib.unique exclude))}" ]
                  [ (verbosity == "quiet") "-q" ]
                  [ (verbosity == "silent") "-qq" ]
                  [ (threads != null) "--threads ${toString threads}" ]
                ]);
            in
            "${hooks.alejandra.package}/bin/alejandra ${cmdArgs}";
          files = "\\.nix$";
        };
      annex =
        {
          name = "annex";
          description = "Runs the git-annex hook for large file support";
          package = tools.git-annex;
          entry = "${hooks.annex.package}/bin/git-annex pre-commit";
        };
      ansible-lint =
        {
          name = "ansible-lint";
          description = "Ansible linter";
          package = tools.ansible-lint;
          entry =
            let
              cmdArgs =
                mkCmdArgs [
                  [ (hooks.ansible-lint.settings.configPath != "") "-c ${hooks.ansible-lint.settings.configPath}" ]
                ];
            in
            "${hooks.ansible-lint.package}/bin/ansible-lint ${cmdArgs}";
          files = if hooks.ansible-lint.settings.subdir != "" then "${hooks.ansible-lint.settings.subdir}/" else "";
        };
      autoflake =
        {
          name = "autoflake";
          description = "Remove unused imports and variables from Python code";

          package = tools.autoflake;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.autoflake "/bin/autoflake";
            in
            "${binPath} ${hooks.autoflake.settings.flags}";
          types = [ "python" ];
        };
      biome =
        {
          name = "biome";
          description = "A toolchain for web projects, aimed to provide functionalities to maintain them";
          types_or = [ "javascript" "jsx" "ts" "tsx" "json" ];

          package = tools.biome;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.biome "/bin/biome";
              cmdArgs =
                mkCmdArgs [
                  [ (hooks.biome.settings.write) "--apply" ]
                  [ (hooks.biome.settings.configPath != "") "--config-path ${hooks.biome.settings.configPath}" ]
                ];
            in
            "${binPath} check ${cmdArgs}";
        };
      bats =
        {
          name = "bats";
          description = "Run bash unit tests";
          types = [ "shell" ];
          types_or = [ "bats" "bash" ];
          package = tools.bats;
          entry = "${hooks.bats.package}/bin/bats -p";
        };
      beautysh =
        {
          name = "beautysh";
          description = "Format shell files";
          types = [ "shell" ];
          package = tools.beautysh;
          entry = "${hooks.beautysh.package}/bin/beautysh";
        };
      black =
        {
          name = "black";
          description = "The uncompromising Python code formatter";
          package = tools.black;
          entry = "${hooks.black.package}/bin/black ${hooks.black.settings.flags}";
          types = [ "file" "python" ];
        };
      cabal-fmt =
        {
          name = "cabal-fmt";
          description = "Format Cabal files";
          package = tools.cabal-fmt;
          entry = "${hooks.cabal-fmt.package}/bin/cabal-fmt --inplace";
          files = "\\.cabal$";
        };
      cabal-gild =
        {
          name = "cabal-gild";
          description = "Format Cabal files";
          package = tools.cabal-gild;
          entry =
            let
              script = pkgs.writeShellScript "precommit-cabal-gild" ''
                for file in "$@"; do
                    ${hooks.cabal-gild.package}/bin/cabal-gild --io="$file"
                done
              '';
            in
            builtins.toString script;
          files = "\\.cabal$";
        };
      cabal2nix =
        {
          name = "cabal2nix";
          description = "Run `cabal2nix` on all `*.cabal` files to generate corresponding `default.nix` files";
          package = tools.cabal2nix-dir;
          entry = "${hooks.cabal2nix.package}/bin/cabal2nix-dir";
          files = "\\.cabal$";
        };
      cargo-check =
        {
          name = "cargo-check";
          description = "Check the cargo package for errors";
          package = tools.cargo;
          entry = "${hooks.cargo-check.package}/bin/cargo check ${cargoManifestPathArg}";
          files = "\\.rs$";
          pass_filenames = false;
        };
      checkmake = {
        name = "checkmake";
        description = "Experimental linter/analyzer for Makefiles";
        types = [ "makefile" ];
        package = tools.checkmake;
        entry =
          ## NOTE: `checkmake` 0.2.2 landed in nixpkgs on 12 April 2023. Once
          ## this gets into a NixOS release, the following code will be useless.
          lib.throwIf
            (hooks.checkmake.package == null)
            "The version of nixpkgs used by git-hooks.nix must have `checkmake` in version at least 0.2.2 for it to work on non-Linux systems."
            "${hooks.checkmake.package}/bin/checkmake";
      };
      check-added-large-files =
        {
          name = "check-added-large-files";
          description = "Prevent very large files to be committed (e.g. binaries).";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-added-large-files.package}/bin/check-added-large-files";
          stages = [ "commit" "push" "manual" ];
        };
      check-builtin-literals =
        {
          name = "check-builtin-literals";
          description = "Require literal syntax when initializing empty or zero builtin types in Python.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-builtin-literals.package}/bin/check-builtin-literals";
          types = [ "python" ];
        };
      check-case-conflicts =
        {
          name = "check-case-conflicts";
          description = "Check for files that would conflict in case-insensitive filesystems.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-case-conflicts.package}/bin/check-case-conflict";
          types = [ "file" ];
        };
      check-docstring-first =
        {
          name = "check-docstring-above";
          description = "Check that all docstrings appear above the code.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-docstring-first.package}/bin/check-docstring-first";
          types = [ "python" ];
        };
      check-executables-have-shebangs =
        {
          name = "check-executables-have-shebangs";
          description = "Ensure that all non-binary executables have shebangs.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-executables-have-shebangs.package}/bin/check-executables-have-shebangs";
          types = [ "text" "executable" ];
          stages = [ "commit" "push" "manual" ];
        };
      check-json =
        {
          name = "check-json";
          description = "Check syntax of JSON files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-json.package}/bin/check-json";
          types = [ "json" ];
        };
      check-merge-conflicts =
        {
          name = "check-merge-conflicts";
          description = "Check for files that contain merge conflict strings.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-merge-conflicts.package}/bin/check-merge-conflict";
          types = [ "text" ];
        };
      check-python =
        {
          name = "check-python";
          description = "Check syntax of Python file by parsing Python abstract syntax tree.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-python.package}/bin/check-ast";
          types = [ "python" ];
        };
      check-shebang-scripts-are-executable =
        {
          name = "check-shebang-scripts-are-executable";
          description = "Ensure that all (non-binary) files with a shebang are executable.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-shebang-scripts-are-executable.package}/bin/check-shebang-scripts-are-executable";
          types = [ "text" ];
          stages = [ "commit" "push" "manual" ];
        };
      check-symlinks =
        {
          name = "check-symlinks";
          description = "Find broken symlinks.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-symlinks.package}/bin/check-symlinks";
          types = [ "symlink" ];
        };
      check-toml =
        {
          name = "check-toml";
          description = "Check syntax of TOML files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-toml.package}/bin/check-toml";
          types = [ "toml" ];
        };
      check-vcs-permalinks =
        {
          name = "check-vcs-permalinks";
          description = "Ensure that links to VCS websites are permalinks.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-vcs-permalinks.package}/bin/check-vcs-permalinks";
          types = [ "text" ];
        };
      check-xml =
        {
          name = "check-xml";
          description = "Check syntax of TOML files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-xml.package}/bin/check-xml";
          types = [ "xml" ];
        };
      check-yaml =
        {
          name = "check-yaml";
          description = "Check syntax of YAML files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.check-yaml.package}/bin/check-yaml --multi";
          types = [ "yaml" ];
        };
      chktex =
        {
          name = "chktex";
          description = "LaTeX semantic checker";
          types = [ "file" "tex" ];
          package = texliveCombine;
          entry = "${hooks.chktex.package}/bin/chktex";
        };
      clang-format =
        {
          name = "clang-format";
          description = "Format your code using `clang-format`.";
          package = tools.clang-tools;
          entry = "${hooks.clang-format.package}/bin/clang-format -style=file -i";
          # Source:
          # https://github.com/pre-commit/mirrors-clang-format/blob/46516e8f532c8f2d55e801c34a740ebb8036365c/.pre-commit-hooks.yaml
          types_or = [
            "c"
            "c++"
            "c#"
            "cuda"
            "java"
            "javascript"
            "json"
            "objective-c"
            "proto"
          ];
        };
      clang-tidy = {
        name = "clang-tidy";
        description = "Static analyzer for C++ code.";
        package = tools.clang-tools;
        entry = "${hooks.clang-tidy.package}/bin/clang-tidy --fix";
        types_or = [ "c" "c++" "c#" "objective-c" ];
      };
      clippy =
        let
          inherit (hooks.clippy) packageOverrides;
          wrapper = pkgs.symlinkJoin {
            name = "clippy-wrapped";
            paths = [ packageOverrides.clippy ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-clippy \
                --prefix PATH : ${lib.makeBinPath [ packageOverrides.cargo ]}
            '';
          };
        in
        {
          name = "clippy";
          description = "Lint Rust code.";
          package = wrapper;
          packageOverrides = { cargo = tools.cargo; clippy = tools.clippy; };
          entry = "${hooks.clippy.package}/bin/cargo-clippy clippy ${cargoManifestPathArg} ${lib.optionalString hooks.clippy.settings.offline "--offline"} ${lib.optionalString hooks.clippy.settings.allFeatures "--all-features"} ${hooks.clippy.settings.extraArgs} -- ${lib.optionalString hooks.clippy.settings.denyWarnings "-D warnings"}";
          files = "\\.rs$";
          pass_filenames = false;
        };
      cljfmt =
        {
          name = "cljfmt";
          description = "A tool for formatting Clojure code.";
          package = tools.cljfmt;
          entry = "${hooks.cljfmt.package}/bin/cljfmt fix";
          types_or = [ "clojure" "clojurescript" "edn" ];
        };
      cmake-format =
        {
          name = "cmake-format";
          description = "A tool for formatting CMake-files.";
          package = tools.cmake-format;
          entry =
            let
              maybeConfigPath =
                if hooks.cmake-format.settings.configPath == ""
                # Searches automatically for the config path.
                then ""
                else "-C ${hooks.cmake-format.settings.configPath}";
            in
            "${hooks.cmake-format.package}/bin/cmake-format --check ${maybeConfigPath}";
          files = "\\.cmake$|CMakeLists.txt";
        };
      commitizen =
        {
          name = "commitizen check";
          description = ''
            Check whether the current commit message follows committing rules.
          '';
          package = tools.commitizen;
          entry = "${hooks.commitizen.package}/bin/cz check --allow-abort --commit-msg-file";
          stages = [ "commit-msg" ];
        };
      conform = {
        name = "conform enforce";
        description = "Policy enforcement for commits.";
        package = tools.conform;
        entry = "${hooks.conform.package}/bin/conform enforce --commit-msg-file";
        stages = [ "commit-msg" ];
      };
      convco = {
        name = "convco";
        package = tools.convco;
        entry =
          let
            convco = hooks.convco.package;
            script = pkgs.writeShellScript "precommit-convco" ''
              cat $1 | ${convco}/bin/convco check --from-stdin
            '';
            # need version >= 0.4.0 for the --from-stdin flag
            toolVersionCheck = lib.versionAtLeast convco.version "0.4.0";
          in
          lib.throwIf (convco == null || !toolVersionCheck) "The version of Nixpkgs used by git-hooks.nix does not have the `convco` package (>=0.4.0). Please use a more recent version of Nixpkgs."
            builtins.toString
            script;
        stages = [ "commit-msg" ];
      };
      credo = {
        name = "credo";
        description = "Runs a static code analysis using Credo";
        package = tools.elixir;
        entry =
          let strict = if hooks.credo.settings.strict then "--strict" else "";
          in "${hooks.credo.package}/bin/mix credo ${strict}";
        files = "\\.exs?$";
      };
      crystal = {
        name = "crystal";
        description = "A tool that automatically formats Crystal source code";
        package = tools.crystal;
        entry = "${hooks.crystal.package}/bin/crystal tool format";
        files = "\\.cr$";
      };
      cspell =
        {
          name = "cspell";
          description = "A Spell Checker for Code";
          package = tools.cspell;
          entry = "${hooks.cspell.package}/bin/cspell";
        };
      deadnix =
        {
          name = "deadnix";
          description = "Scan Nix files for dead code (unused variable bindings).";
          package = tools.deadnix;
          entry =
            let
              cmdArgs =
                mkCmdArgs (with hooks.deadnix.settings; [
                  [ noLambdaArg "--no-lambda-arg" ]
                  [ noLambdaPatternNames "--no-lambda-pattern-names" ]
                  [ noUnderscore "--no-underscore" ]
                  [ quiet "--quiet" ]
                  [ hidden "--hidden" ]
                  [ edit "--edit" ]
                  [ (exclude != [ ]) "--exclude ${lib.escapeShellArgs exclude}" ]
                ]);
            in
            "${hooks.deadnix.package}/bin/deadnix ${cmdArgs} --fail";
          files = "\\.nix$";
        };
      denofmt =
        {
          name = "denofmt";
          description = "Auto-format JavaScript, TypeScript, Markdown, and JSON files.";
          types_or = [ "javascript" "jsx" "ts" "tsx" "markdown" "json" ];
          package = tools.deno;
          entry =
            let
              cmdArgs =
                mkCmdArgs [
                  [ (!hooks.denofmt.settings.write) "--check" ]
                  [ (hooks.denofmt.settings.configPath != "") "-c ${hooks.denofmt.settings.configPath}" ]
                ];
            in
            "${hooks.denofmt.package}/bin/deno fmt ${cmdArgs}";
        };
      denolint =
        {
          name = "denolint";
          description = "Lint JavaScript/TypeScript source code.";
          types_or = [ "javascript" "jsx" "ts" "tsx" ];
          package = tools.deno;
          entry =
            let
              cmdArgs =
                mkCmdArgs [
                  [ (hooks.denolint.settings.format == "compact") "--compact" ]
                  [ (hooks.denolint.settings.format == "json") "--json" ]
                  [ (hooks.denolint.settings.configPath != "") "-c ${hooks.denolint.settings.configPath}" ]
                ];
            in
            "${hooks.denolint.package}/bin/deno lint ${cmdArgs}";
        };
      detect-aws-credentials =
        {
          name = "detect-aws-credentials";
          description = "Detect AWS credentials from the AWS cli credentials file.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.detect-aws-credentials.package}/bin/detect-aws-credentials --allow-missing-credentials";
          types = [ "text" ];
        };
      detect-private-keys =
        {
          name = "detect-private-keys";
          description = "Detect the presence of private keys.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.detect-private-keys.package}/bin/detect-private-key";
          types = [ "text" ];
        };
      dhall-format = {
        name = "dhall-format";
        description = "Dhall code formatter.";
        package = tools.dhall;
        entry = "${hooks.dhall-format.package}/bin/dhall format";
        files = "\\.dhall$";
      };
      dialyzer = {
        name = "dialyzer";
        description = "Runs a static code analysis using Dialyzer";
        package = tools.elixir;
        entry = "${hooks.dialyzer.package}/bin/mix dialyzer";
        files = "\\.exs?$";
      };
      dune-fmt = {
        name = "dune-fmt";
        description = "Runs Dune's formatters on the code tree.";
        package = tools.dune-fmt;
        entry =
          let
            auto-promote = if hooks.dune-fmt.settings.auto-promote then "--auto-promote" else "";
            run-dune-fmt = pkgs.writeShellApplication {
              name = "run-dune-fmt";
              runtimeInputs = hooks.dune-fmt.settings.extraRuntimeInputs;
              text = "${hooks.dune-fmt.package}/bin/dune-fmt ${auto-promote}";
            };
          in
          "${run-dune-fmt}/bin/run-dune-fmt";
        pass_filenames = false;
      };
      dune-opam-sync = {
        name = "dune/opam sync";
        description = "Check that Dune-generated OPAM files are in sync.";
        package = tools.dune-build-opam-files;
        entry = "${hooks.dune-opam-sync.package}/bin/dune-build-opam-files";
        files = "(\\.opam$)|(\\.opam.template$)|((^|/)dune-project$)";
        ## We don't pass filenames because they can only be misleading. Indeed,
        ## we need to re-run `dune build` for every `*.opam` file, but also when
        ## the `dune-project` file has changed.
        pass_filenames = false;
      };
      eclint =
        {
          name = "eclint";
          description = "EditorConfig linter written in Go.";
          types = [ "file" ];
          package = tools.eclint;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.eclint.settings; [
                    [ fix "-fix" ]
                    [ summary "-summary" ]
                    [ (color != "auto") "-color ${color}" ]
                    [ (exclude != [ ]) "-exclude ${lib.escapeShellArgs exclude}" ]
                    [ (verbosity != 0) "-verbosity ${toString verbosity}" ]
                  ]);
            in
            "${hooks.eclint.package}/bin/eclint ${cmdArgs}";
        };
      editorconfig-checker =
        {
          name = "editorconfig-checker";
          description = "Verify that the files are in harmony with the `.editorconfig`.";
          package = tools.editorconfig-checker;
          entry = "${hooks.editorconfig-checker.package}/bin/editorconfig-checker";
          types = [ "file" ];
        };
      end-of-file-fixer =
        {
          name = "end-of-file-fixer";
          description = "Ensures that a file is either empty, or ends with a single newline.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.end-of-file-fixer.package}/bin/end-of-file-fixer";
          types = [ "text" ];
        };
      elm-format =
        {
          name = "elm-format";
          description = "Format Elm files.";
          package = tools.elm-format;
          entry = "${hooks.elm-format.package}/bin/elm-format --yes --elm-version=0.19";
          files = "\\.elm$";
        };
      elm-review =
        {
          name = "elm-review";
          description = "Analyzes Elm projects, to help find mistakes before your users find them.";
          package = tools.elm-review;
          entry = "${hooks.elm-review.package}/bin/elm-review";
          files = "\\.elm$";
          pass_filenames = false;
        };
      elm-test =
        {
          name = "elm-test";
          description = "Run unit tests and fuzz tests for Elm code.";
          package = tools.elm-test;
          entry = "${hooks.elm-test.package}/bin/elm-test";
          files = "\\.elm$";
          pass_filenames = false;
        };
      eslint =
        {
          name = "eslint";
          description = "Find and fix problems in your JavaScript code.";

          package = tools.eslint;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.eslint "/bin/eslint";
            in
            "${binPath} --fix";
          files = "${hooks.eslint.settings.extensions}";
        };
      fix-byte-order-marker =
        {
          name = "fix-byte-order-marker";
          description = "Remove UTF-8 byte order marker.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.fix-byte-order-marker.package}/bin/fix-byte-order-marker";
          types = [ "text" ];
        };
      fix-encoding-pragma =
        {
          name = "fix-encoding-pragma";
          description = "Adds \# -*- coding: utf-8 -*- to the top of Python files.'";
          package = tools.pre-commit-hooks;
          entry = "${hooks.fix-encoding-pragma.package}/bin/fix-encoding-pragma";
          types = [ "python" ];
        };
      flake8 =
        let
          extendIgnoreStr =
            if lib.lists.length hooks.flake8.settings.extendIgnore > 0
            then "--extend-ignore " + builtins.concatStringsSep "," hooks.flake8.settings.extendIgnore
            else "";
        in
        {
          name = "flake8";
          description = "Check the style and quality of Python files.";

          package = tools.flake8;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.flake8 "/bin/flake8";
            in
            "${binPath} --format ${hooks.flake8.settings.format} ${extendIgnoreStr}";
          types = [ "python" ];
        };
      flake-checker = {
        name = "flake-checker";
        description = "Run health checks on your flake-powered Nix projects.";
        package = tools.flake-checker;
        entry = "${hooks.flake-checker.package}/bin/flake-checker -f";
        files = "(^flake\\.nix$|^flake\\.lock$)";
        pass_filenames = false;
      };
      flynt =
        {
          name = "flynt";
          description = "CLI tool to convert a python project's %-formatted strings to f-strings.";
          package = tools.flynt;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.flynt "/bin/flynt";
              cmdArgs =
                mkCmdArgs (with hooks.flynt.settings; [
                  [ aggressive "--aggressive" ]
                  [ dry-run "--dry-run" ]
                  [ (exclude != [ ]) "--exclude ${lib.escapeShellArgs exclude}" ]
                  [ fail-on-change "--fail-on-change" ]
                  [ (line-length != null) "--line-length ${toString line-length}" ]
                  [ no-multiline "--no-multiline" ]
                  [ quiet "--quiet" ]
                  [ string "--string" ]
                  [ transform-concats "--transform-concats" ]
                  [ verbose "--verbose" ]
                ]);
            in
            "${binPath} ${cmdArgs}";
          types = [ "python" ];
        };
      forbid-new-submodules =
        {
          name = "forbid-new-submodules";
          description = "Prevent addition of new Git submodules.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.forbid-new-submodules.package}/bin/forbid-new-submodules";
          types = [ "directory" ];
        };
      fourmolu =
        {
          name = "fourmolu";
          description = "Haskell code prettifier.";
          package = tools.fourmolu;
          entry =
            "${hooks.fourmolu.package}/bin/fourmolu --mode inplace ${
lib.escapeShellArgs (lib.concatMap (ext: [ "--ghc-opt" "-X${ext}" ]) hooks.ormolu.settings.defaultExtensions)
}";
          files = "\\.l?hs(-boot)?$";
        };
      fprettify = {
        name = "fprettify";
        description = "Auto-formatter for modern Fortran code.";
        types = [ "fortran " ];
        package = tools.fprettify;
        entry = "${hooks.fprettify.package}/bin/fprettify";
      };
      gofmt =
        {
          name = "gofmt";
          description = "A tool that automatically formats Go source code";
          package = tools.go;
          entry =
            let
              script = pkgs.writeShellScript "precommit-gofmt" ''
                set -e
                failed=false
                for file in "$@"; do
                    # redirect stderr so that violations and summaries are properly interleaved.
                    if ! ${hooks.gofmt.package}/bin/gofmt -l -w "$file" 2>&1
                    then
                        failed=true
                    fi
                done
                if [[ $failed == "true" ]]; then
                    exit 1
                fi
              '';
            in
            builtins.toString script;
          files = "\\.go$";
        };
      golangci-lint = {
        name = "golangci-lint";
        description = "Fast linters runner for Go.";
        package = tools.golangci-lint;
        entry =
          let
            script = pkgs.writeShellScript "precommit-golangci-lint" ''
              set -e
              for dir in $(echo "$@" | xargs -n1 dirname | sort -u); do
                ${hooks.golangci-lint.package}/bin/golangci-lint run ./"$dir"
              done
            '';
          in
          builtins.toString script;
        files = "\\.go$";
        # to avoid multiple invocations of the same directory input, provide
        # all file names in a single run.
        require_serial = true;
      };
      gotest = {
        name = "gotest";
        description = "Run go tests";
        package = tools.go;
        entry =
          let
            script = pkgs.writeShellScript "precommit-gotest" ''
              set -e
              # find all directories that contain tests
              dirs=()
              for file in "$@"; do
                # either the file is a test
                if [[ "$file" = *_test.go ]]; then
                  dirs+=("$(dirname "$file")")
                  continue
                fi

                # or the file has an associated test
                filename="''${file%.go}"
                test_file="''${filename}_test.go"
                if [[ -f "$test_file"  ]]; then
                  dirs+=("$(dirname "$test_file")")
                  continue
                fi
              done

              # ensure we are not duplicating dir entries
              IFS=$'\n' sorted_dirs=($(sort -u <<<"''${dirs[*]}")); unset IFS

              # test each directory one by one
              for dir in "''${sorted_dirs[@]}"; do
                  ${hooks.gotest.package}/bin/go test "./$dir"
              done
            '';
          in
          builtins.toString script;
        files = "\\.go$";
        # to avoid multiple invocations of the same directory input, provide
        # all file names in a single run.
        require_serial = true;
      };
      govet =
        {
          name = "govet";
          description = "Checks correctness of Go programs.";
          package = tools.go;
          entry =
            let
              # go vet requires package (directory) names as inputs.
              script = pkgs.writeShellScript "precommit-govet" ''
                set -e
                for dir in $(echo "$@" | xargs -n1 dirname | sort -u); do
                  ${hooks.govet.package}/bin/go vet ./"$dir"
                done
              '';
            in
            builtins.toString script;
          # to avoid multiple invocations of the same directory input, provide
          # all file names in a single run.
          require_serial = true;
          files = "\\.go$";
        };
      gptcommit = {
        name = "gptcommit";
        description = "Generate a commit message using GPT3.";
        package = tools.gptcommit;
        entry =
          let
            script = pkgs.writeShellScript "precommit-gptcomit" ''
              ${hooks.gptcommit.package}/bin/gptcommit prepare-commit-msg --commit-source \
                "$PRE_COMMIT_COMMIT_MSG_SOURCE" --commit-msg-file "$1"
            '';
          in
          lib.throwIf (hooks.gptcommit.package == null) "The version of Nixpkgs used by git-hooks.nix does not have the `gptcommit` package. Please use a more recent version of Nixpkgs."
            toString
            script;
        stages = [ "prepare-commit-msg" ];
      };
      hadolint =
        {
          name = "hadolint";
          description = "Dockerfile linter, validate inline bash.";
          package = tools.hadolint;
          entry = "${hooks.hadolint.package}/bin/hadolint";
          files = "Dockerfile$";
        };
      headache =
        {
          name = "headache";
          description = "Lightweight tool for managing headers in source code files.";
          ## NOTE: Supported `files` are taken from
          ## https://github.com/Frama-C/headache/blob/master/config_builtin.txt
          files = "(\\.ml[ily]?$)|(\\.fmli?$)|(\\.[chy]$)|(\\.tex$)|(Makefile)|(README)|(LICENSE)";
          package = tools.headache;
          entry =
            ## NOTE: `headache` made into in nixpkgs on 12 April 2023. At the
            ## next NixOS release, the following code will become irrelevant.
            lib.throwIf
              (hooks.headache.package == null)
              "The version of nixpkgs used by git-hooks.nix does not have `ocamlPackages.headache`. Please use a more recent version of nixpkgs."
              "${hooks.headache.package}/bin/headache -h ${hooks.headache.settings.header-file}";
        };
      hindent =
        {
          name = "hindent";
          description = "Haskell code prettifier.";
          package = tools.hindent;
          entry = "${hooks.hindent.package}/bin/hindent";
          files = "\\.l?hs(-boot)?$";
        };
      hlint =
        {
          name = "hlint";
          description = "HLint gives suggestions on how to improve your source code.";
          package = tools.hlint;
          entry = "${hooks.hlint.package}/bin/hlint${if hooks.hlint.settings.hintFile == null then "" else " --hint=${hooks.hlint.settings.hintFile}"}";
          files = "\\.l?hs(-boot)?$";
        };
      hpack =
        {
          name = "hpack";
          description = "`hpack` converts package definitions in the hpack format (`package.yaml`) to Cabal files.";
          package = tools.hpack-dir;
          entry = "${hooks.hpack.package}/bin/hpack-dir --${if hooks.hpack.settings.silent then "silent" else "verbose"}";
          files = "(\\.l?hs(-boot)?$)|(\\.cabal$)|((^|/)package\\.yaml$)";
          # We don't pass filenames because they can only be misleading.
          # Indeed, we need to rerun `hpack` in every directory:
          # 1. In which there is a *.cabal file, or
          # 2. Below which there are haskell files, or
          # 3. In which there is a package.yaml that references haskell files
          #    that have been changed at arbitrary locations specified in that
          #    file.
          # In other words: We have no choice but to always run `hpack` on every `package.yaml` directory.
          pass_filenames = false;
        };
      html-tidy =
        {
          name = "html-tidy";
          description = "HTML linter.";
          package = tools.html-tidy;
          entry = "${hooks.html-tidy.package}/bin/tidy -quiet -errors";
          files = "\\.html$";
        };
      hunspell =
        {
          name = "hunspell";
          description = "Spell checker and morphological analyzer.";
          package = tools.hunspell;
          entry = "${hooks.hunspell.package}/bin/hunspell -l";
          files = "\\.((txt)|(html)|(xml)|(md)|(rst)|(tex)|(odf)|\\d)$";
        };
      isort =
        {
          name = "isort";
          description = "A Python utility / library to sort imports.";
          types = [ "file" "python" ];
          package = tools.isort;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.isort.settings; [
                    [ (profile != "") " --profile ${profile}" ]
                  ]);
            in
            "${hooks.isort.package}/bin/isort${cmdArgs} ${hooks.isort.settings.flags}";
        };
      juliaformatter =
        {
          description = "Run JuliaFormatter.jl against Julia source files";
          files = "\\.jl$";
          package = tools.julia-bin;
          entry = ''
            ${hooks.juliaformatter.package}/bin/julia -e '
            using Pkg
            Pkg.activate(".")
            using JuliaFormatter
            format(ARGS)
            out = Cmd(`git diff --name-only`) |> read |> String
            if out == ""
                exit(0)
            else
                @error "Some files have been formatted !!!"
                write(stdout, out)
                exit(1)
            end'
          '';
        };
      latexindent =
        {
          name = "latexindent";
          description = "Perl script to add indentation to LaTeX files.";
          types = [ "file" "tex" ];
          package = texliveCombine;
          entry = "${hooks.latexindent.package}/bin/latexindent ${hooks.latexindent.settings.flags}";
        };
      lacheck =
        let
          script = pkgs.writeShellScript "precommit-mdsh" ''
            for file in $(echo "$@"); do
                "${hooks.lacheck.package}/bin/lacheck" "$file"
            done
          '';
        in
        {
          name = "lacheck";
          description = "A consistency checker for LaTeX documents.";
          types = [ "file" "tex" ];
          package = texliveCombine;
          entry = "${script}";
        };
      lua-ls =
        let
          # .luarc.json has to be in a directory,
          # or lua-language-server will hang forever.
          luarc = pkgs.writeText ".luarc.json" (builtins.toJSON hooks.lua-ls.settings.configuration);
          luarc-dir = pkgs.stdenv.mkDerivation {
            name = "luarc";
            unpackPhase = "true";
            installPhase = ''
              mkdir $out
              cp ${luarc} $out/.luarc.json
            '';
          };
          script = pkgs.writeShellApplication {
            name = "lua-ls-lint";
            runtimeInputs = [ hooks.lua-ls.package pkgs.jq ];
            checkPhase = ""; # The default checkPhase depends on GHC
            text = ''
              set -e
              export logpath="$(mktemp -d)"
              lua-language-server --check $(realpath .) \
                --checklevel="${hooks.lua-ls.settings.checklevel}" \
                --configpath="${luarc-dir}/.luarc.json" \
                --logpath="$logpath"
              if [[ -f $logpath/check.json ]]; then
                echo "+++++++++++++++ lua-language-server diagnostics +++++++++++++++"
                cat $logpath/check.json
                diagnostic_count=$(jq 'length' $logpath/check.json)
                if [ "$diagnostic_count" -gt 0 ]; then
                  exit 1
                fi
              fi
            '';
          };
        in
        {
          name = "lua-ls";
          description = "Uses the lua-language-server CLI to statically type-check and lint Lua code.";
          package = tools.lua-language-server;
          entry = "${script}/bin/lua-ls-lint";
          files = "\\.lua$";
          pass_filenames = false;
        };
      luacheck =
        {
          name = "luacheck";
          description = "A tool for linting and static analysis of Lua code.";
          types = [ "file" "lua" ];
          package = tools.luacheck;
          entry = "${hooks.luacheck.package}/bin/luacheck";
        };
      lychee = {
        name = "lychee";
        description = "A fast, async, stream-based link checker that finds broken hyperlinks and mail addresses inside Markdown, HTML, reStructuredText, or any other text file or website.";
        package = tools.lychee;
        entry =
          let
            cmdArgs =
              mkCmdArgs
                (with hooks.lychee.settings; [
                  [ (configPath != "") " --config ${configPath}" ]
                ]);
          in
          "${hooks.lychee.package}/bin/lychee${cmdArgs} ${hooks.lychee.settings.flags}";
        types = [ "text" ];
      };
      markdownlint =
        {
          name = "markdownlint";
          description = "Style checker and linter for markdown files.";
          package = tools.markdownlint-cli;
          entry = "${hooks.markdownlint.package}/bin/markdownlint -c ${pkgs.writeText "markdownlint.json" (builtins.toJSON hooks.markdownlint.settings.configuration)}";
          files = "\\.md$";
        };
      mdl =
        {
          name = "mdl";
          description = "A tool to check markdown files and flag style issues.";
          package = tools.mdl;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.mdl.settings; [
                    [ (configPath != "") "--config ${configPath}" ]
                    [ git-recurse "--git-recurse" ]
                    [ ignore-front-matter "--ignore-front-matter" ]
                    [ json "--json" ]
                    [ (rules != [ ]) "--rules ${lib.strings.concatStringsSep "," rules}" ]
                    [ (rulesets != [ ]) "--rulesets ${lib.strings.concatStringsSep "," rulesets}" ]
                    [ show-aliases "--show-aliases" ]
                    [ warnings "--warnings" ]
                    [ skip-default-ruleset "--skip-default-ruleset" ]
                    [ (style != "") "--style ${style}" ]
                    [ (tags != [ ]) "--tags ${lib.strings.concatStringsSep "," tags}" ]
                    [ verbose "--verbose" ]
                  ]);
            in
            "${hooks.mdl.package}/bin/mdl ${cmdArgs}";
          files = "\\.md$";
        };
      mdsh =
        let
          script = pkgs.writeShellScript "precommit-mdsh" ''
            for file in $(echo "$@"); do
                ${hooks.mdsh.package}/bin/mdsh -i "$file"
            done
          '';
        in
        {
          name = "mdsh";
          description = "Markdown shell pre-processor.";
          package = tools.mdsh;
          entry = toString script;
          files = "\\.md$";
        };
      mixed-line-endings = {
        name = "mixed-line-endings";
        description = "Resolve mixed line endings.";
        package = tools.pre-commit-hooks;
        entry = "${hooks.mixed-line-endings.package}/bin/mixed-line-ending";
        types = [ "text" ];
      };
      mix-format = {
        name = "mix-format";
        description = "Runs the built-in Elixir syntax formatter";
        package = tools.elixir;
        entry = "${hooks.mix-format.package}/bin/mix format";
        files = "\\.exs?$";
      };
      mix-test = {
        name = "mix-test";
        description = "Runs the built-in Elixir test framework";
        package = tools.elixir;
        entry = "${hooks.mix-test.package}/bin/mix test";
        files = "\\.exs?$";
      };
      mkdocs-linkcheck = {
        name = "mkdocs-linkcheck";
        description = "Validate links associated with markdown-based, statically generated websites.";
        package = tools.mkdocs-linkcheck;
        entry =
          let
            binPath = migrateBinPathToPackage hooks.mkdocs-linkcheck "/bin/mkdocs-linkcheck";
            cmdArgs =
              mkCmdArgs
                (with hooks.mkdocs-linkcheck.settings; [
                  [ local-only " --local" ]
                  [ recurse " --recurse" ]
                  [ (extension != "") " --ext ${extension}" ]
                  [ (method != "") " --method ${method}" ]
                  [ (path != "") " ${path}" ]
                ]);
          in
          "${binPath}${cmdArgs}";
        types = [ "text" "markdown" ];
      };
      mypy =
        {
          name = "mypy";
          description = "Static type checker for Python";

          package = tools.mypy;
          entry = migrateBinPathToPackage hooks.mypy "/bin/mypy";
          files = "\\.py$";
        };
      name-tests-test =
        {
          name = "mypy";
          description = "Verify that Python test files are named correctly.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.name-tests-test.package}/bin/tests_should_end_in_test.py";
          files = "(^|/)tests/\.+\\.py$";
        };
      nil =
        {
          name = "nil";
          description = "Incremental analysis assistant for writing in Nix.";
          package = tools.nil;
          entry =
            let
              script = pkgs.writeShellScript "precommit-nil" ''
                errors=false
                echo Checking: $@
                for file in $(echo "$@"); do
                  ${hooks.nil.package}/bin/nil diagnostics "$file"
                  exit_code=$?

                  if [[ $exit_code -ne 0 ]]; then
                    echo \"$file\" failed with exit code: $exit_code
                    errors=true
                  fi
                done
                if [[ $errors == true ]]; then
                  exit 1
                fi
              '';
            in
            builtins.toString script;
          files = "\\.nix$";
        };
      # nixfmt was renamed to nixfmt-classic.
      # The hook has been deprecated to free up the name for when the new RFC-style nixfmt becomes stable.
      nixfmt = nixfmt-classic;
      nixfmt-classic =
        {
          name = "nixfmt-classic";
          description = "Nix code prettifier (classic).";
          package = tools.nixfmt-classic;
          entry = "${hooks.nixfmt-classic.package}/bin/nixfmt ${lib.optionalString (hooks.nixfmt-classic.settings.width != null) "--width=${toString hooks.nixfmt-classic.settings.width}"}";
          files = "\\.nix$";
        };
      nixfmt-rfc-style =
        {
          name = "nixfmt-rfc-style";
          description = "Nix code prettifier (RFC 166 style).";
          package = tools.nixfmt-rfc-style;
          entry = "${hooks.nixfmt-rfc-style.package}/bin/nixfmt ${lib.optionalString (hooks.nixfmt-rfc-style.settings.width != null) "--width=${toString hooks.nixfmt-rfc-style.settings.width}"}";
          files = "\\.nix$";
        };
      nixpkgs-fmt =
        {
          name = "nixpkgs-fmt";
          description = "Nix code prettifier.";
          package = tools.nixpkgs-fmt;
          entry = "${hooks.nixpkgs-fmt.package}/bin/nixpkgs-fmt";
          files = "\\.nix$";
        };
      no-commit-to-branch =
        {
          name = "no-commit-to-branch";
          description = "Disallow committing to certain branch/branches.";
          pass_filenames = false;
          always_run = true;
          package = tools.pre-commit-hooks;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.no-commit-to-branch.settings; [
                    [ (branch != [ ]) "--branch ${lib.strings.concatStringsSep " --branch " branch}" ]
                    [ (pattern != [ ]) "--pattern ${lib.strings.concatStringsSep " --pattern " pattern}" ]
                  ]);
            in
            "${hooks.no-commit-to-branch.package}/bin/no-commit-to-branch ${cmdArgs}";
        };
      ocp-indent =
        {
          name = "ocp-indent";
          description = "A tool to indent OCaml code.";
          package = tools.ocp-indent;
          entry = "${hooks.ocp-indent.package}/bin/ocp-indent --inplace";
          files = "\\.mli?$";
        };
      opam-lint =
        {
          name = "opam lint";
          description = "OCaml package manager configuration checker.";
          package = tools.opam;
          entry = "${hooks.opam-lint.package}/bin/opam lint";
          files = "\\.opam$";
        };
      ormolu =
        {
          name = "ormolu";
          description = "Haskell code prettifier.";
          package = tools.ormolu;
          entry =
            let
              extensions =
                lib.escapeShellArgs (lib.concatMap (ext: [ "--ghc-opt" "-X${ext}" ]) hooks.ormolu.settings.defaultExtensions);
              cabalExtensions =
                if hooks.ormolu.settings.cabalDefaultExtensions then "--cabal-default-extensions" else "";
            in
            "${hooks.ormolu.package}/bin/ormolu --mode inplace ${extensions} ${cabalExtensions}";
          files = "\\.l?hs(-boot)?$";
        };
      php-cs-fixer =
        {
          name = "php-cs-fixer";
          description = "Lint PHP files.";

          package = tools.php-cs-fixer;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.php-cs-fixer "/bin/php-cs-fixer";
            in
            "${binPath} fix";
          types = [ "php" ];
        };
      phpcbf =
        {
          name = "phpcbf";
          description = "Lint PHP files.";

          package = tools.phpcbf;
          entry = migrateBinPathToPackage hooks.phpcbf "/bin/phpcbf";
          types = [ "php" ];
        };
      phpcs =
        {
          name = "phpcs";
          description = "Lint PHP files.";

          package = tools.phpcs;
          entry = migrateBinPathToPackage hooks.phpcs "/bin/phpcs";
          types = [ "php" ];
        };
      phpstan =
        {
          name = "phpstan";
          description = "Static Analysis of PHP files.";

          package = tools.phpstan;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.phpstan "/bin/phpstan";
            in
            "${binPath} analyse";
          types = [ "php" ];
        };
      pretty-format-json =
        {
          name = "pretty-format-json";
          description = "Formats JSON files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.pretty-format-json.package}/bin/pretty-format-json";
          types = [ "json" ];
        };
      poetry-check = {
        name = "poetry check";
        description = "Check the Poetry config for errors";
        package = tools.poetry;
        entry = "${hooks.poetry-check.package}/bin/poetry check";
        files = "^(poetry\\.lock$|pyproject\\.toml)$";
        pass_filenames = false;
      };
      poetry-lock = {
        name = "poetry lock";
        description = "Update the Poetry lock file";
        package = tools.poetry;
        entry = "${hooks.poetry-lock.package}/bin/poetry lock";
        files = "^(poetry\\.lock$|pyproject\\.toml)$";
        pass_filenames = false;
      };
      pre-commit-hook-ensure-sops = {
        name = "pre-commit-hook-ensure-sops";
        package = tools.pre-commit-hook-ensure-sops;
        entry =
          ## NOTE: pre-commit-hook-ensure-sops landed in nixpkgs on 8 July 2022. Once it reaches a
          ## release of NixOS, the `throwIf` piece of code below will become
          ## useless.
          lib.throwIf
            (hooks.pre-commit-hook-ensure-sops.package == null)
            "The version of nixpkgs used by git-hooks.nix does not have the `pre-commit-hook-ensure-sops` package. Please use a more recent version of nixpkgs."
            ''
              ${hooks.pre-commit-hook-ensure-sops.package}/bin/pre-commit-hook-ensure-sops
            '';
        files = "^secrets";
      };
      # See all CLI flags for prettier [here](https://prettier.io/docs/en/cli.html).
      # See all options for prettier [here](https://prettier.io/docs/en/options.html).
      prettier =
        {
          name = "prettier";
          description = "Opinionated multi-language code formatter.";
          types = [ "text" ];

          package = tools.prettier;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.prettier "/bin/prettier";
              cmdArgs =
                mkCmdArgs
                  (with hooks.prettier.settings; [
                    [ (allow-parens != "always") "--allow-parens ${allow-parens}" ]
                    [ bracket-same-line "--bracket-same-line" ]
                    [ cache "--cache" ]
                    [ (cache-location != "./node_modules/.cache/prettier/.prettier-cache") "--cache-location ${cache-location}" ]
                    [ (cache-strategy != null) "--cache-strategy ${cache-strategy}" ]
                    [ check "--check" ]
                    [ (!color) "--no-color" ]
                    [ (configPath != "") "--config ${configPath}" ]
                    [ (config-precedence != "cli-override") "--config-precedence ${config-precedence}" ]
                    [ (embedded-language-formatting != "auto") "--embedded-language-formatting ${embedded-language-formatting}" ]
                    [ (end-of-line != "lf") "--end-of-line ${end-of-line}" ]
                    [ (html-whitespace-sensitivity != "css") "--html-whitespace-sensitivity ${html-whitespace-sensitivity}" ]
                    [ (ignore-path != [ ]) "--ignore-path ${lib.escapeShellArgs ignore-path}" ]
                    [ ignore-unknown "--ignore-unknown" ]
                    [ insert-pragma "--insert-pragma" ]
                    [ jsx-single-quote "--jsx-single-quote" ]
                    [ list-different "--list-different" ]
                    [ (log-level != "log") "--log-level ${log-level}" ]
                    [ no-bracket-spacing "--no-bracket-spacing" ]
                    [ no-config "--no-config" ]
                    [ no-editorconfig "--no-editorconfig" ]
                    [ no-error-on-unmatched-pattern "--no-error-on-unmatched-pattern" ]
                    [ no-semi "--no-semi" ]
                    [ (parser != "") "--parser ${parser}" ]
                    [ (print-width != 80) "--print-width ${toString print-width}" ]
                    [ (prose-wrap != "preserve") "--prose-wrap ${prose-wrap}" ]
                    [ (plugins != [ ]) "--plugin ${lib.strings.concatStringsSep " --plugin " plugins}" ]
                    [ (quote-props != "as-needed") "--quote-props ${quote-props}" ]
                    [ require-pragma "--require-pragma" ]
                    [ single-attribute-per-line "--single-attribute-per-line" ]
                    [ single-quote "--single-quote" ]
                    [ (tab-width != 2) "--tab-width ${toString tab-width}" ]
                    [ (trailing-comma != "all") "--trailing-comma ${trailing-comma}" ]
                    [ use-tabs "--use-tabs" ]
                    [ vue-indent-script-and-style "--vue-indent-script-and-style" ]
                    [ with-node-modules "--with-node-modules" ]
                    [ write "--write" ]
                  ]);
            in
            "${binPath} ${cmdArgs}";
        };
      psalm =
        {
          name = "psalm";
          description = "Static Analysis of PHP files.";

          package = tools.psalm;
          entry = migrateBinPathToPackage hooks.psalm "/bin/psalm";
          types = [ "php" ];
        };
      purs-tidy =
        {
          name = "purs-tidy";
          description = "Format purescript files.";
          package = tools.purs-tidy;
          entry = "${hooks.purs-tidy.package}/bin/purs-tidy format-in-place";
          files = "\\.purs$";
        };
      purty =
        {
          name = "purty";
          description = "Format purescript files.";
          package = tools.purty;
          entry = "${hooks.purty.package}/bin/purty";
          files = "\\.purs$";
        };
      pylint =
        {
          name = "pylint";
          description = "Lint Python files.";

          package = tools.pylint;
          entry =
            let
              binPath = migrateBinPathToPackage hooks.pylint "/bin/pylint";
              cmdArgs =
                mkCmdArgs
                  (with hooks.pylint.settings; [
                    [ reports "-ry" ]
                    [ (! score) "-sn" ]
                  ]);
            in
            "${binPath} ${cmdArgs}";
          types = [ "python" ];
        };
      pyright =
        {
          name = "pyright";
          description = "Static type checker for Python";

          package = tools.pyright;
          entry = migrateBinPathToPackage hooks.pyright "/bin/pyright";
          files = "\\.py$";
        };
      python-debug-statements =
        {
          name = "python-debug-statements";
          description = "Check for debugger imports and py37+ `breakpoint()` calls in python source.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.python-debug-statements.package}/bin/debug-statement-hook";
          types = [ "python" ];
        };
      pyupgrade =
        {
          name = "pyupgrade";
          description = "Automatically upgrade syntax for newer versions.";

          package = tools.pyupgrade;
          entry = migrateBinPathToPackage hooks.pyupgrade "/bin/pyupgrade";
          types = [ "python" ];
        };
      reuse =
        {
          name = "reuse";
          description = "reuse is a tool for compliance with the REUSE recommendations.";
          package = tools.reuse;
          entry = "${hooks.reuse.package}/bin/reuse lint ${hooks.reuse.settings.flags}";
          types = [ "file" ];
          pass_filenames = false;
        };
      revive =
        {
          name = "revive";
          description = "A linter for Go source code.";
          package = tools.revive;
          entry =
            let
              cmdArgs =
                mkCmdArgs [
                  [ true "-set_exit_status" ]
                  [ (hooks.revive.settings.configPath != "") "-config ${hooks.revive.settings.configPath}" ]
                ];
              # revive works with both files and directories; however some lints
              # may fail (e.g. package-comment) if they run on an individual file
              # rather than a package/directory scope; given this let's get the
              # directories from each individual file.
              script = pkgs.writeShellScript "precommit-revive" ''
                set -e
                for dir in $(echo "$@" | xargs -n1 dirname | sort -u); do
                  ${hooks.revive.package}/bin/revive ${cmdArgs} ./"$dir"
                done
              '';
            in
            builtins.toString script;
          files = "\\.go$";
          # to avoid multiple invocations of the same directory input, provide
          # all file names in a single run.
          require_serial = true;
        };
      ripsecrets =
        {
          name = "ripsecrets";
          description = "Prevent committing secret keys into your source code";
          package = tools.ripsecrets;
          entry =
            let
              cmdArgs = mkCmdArgs (
                with hooks.ripsecrets.settings; [
                  [ true "--strict-ignore" ]
                  [
                    (additionalPatterns != [ ])
                    "--additional-pattern ${lib.strings.concatStringsSep " --additional-pattern " additionalPatterns}"
                  ]
                ]
              );
            in
            "${hooks.ripsecrets.package}/bin/ripsecrets ${cmdArgs}";
          types = [ "text" ];
        };
      rome = biome;
      ruff =
        {
          name = "ruff";
          description = "An extremely fast Python linter, written in Rust.";
          package = tools.ruff;
          entry = "${hooks.ruff.package}/bin/ruff check --fix";
          types = [ "python" ];
        };
      ruff-format =
        {
          name = "ruff-format";
          description = "An extremely fast Python code formatter, written in Rust.";
          package = tools.ruff;
          entry = "${hooks.ruff.package}/bin/ruff format";
          types = [ "python" ];
        };
      rustfmt =
        let
          mkAdditionalArgs = args: lib.optionalString (args != "") " -- ${args}";

          inherit (hooks.rustfmt) packageOverrides;
          wrapper = pkgs.symlinkJoin {
            name = "rustfmt-wrapped";
            paths = [ packageOverrides.rustfmt ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-fmt \
              --prefix PATH : ${lib.makeBinPath (builtins.attrValues packageOverrides)}
            '';
          };
        in
        {
          name = "rustfmt";
          description = "Format Rust code.";
          package = wrapper;
          packageOverrides = { inherit (tools) cargo rustfmt; };
          entry =
            let
              inherit (hooks) rustfmt;
              inherit (rustfmt) settings;
              cargoArgs = lib.cli.toGNUCommandLineShell { } {
                inherit (settings) all package verbose;
              };
              rustfmtArgs = lib.cli.toGNUCommandLineShell { } {
                inherit (settings) check emit config-path color files-with-diff config verbose;
              };
            in
            "${rustfmt.package}/bin/cargo-fmt fmt ${cargoArgs}${mkAdditionalArgs rustfmtArgs}";
          files = "\\.rs$";
          pass_filenames = false;
        };
      shellcheck =
        {
          name = "shellcheck";
          description = "Format shell files.";
          types = [ "shell" ];
          package = tools.shellcheck;
          entry = "${hooks.shellcheck.package}/bin/shellcheck";
        };
      shfmt =
        {
          name = "shfmt";
          description = "Format shell files.";
          types = [ "shell" ];
          package = tools.shfmt;
          entry =
            let
              simplify = if hooks.shfmt.settings.simplify then "-s" else "";
            in
            "${hooks.shfmt.package}/bin/shfmt -w -l ${simplify}";
        };
      single-quoted-strings =
        {
          name = "single-quoted-strings";
          description = "Replace double quoted strings with single quoted strings.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.single-quoted-strings.package}/bin/double-quote-string-fixer";
          types = [ "python" ];
        };
      sort-file-contents =
        {
          name = "sort-file-contents";
          description = "Sort the lines in specified files (defaults to alphabetical).";
          types = [ "text" ];
          package = tools.pre-commit-hooks;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.sort-file-contents.settings;
                  [
                    [ ignore-case "--ignore-case" ]
                    [ unique "--unique" ]
                  ]);
            in
            "${hooks.sort-file-contents.package}/bin/file-contents-sorter ${cmdArgs}";
        };
      sort-requirements-txt =
        {
          name = "sort-requirements.txt";
          description = "Sort requirements in requirements.txt and constraints.txt files.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.sort-requirements-txt.package}/bin/requirements-txt-fixer";
          files = "\\.*(requirements|constraints)\\.*\\.txt$";
        };
      sort-simple-yaml =
        {
          name = "sort-simple-yaml";
          description = "Sort simple YAML files which consist only of top-level keys, preserving comments and blocks.";
          package = tools.pre-commit-hooks;
          entry = "${hooks.sort-simple-yaml.package}/bin/sort-simple-yaml";
          files = "(\\.yaml$)|(\\.yml$)";
        };
      staticcheck =
        {
          name = "staticcheck";
          description = "State of the art linter for the Go programming language";
          package = tools.go-tools;
          # staticheck works with directories.
          entry =
            let
              script = pkgs.writeShellScript "precommit-staticcheck" ''
                err=0
                for dir in $(echo "$@" | xargs -n1 dirname | sort -u); do
                  ${hooks.staticcheck.package}/bin/staticcheck ./"$dir"
                  code="$?"
                  if [[ "$err" -eq 0 ]]; then
                     err="$code"
                  fi
                done
                exit $err
              '';
            in
            builtins.toString script;
          files = "\\.go$";
          # to avoid multiple invocations of the same directory input, provide
          # all file names in a single run.
          require_serial = true;
        };
      statix =
        {
          name = "statix";
          description = "Lints and suggestions for the Nix programming language.";
          package = tools.statix;
          entry =
            let
              inherit (hooks.statix) package settings;
              mkOptionName = k:
                if builtins.stringLength k == 1
                then "-${k}"
                else "--${k}";
              options = lib.cli.toGNUCommandLineShell
                {
                  # instead of repeating the option name for each element,
                  # create a single option with a space-separated list of unique values.
                  mkList = k: v: if v == [ ] then [ ] else [ (mkOptionName k) ] ++ lib.unique v;
                }
                settings;
            in
            "${package}/bin/statix check ${options}";
          files = "\\.nix$";
          pass_filenames = false;
        };
      stylish-haskell =
        {
          name = "stylish-haskell";
          description = "A simple Haskell code prettifier";
          package = tools.stylish-haskell;
          entry = "${hooks.stylish-haskell.package}/bin/stylish-haskell --inplace";
          files = "\\.l?hs(-boot)?$";
        };
      stylua =
        {
          name = "stylua";
          description = "An Opinionated Lua Code Formatter.";
          types = [ "file" "lua" ];
          package = tools.stylua;
          entry = "${hooks.stylua.package}/bin/stylua --respect-ignores";
        };
      tagref =
        {
          name = "tagref";
          description = ''
            Have tagref check all references and tags.
          '';
          package = tools.tagref;
          entry = "${hooks.tagref.package}/bin/tagref";
          types = [ "text" ];
          pass_filenames = false;
        };
      taplo =
        {
          name = "taplo";
          description = "Format TOML files with taplo fmt";
          package = tools.taplo;
          entry = "${hooks.taplo.package}/bin/taplo fmt";
          types = [ "toml" ];
        };
      terraform-format =
        {
          name = "terraform-format";
          description = "Format terraform (`.tf`) files.";
          package = tools.terraform-fmt;
          entry = "${hooks.terraform-format.package}/bin/terraform-fmt";
          files = "\\.tf$";
        };
      terraform-validate =
        {
          name = "terraform-validate";
          description = "Validates terraform configuration files (`.tf`).";
          package = tools.terraform-validate;
          entry = "${hooks.terraform-validate.package}/bin/terraform-validate";
          files = "\\.(tf(vars)?|terraform\\.lock\\.hcl)$";
          excludes = [ "\\.terraform/.*$" ];
          require_serial = true;
        };
      tflint =
        {
          name = "tflint";
          description = "A Pluggable Terraform Linter.";
          package = tools.tflint;
          entry = "${hooks.tflint.package}/bin/tflint";
          files = "\\.tf$";
        };
      topiary =
        {
          name = "topiary";
          description = "A universal formatter engine within the Tree-sitter ecosystem, with support for many languages.";
          package = tools.topiary;
          entry =
            ## NOTE: Topiary landed in nixpkgs on 2 Dec 2022. Once it reaches a
            ## release of NixOS, the `throwIf` piece of code below will become
            ## useless.
            lib.throwIf
              (hooks.topiary.package == null)
              "The version of nixpkgs used by git-hooks.nix does not have the `topiary` package. Please use a more recent version of nixpkgs."
              (
                let
                  topiary-inplace = pkgs.writeShellApplication {
                    name = "topiary-inplace";
                    text = ''
                      for file; do
                        ${hooks.topiary.package}/bin/topiary --in-place --input-file "$file"
                      done
                    '';
                  };
                in
                "${topiary-inplace}/bin/topiary-inplace"
              );
          files = "(\\.json$)|(\\.toml$)|(\\.mli?$)";
        };
      treefmt =
        let
          inherit (hooks.treefmt) packageOverrides settings;
          wrapper =
            pkgs.writeShellApplication {
              name = "treefmt";
              runtimeInputs = [
                packageOverrides.treefmt
              ] ++ settings.formatters;

              text =
                ''
                  exec treefmt "$@"
                '';
            };
        in
        {
          name = "treefmt";
          description = "One CLI to format the code tree.";
          types = [ "file" ];
          pass_filenames = true;
          package = wrapper;
          packageOverrides = { treefmt = tools.treefmt; };
          entry = "${hooks.treefmt.package}/bin/treefmt --fail-on-change";
        };
      trim-trailing-whitespace =
        {
          name = "trim-trailing-whitespace";
          description = "Trim trailing whitespace.";
          types = [ "text" ];
          stages = [ "commit" "push" "manual" ];
          package = tools.pre-commit-hooks;
          entry = "${hooks.trim-trailing-whitespace.package}/bin/trailing-whitespace-fixer";
        };
      trufflehog =
        {
          name = "trufflehog";
          description = "Secrets scanner";
          entry =
            let
              script = pkgs.writeShellScript "precommit-trufflehog" ''
                set -e
                ${hooks.trufflehog.package}/bin/trufflehog --no-update git "file://$(git rev-parse --show-top-level)" --since-commit HEAD --only-verified --fail
              '';
            in
            builtins.toString script;
          package = tools.trufflehog;

          # trufflehog expects to run across the whole repo, not particular files
          pass_filenames = false;
        };
      typos =
        {
          name = "typos";
          description = "Source code spell checker";
          package = tools.typos;
          entry =
            let
              # Concatenate config in config file with section for ignoring words generated from list of words to ignore
              configuration = "${hooks.typos.settings.configuration}" + lib.strings.optionalString (hooks.typos.settings.ignored-words != [ ]) "\n\[default.extend-words\]" + lib.strings.concatMapStrings (x: "\n${x} = \"${x}\"") hooks.typos.settings.ignored-words;
              configFile = builtins.toFile "typos-config.toml" configuration;
              cmdArgs =
                mkCmdArgs
                  (with hooks.typos.settings; [
                    [ binary "--binary" ]
                    [ (color != "auto") "--color ${color}" ]
                    [ (configuration != "") "--config ${configFile}" ]
                    [ (configPath != "" && configuration == "") "--config ${configPath}" ]
                    [ diff "--diff" ]
                    [ (exclude != "") "--exclude ${exclude} --force-exclude" ]
                    [ (format != "long") "--format ${format}" ]
                    [ hidden "--hidden" ]
                    [ (locale != "en") "--locale ${locale}" ]
                    [ no-check-filenames "--no-check-filenames" ]
                    [ no-check-files "--no-check-files" ]
                    [ no-unicode "--no-unicode" ]
                    [ quiet "--quiet" ]
                    [ verbose "--verbose" ]
                    [ (write && !diff) "--write-changes" ]
                  ]);
            in
            "${hooks.typos.package}/bin/typos ${cmdArgs}";
          types = [ "text" ];
        };
      typstfmt = {
        name = "typstfmt";
        description = "format typst";
        package = tools.typstfmt;
        entry = "${hooks.typstfmt.package}/bin/typstfmt";
        files = "\\.typ$";
      };
      typstyle = {
        name = "typstyle";
        description = "Beautiful and reliable typst code formatter";
        package = tools.typstyle;
        entry =
          lib.throwIf
            (hooks.typstyle.package == null)
            "The version of nixpkgs used by git-hooks.nix must contain typstyle"
            "${hooks.typstyle.package}/bin/typstyle -i";
        files = "\\.typ$";
      };
      vale = {
        name = "vale";
        description = "A markup-aware linter for prose built with speed and extensibility in mind.";
        package = tools.vale;
        entry =
          let
            # TODO: was .vale.ini, threw error in Nix
            configFile = builtins.toFile "vale.ini" "${hooks.vale.settings.config}";
            cmdArgs =
              mkCmdArgs
                (with hooks.vale.settings; [
                  [ (configPath != "") " --config ${configPath}" ]
                  [ (configuration != "" && configPath == "") " --config ${configFile}" ]
                ]);
          in
          "${hooks.vale.package}/bin/vale${cmdArgs} ${hooks.vale.settings.flags}";
        types = [ "text" ];
      };
      yamlfmt =
        {
          name = "yamlfmt";
          description = "Formatter for YAML files.";
          types = [ "file" "yaml" ];
          package = tools.yamlfmt;
          entry =
            let
              cmdArgs =
                mkCmdArgs
                  (with hooks.yamlfmt.settings; [
                    # Exit non-zero on changes
                    [ true "-lint" ]
                    # But do not print the diff
                    [ true "-quiet" ]
                    # See https://github.com/google/yamlfmt/blob/main/docs/config-file.md#config-file-discovery
                    [ (configPath != "") "-conf ${configPath}" ]
                  ]);
            in
            "${hooks.yamlfmt.package}/bin/yamlfmt ${cmdArgs}";
        };
      yamllint =
        {
          name = "yamllint";
          description = "Linter for YAML files.";
          types = [ "file" "yaml" ];
          package = tools.yamllint;
          entry =
            let
              configFile = builtins.toFile "yamllint.yaml" "${hooks.yamllint.settings.configuration}";
              cmdArgs =
                mkCmdArgs
                  (with hooks.yamllint.settings; [
                    # Priorize multiline configuration over serialized configuration and configuration file
                    [ (configuration != "") "--config-file ${configFile}" ]
                    [ (configData != "" && configuration == "") "--config-data \"${configData}\"" ]
                    [ (configPath != "" && configData == "" && configuration == "" && preset == "default") "--config-file ${configPath}" ]
                    [ (format != "auto") "--format ${format}" ]
                    [ (preset != "default" && configuration == "") "--config-data ${preset}" ]
                    [ strict "--strict" ]
                  ]);
            in
            "${hooks.yamllint.package}/bin/yamllint ${cmdArgs}";
        };
      zprint =
        {
          name = "zprint";
          description = "Beautifully format Clojure and Clojurescript source code and s-expressions.";
          package = tools.zprint;
          entry = "${hooks.zprint.package}/bin/zprint '{:search-config? true}' -w";
          types_or = [ "clojure" "clojurescript" "edn" ];
        };

    };
}
