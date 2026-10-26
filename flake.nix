{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    haskell-flake.url = "github:srid/haskell-flake";
  };
  outputs =
    {
      self,
      nixpkgs,
      haskell-flake,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = (haskell-flake.lib { inherit pkgs; }).evalHaskellProject {
        projectRoot = self;
        modules = [
          {
            # Same options as haskellProjects.default = { ... }
            #settings = {
            ##  .haddock = false;
            #};
            devShell.tools = hp: {
              inherit (hp) ormolu cabal-gild;
            };
          }
        ];
      };
    in
    {
      packages.${system}.default = project.packages.dnsblockfind.package;
      devShells.${system}.default = project.devShell;
    };
}
