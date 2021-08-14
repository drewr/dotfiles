with (import <nixpkgs> {});

mkShell {
  buildInputs = [
    readline
    python3Packages.virtualenv
    python3Packages.click
  ];
}
