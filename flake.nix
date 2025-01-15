{
  description = "OpenJKDF2 - Open-source reimplementation of Star Wars Jedi Knight: Dark Forces II";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.permittedInsecurePackages = [
            "openssl-1.1.1w"
          ];
        };
        
        # Use Clang stdenv (required by OpenJKDF2)
        stdenv = if pkgs.stdenv.isDarwin then pkgs.stdenv else pkgs.llvmPackages.stdenv;
        
        # System-specific dependencies
        systemDeps = if pkgs.stdenv.isDarwin then
          with pkgs.darwin.apple_sdk.frameworks; [
            Cocoa
            IOKit
            ForceFeedback
            CoreAudio
            AudioUnit
            AudioToolbox
          ]
        else [ # Linux dependencies
          pkgs.gtk3
          pkgs.libGL
          pkgs.libGLU
          pkgs.xorg.libX11
          pkgs.xorg.libXext
          pkgs.xorg.libXrandr
          pkgs.xorg.libXinerama
          pkgs.xorg.libXcursor
          pkgs.xorg.libXi
          pkgs.xorg.libXScrnSaver
          pkgs.xorg.libXxf86vm
          pkgs.udev
          pkgs.alsa-lib
          pkgs.pulseaudio
          pkgs.libpulseaudio
        ];
      in
      {
        packages.openjkdf2 = stdenv.mkDerivation rec {
          pname = "openjkdf2";
          version = "0.9.8";

          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let baseName = baseNameOf path;
              in !(baseName == "build" || baseName == ".git");
          };
          # Common build dependencies
          buildInputs = with pkgs; [
            # Graphics libraries
            libGL
            libGLU
            glew
            freeglut

            # Audio libraries
            openal

            # SDL libraries
            SDL2
            #SDL2.dev
            SDL2_mixer
            #SDL2_mixer.dev

            # Other libraries
            curl
            openssl_1_1
            zlib
            libpng
            libmodplug
            protobuf
            physfs

          ] ++ systemDeps;

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            gnumake
            (pkgs.python3.withPackages (ps: [
              ps.cogapp
              (ps.buildPythonPackage rec {
                pname = "generate-iconset";
                version = "1.2.0";
                src = pkgs.fetchPypi {
                  inherit pname version;
                  sha256 = "3832ed222c9dcdda9c7d5754263d365734f111a1a1af8c97b63afbb123dde613";
                };
                pyproject = true;
                build-system = [ ps.setuptools ];
                doCheck = false;
              })
            ]))
            bison
            imagemagick
          ];

          patches = [ ./use-system-libs.patch ];

          # Platform-specific library extension
          libExt = if pkgs.stdenv.isDarwin then "dylib" else "so";

          # Handle Nix-specific substitutions in postPatch
          postPatch = ''
            # Fix SDL2_mixer include path to use dev package
            substituteInPlace cmake_modules/config_platform_deps.cmake \
              --replace-fail 'target_include_directories(SDL::Mixer INTERFACE ''${SDL2_MIXER_INCLUDE_DIRS})' \
                            'target_include_directories(SDL::Mixer INTERFACE ${pkgs.SDL2_mixer.dev}/include/SDL2)' \
              --replace-fail 'target_link_libraries(SDL::Mixer INTERFACE ''${SDL2_MIXER_LIBRARIES})' \
                            'target_link_libraries(SDL::Mixer INTERFACE ${pkgs.SDL2_mixer}/lib/libSDL2_mixer.${libExt})'
          '';

          # Configure with our fixes
          cmakeFlags = [
            "-DTARGET_USE_GAMENETWORKINGSOCKETS=OFF"
            "-DTARGET_USE_BASICSOCKETS=ON"
            "-DUSE_SYSTEM_COGAPP=ON"
            "-DCMAKE_CROSSCOMPILING=FALSE"
          ] ++ pkgs.lib.optionals (!pkgs.stdenv.isDarwin) [
            # Linux-specific flags
            "-DGLEW_FOUND=TRUE"
            "-DGLEW_INCLUDE_DIRS=${pkgs.glew.dev}/include"
            "-DGLEW_LIBRARIES=${pkgs.glew}/lib/libGLEW.so"
            "-DGLEW_LIBRARY=${pkgs.glew}/lib/libGLEW.so"
            "-DFreeGLUT_FOUND=TRUE"
            "-DGLUT_FOUND=TRUE"
            "-DGLUT_INCLUDE_DIR=${pkgs.freeglut.dev}/include"
            "-DGLUT_glut_LIBRARY=${pkgs.freeglut}/lib/libglut.so"
            "-DSDL2_FOUND=TRUE"
            "-DSDL2_INCLUDE_DIRS=${pkgs.SDL2.dev}/include/SDL2"
            "-DSDL2_LIBRARIES=${pkgs.SDL2}/lib/libSDL2.so"
            "-DSDL2_MIXER_FOUND=TRUE"
            "-DSDL2_MIXER_INCLUDE_DIRS=${pkgs.SDL2_mixer}/include/SDL2"
            "-DSDL2_MIXER_LIBRARIES=${pkgs.SDL2_mixer}/lib/libSDL2_mixer.so"
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS-specific flags
            "-DSKIP_MACOS_BUNDLE=ON"  # Skip .app bundle creation for Nix
            "-DSDL2_FOUND=TRUE"
            "-DSDL2_INCLUDE_DIRS=${pkgs.SDL2.dev}/include/SDL2"
            "-DSDL2_LIBRARIES=${pkgs.SDL2}/lib/libSDL2.dylib"
            "-DSDL2_MIXER_FOUND=TRUE"
            "-DSDL2_MIXER_INCLUDE_DIRS=${pkgs.SDL2_mixer.dev}/include/SDL2"
            "-DSDL2_MIXER_LIBRARIES=${pkgs.SDL2_mixer}/lib/libSDL2_mixer.dylib"
          ];

          # Set environment variables
          #CC = "${stdenv.cc}/bin/clang";
          #CXX = "${stdenv.cc}/bin/clang++";
          
          # Set PKG_CONFIG_PATH for finding system packages
          # PKG_CONFIG_PATH = pkgs.lib.makeSearchPath "lib/pkgconfig" [
          #   pkgs.SDL2
          #   pkgs.SDL2_mixer
          #   pkgs.openal
          #   pkgs.glew
          #   pkgs.freeglut
          #   pkgs.libpng
          #   pkgs.physfs
          #   pkgs.zlib
          #   pkgs.libGL
          # ] + ":" + pkgs.lib.makeSearchPath "share/pkgconfig" [
          #   pkgs.SDL2
          #   pkgs.SDL2_mixer
          # ];

          # Install the binary (name differs by platform)
          installPhase = ''
            mkdir -p $out/bin
            if [ -f openjkdf2-64 ]; then
              cp openjkdf2-64 $out/bin/openjkdf2
            else
              cp openjkdf2 $out/bin/
            fi
          '';

          meta = with pkgs.lib; {
            description = "Open-source reimplementation of Star Wars Jedi Knight: Dark Forces II";
            longDescription = ''
              OpenJKDF2 is a function-by-function reimplementation of Star Wars Jedi Knight: 
              Dark Forces II (DF2) in C, providing 64-bit ports to Windows, macOS, and Linux. 
              This is a reverse-engineered game engine reconstruction, not an emulator - it 
              recreates the original game's functionality through careful decompilation and analysis.
              
              Note: This package does not include game assets. You need the original 
              Jedi Knight: Dark Forces II game files to play.
            '';
            homepage = "https://github.com/OpenJKDF2/OpenJKDF2";
            license = licenses.gpl2Only;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        packages.default = self.packages.${system}.openjkdf2;

        # Keep the development shell for development work
        devShells.default = pkgs.mkShell {
          #nativeBuildInputs = commonNativeBuildInputs;
          #buildInputs = commonBuildInputs;
          
          shellHook = ''
            # Set compiler to Clang (required by OpenJKDF2)  
            export CC=${stdenv.cc}/bin/clang
            export CXX=${stdenv.cc}/bin/clang++
            
            # Initialize git submodules if not already done
            if [ ! -f "3rdparty/json/CMakeLists.txt" ]; then
              echo "Initializing git submodules..."
              ${pkgs.git}/bin/git submodule update --init --recursive
              echo "Git submodules initialized."
              echo ""
            fi
            
            echo "=== OpenJKDF2 Development Environment ==="
            echo "System: ${system}"
            echo "Compiler: $(${stdenv.cc}/bin/clang --version | head -1)"
            echo "CMake: $(${pkgs.cmake}/bin/cmake --version | head -1)"
            echo ""
            echo "To build the package:"
            echo "  nix build .#openjkdf2"
            echo ""
            echo "To run the package:"
            echo "  nix run .#openjkdf2"
            echo ""
            echo "To develop manually:"
            echo "  mkdir -p build && cd build"
            echo "  cmake .. -DTARGET_USE_GAMENETWORKINGSOCKETS=OFF -DTARGET_USE_BASICSOCKETS=ON"
            echo "  make -j\$(nproc) openjkdf2"
            echo ""
          '';
        };

        # Make it runnable with nix run
        apps.openjkdf2 = flake-utils.lib.mkApp {
          drv = self.packages.${system}.openjkdf2;
        };

        apps.default = self.apps.${system}.openjkdf2;
      });
}
