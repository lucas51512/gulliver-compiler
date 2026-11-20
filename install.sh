#!/bin/bash
# Installation script for Gulliver Quantum Compiler

set -e

echo "================================"
echo "Gulliver Installation Script"
echo "================================"
echo ""

# Detect OS
OS=$(uname)
ARCH=$(uname -m)

echo "Detected: $OS ($ARCH)"
echo ""

# Check if Haskell Platform is installed
if ! command -v ghc &> /dev/null; then
    echo "GHC not found. Installing Haskell..."
    
    if [ "$OS" = "Darwin" ]; then
        echo "macOS detected. Using Homebrew..."
        brew install ghc
    elif [ "$OS" = "Linux" ]; then
        echo "Linux detected."
        # For Ubuntu/Debian
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y ghc libncurses-dev
        # For Fedora/RHEL
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y ghc ncurses-devel
        # For Arch
        elif command -v pacman &> /dev/null; then
            sudo pacman -S ghc
        else
            echo "Could not detect package manager. Please install GHC manually."
            exit 1
        fi
    else
        echo "Unsupported OS: $OS"
        echo "Please install GHC and Cabal manually from: https://www.haskell.org/downloads"
        exit 1
    fi
fi

echo "GHC version:"
ghc --version
echo ""

echo "Building Gulliver..."
mkdir -p build
ghc -dynamic -Wall -isrc -iapp -outputdir build -o build/gulliver app/Main.hs

echo ""
echo "================================"
echo "Installation Complete!"
echo "================================"
echo ""
echo "To run Gulliver:"
echo "  build/gulliver examples/bell_state.gll"
echo ""
echo "To run tests:"
echo "  mkdir -p build/test && ghc -dynamic -isrc -iapp -itest -outputdir build/test -o build/gulliver-test test/Main.hs && build/gulliver-test"
echo ""
echo "For more information, see README.md"
