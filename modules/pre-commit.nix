{ config, lib, pkgs, ... }:
let
  inherit (lib)
    attrNames
    concatStringsSep
    compare
    filterAttrs
    literalExample
    mapAttrsToList
    mkIf
    mkOption
    types
    ;

  inherit (pkgs) runCommand writeText git;

  cfg = config;
  install_stages = lib.unique (cfg.default_stages ++ (builtins.concatLists (lib.mapAttrsToList (_: h: h.stages) enabledHooks)));

  hookType = types.submodule {
    imports = [
      ({ ... }: { _module.args.default_stages = cfg.default_stages; })
      ./hook.nix
    ];
  };

  mergeExcludes =
    excludes:
    if excludes == [ ] then "^$" else "(${concatStringsSep "|" excludes})";

  enabledHooks = filterAttrs (id: value: value.enable) cfg.hooks;
  processedHooks =
    mapAttrsToList (id: value: value.raw // { inherit id; }) enabledHooks;

  configFile =
    performAssertions (
      runCommand "pre-commit-config.json"
        {
          buildInputs = [
            pkgs.jq
            # needs to be an input so we regenerate the config and reinstall the hooks
            # when the package changes
            cfg.package
          ];
          passAsFile = [ "rawJSON" ];
          rawJSON = builtins.toJSON cfg.rawConfig;
        } ''
        {
          echo '# DO NOT MODIFY';
          echo '# This file was generated by pre-commit-hooks.nix';
          jq . <"$rawJSONPath"
        } >$out
      ''
    );

  run =
    runCommand "pre-commit-run" { buildInputs = [ git ]; } ''
      set +e
      HOME=$PWD
      # Use `chmod +w` instead of `cp --no-preserve=mode` to be able to write and to
      # preserve the executable bit at the same time
      cp -R ${cfg.rootSrc} src
      chmod -R +w src
      ln -fs ${configFile} src/.pre-commit-config.yaml
      cd src
      rm -rf .git
      git init -q
      git add .
      git config --global user.email "you@example.com"
      git config --global user.name "Your Name"
      git commit -m "init" -q
      if [[ ${toString (compare install_stages [ "manual" ])} -eq 0 ]]
      then
        echo "Running: $ pre-commit run --hook-stage manual --all-files"
        ${cfg.package}/bin/pre-commit run --hook-stage manual --all-files
      else
        echo "Running: $ pre-commit run --all-files"
        ${cfg.package}/bin/pre-commit run --all-files
      fi
      exitcode=$?
      git --no-pager diff --color
      touch $out
      [ $? -eq 0 ] && exit $exitcode
    '';

  failedAssertions = builtins.map (x: x.message) (builtins.filter (x: !x.assertion) config.assertions);

  performAssertions =
    let
      formatAssertionMessage = message:
        let
          lines = lib.splitString "\n" message;
        in
        "- ${lib.concatStringsSep "\n  " lines}";
    in
    if failedAssertions != [ ]
    then
      throw ''
        Failed assertions:
        ${lib.concatStringsSep "\n" (builtins.map formatAssertionMessage failedAssertions)}
      ''
    else lib.trivial.showWarnings config.warnings;
in
{
  options =
    {

      package =
        mkOption {
          type = types.package;
          description = lib.mdDoc
            ''
              The `pre-commit` package to use.
            '';
          defaultText =
            lib.literalExpression or literalExample ''
              pkgs.pre-commit
            '';
        };

      tools =
        mkOption {
          type = types.lazyAttrsOf (types.nullOr types.package);
          description = lib.mdDoc
            ''
              Tool set from which `nix-pre-commit-hooks` will pick binaries.

              `nix-pre-commit-hooks` comes with its own set of packages for this purpose.
            '';
          defaultText =
            lib.literalExpression or literalExample ''pre-commit-hooks.nix-pkgs.callPackage tools-dot-nix { inherit (pkgs) system; }'';
        };

      enabledPackages = mkOption {
        type = types.listOf types.unspecified;
        description = lib.mdDoc
          ''
            All packages provided by hooks that are enabled.

            Useful for including into the developer environment.
          '';

        default = builtins.map (hook: hook.package) (lib.filter (hook: hook.enable) (builtins.attrValues config.hooks));
      };

      hooks =
        mkOption {
          type = types.submodule {
            freeformType = types.attrsOf hookType;
          };
          description = lib.mdDoc
            ''
              The hook definitions.

              You can both specify your own hooks here and you can enable predefined hooks.

              Example of enabling a predefined hook:

              ```nix
              hooks.nixpkgs-fmt.enable = true;
              ```

              Example of a custom hook:

              ```nix
              hooks.my-tool = {
                enable = true;
                name = "my-tool";
                description = "Run MyTool on all files in the project";
                files = "\\.mtl$";
                entry = "''${pkgs.my-tool}/bin/mytoolctl";
              };
              ```

              The predefined hooks are:

              ${
                lib.concatStringsSep
                  "\n"
                  (lib.mapAttrsToList
                    (hookName: hookConf:
                      ''
                        **`${hookName}`**

                        ${hookConf.description}

                      '')
                    config.hooks)
              }
            '';
          default = { };
        };

      run =
        mkOption {
          type = types.package;
          description = lib.mdDoc
            ''
              A derivation that tests whether the pre-commit hooks run cleanly on
              the entire project.
            '';
          readOnly = true;
          default = run;
          defaultText = "<derivation>";
        };

      installationScript =
        mkOption {
          type = types.str;
          description = lib.mdDoc
            ''
              A bash snippet that installs nix-pre-commit-hooks in the current directory
            '';
          readOnly = true;
        };

      src =
        lib.mkOption {
          description = lib.mdDoc ''
            Root of the project. By default this will be filtered with the `gitignoreSource`
            function later, unless `rootSrc` is specified.

            If you use the `flakeModule`, the default is `self.outPath`; the whole flake
            sources.
          '';
          type = lib.types.path;
        };

      rootSrc =
        mkOption {
          type = types.path;
          description = lib.mdDoc
            ''
              The source of the project to be checked.

              This is used in the derivation that performs the check.

              If you use the `flakeModule`, the default is `self.outPath`; the whole flake
              sources.
            '';
          defaultText = lib.literalExpression or literalExample ''gitignoreSource config.src'';
        };

      excludes =
        mkOption {
          type = types.listOf types.str;
          description = lib.mdDoc
            ''
              Exclude files that were matched by these patterns.
            '';
          default = [ ];
        };

      default_stages =
        mkOption {
          type = types.listOf types.str;
          description = lib.mdDoc
            ''
              A configuration wide option for the stages property.
              Installs hooks to the defined stages.
              See [https://pre-commit.com/#confining-hooks-to-run-at-certain-stages](https://pre-commit.com/#confining-hooks-to-run-at-certain-stages).
            '';
          default = [ "commit" ];
        };

      rawConfig =
        mkOption {
          type = types.attrs;
          description = lib.mdDoc
            ''
              The raw configuration before writing to file.

              This option does not have an appropriate merge function.
              It is accessible in case you need to set an attribute that doesn't have an option.
            '';
          internal = true;
        };

      assertions = lib.mkOption {
        type = types.listOf types.unspecified;
        internal = true;
        default = [ ];
        example = [{ assertion = false; message = "you can't enable this for that reason"; }];
        description = ''
          This option allows modules to express conditions that must
          hold for the evaluation of the configuration to succeed,
          along with associated error messages for the user.
        '';
      };

      warnings = lib.mkOption {
        type = types.listOf types.str;
        internal = true;
        default = [ ];
        example = [ "you should fix this or that" ];
        description = ''
          This option allows modules to express warnings about the
          configuration. For example, `lib.mkRenamedOptionModule` uses this to
          display a warning message when a renamed option is used.
        '';
      };
    };

  config =
    {

      rawConfig =
        {
          repos =
            [
              {
                repo = "local";
                hooks = processedHooks;
              }
            ];
        } // lib.optionalAttrs (cfg.excludes != [ ]) {
          exclude = mergeExcludes cfg.excludes;
        } // lib.optionalAttrs (cfg.default_stages != [ ]) {
          default_stages = cfg.default_stages;
        };

      installationScript =
        ''
          export PATH=${cfg.package}/bin:$PATH
          if ! type -t git >/dev/null; then
            # This happens in pure shells, including lorri
            echo 1>&2 "WARNING: pre-commit-hooks.nix: git command not found; skipping installation."
          elif ! ${git}/bin/git rev-parse --git-dir &> /dev/null; then
            echo 1>&2 "WARNING: pre-commit-hooks.nix: .git not found; skipping installation."
          else
            GIT_WC=`${git}/bin/git rev-parse --show-toplevel`

            # These update procedures compare before they write, to avoid
            # filesystem churn. This improves performance with watch tools like lorri
            # and prevents installation loops by via lorri.

            if ! readlink "''${GIT_WC}/.pre-commit-config.yaml" >/dev/null \
              || [[ $(readlink "''${GIT_WC}/.pre-commit-config.yaml") != ${configFile} ]]; then
              echo 1>&2 "pre-commit-hooks.nix: updating $PWD repo"

              [ -L .pre-commit-config.yaml ] && unlink .pre-commit-config.yaml

              if [ -e "''${GIT_WC}/.pre-commit-config.yaml" ]; then
                echo 1>&2 "pre-commit-hooks.nix: WARNING: Refusing to install because of pre-existing .pre-commit-config.yaml"
                echo 1>&2 "    1. Translate .pre-commit-config.yaml contents to the new syntax in your Nix file"
                echo 1>&2 "        see https://github.com/cachix/pre-commit-hooks.nix#getting-started"
                echo 1>&2 "    2. remove .pre-commit-config.yaml"
                echo 1>&2 "    3. add .pre-commit-config.yaml to .gitignore"
              else
                ln -fs ${configFile} "''${GIT_WC}/.pre-commit-config.yaml"
                # Remove any previously installed hooks (since pre-commit itself has no convergent design)
                hooks="pre-commit pre-merge-commit pre-push prepare-commit-msg commit-msg post-checkout post-commit"
                for hook in $hooks; do
                  pre-commit uninstall -t $hook
                done
                ${git}/bin/git config --local core.hooksPath ""
                # Add hooks for configured stages (only) ...
                if [ ! -z "${concatStringsSep " " install_stages}" ]; then
                  for stage in ${concatStringsSep " " install_stages}; do
                    if [[ "$stage" == "manual" ]]; then
                      continue
                    fi
                    case $stage in
                      # if you amend these switches please also review $hooks above
                      commit | merge-commit | push)
                        stage="pre-"$stage
                        pre-commit install -t $stage
                        ;;
                      prepare-commit-msg | commit-msg | post-checkout | post-commit)
                        pre-commit install -t $stage
                        ;;
                      *)
                        echo 1>&2 "ERROR: pre-commit-hooks.nix: either $stage is not a valid stage or pre-commit-hooks.nix doesn't yet support it."
                        exit 1
                        ;;
                    esac
                  done
                # ... or default 'pre-commit' hook
                else
                  pre-commit install
                fi

                # Fetch the absolute path to the git common directory. This will normally point to $GIT_WC/.git.
                common_dir=''$(${git}/bin/git rev-parse --path-format=absolute --git-common-dir)

                # Convert the absolute path to a path relative to the toplevel working directory.
                common_dir=''${common_dir#''$GIT_WC/}

                ${git}/bin/git config --local core.hooksPath "''$common_dir/hooks"
              fi
            fi
          fi
        '';
    };
}
