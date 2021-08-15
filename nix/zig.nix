# https://github.com/ziglang/zig/wiki/development-with-nix

{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  hardeningDisable = [ "all" ];
  buildInputs = with pkgs; [
    cmake
    gdb
    clang_12
    llvmPackages_12.clang-unwrapped
    llvm_12
    lld_12
    ninja
    qemu
    libxml2
  ];
}
