{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  unzip,
  wrapBuddy,
  fzf,
  ripgrep,
  versionCheckHook,
  versionCheckHomeHook,
  writeShellScriptBin,
}:

let
  pname = "opencode";
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  platformMap = {
    x86_64-linux = {
      asset = "opencode-linux-x64.tar.gz";
      isZip = false;
    };
    aarch64-linux = {
      asset = "opencode-linux-arm64.tar.gz";
      isZip = false;
    };
    x86_64-darwin = {
      asset = "opencode-darwin-x64.zip";
      isZip = true;
    };
    aarch64-darwin = {
      asset = "opencode-darwin-arm64.zip";
      isZip = true;
    };
  };

  platform = stdenv.hostPlatform.system;
  platformInfo = platformMap.${platform} or (throw "Unsupported system: ${platform}");

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/${platformInfo.asset}";
    hash = hashes.${platform};
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals platformInfo.isZip [
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wrapBuddy
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    (writeShellScriptBin "sysctl" "echo 0")
  ];
  versionCheckKeepEnvironment = "PATH";

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];

  wrapBuddyExtraNeeded = lib.optionals stdenv.hostPlatform.isLinux [
    "libstdc++.so.6"
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
  ''
  + lib.optionalString platformInfo.isZip ''
    unzip $src
  ''
  + lib.optionalString (!platformInfo.isZip) ''
    tar -xzf $src
  ''
  + ''
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 opencode $out/bin/opencode

    wrapProgram $out/bin/opencode \
      --prefix PATH : ${
        lib.makeBinPath [
          fzf
          ripgrep
        ]
      }

    runHook postInstall
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "AI coding agent built for the terminal";
    longDescription = ''
      OpenCode is a terminal-based agent that can build anything.
      It provides an interactive AI coding experience directly in your terminal.
    '';
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
}
