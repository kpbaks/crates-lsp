{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mkflake.url = "github:jonascarpay/mkflake";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      mkflake,
      crane,
      ...
    }:
    mkflake.lib.mkflake {
      perSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          # craneLib = crane.mkLib pkgs;

          # NB: we don't need to overlay our custom toolchain for the *entire*
          # pkgs (which would require rebuidling anything else which uses rust).
          # Instead, we just want to update the scope that crane will use by appending
          # our specific toolchain there.
          craneLib = (crane.mkLib pkgs).overrideToolchain (
            p:
            p.rust-bin.stable.latest.default.override {
              extensions = [ "rust-analyzer" ];
            }
          );

          crates-lsp = craneLib.buildPackage {
            src = craneLib.cleanCargoSource ./.;
            strictDeps = true;
            buildInputs = with pkgs; [
              openssl
            ];

            nativeBuildInputs = with pkgs; [
              pkg-config
            ];
          };
        in
        {
          checks = { inherit crates-lsp; };
          packages.default = crates-lsp;

          devShells.default = craneLib.devShell {

            checks = self.checks.${system};
          };

          # https://blog.katona.me/2025/01/12/Adding-crates-io-version-check-to-Helix-editor/
          homeModules.default = {
            home.packages = [ crates-lsp ];
            programs.helix = {
              extraPackages = [
                crates-lsp
              ];
              languages = {
                language-server.crates-lsp = {
                  command = "${pkgs.lib.getExe crates-lsp}";
                };

                language = [
                  {
                    name = "Cargo.toml";
                    scope = "source.toml";
                    injection-regex = "toml";
                    file-types = [ { glob = "Cargo.toml"; } ];
                    comment-token = "#";
                    language-servers = [ "crates-lsp" ];
                    grammar = "toml";
                    indent = {
                      tab-width = 2;
                      unit = "  ";
                    };
                    diagnostic-severity = "info";
                  }
                ];
              };
            };
          };

        };
    };

}
