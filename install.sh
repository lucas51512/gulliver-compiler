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
        brew install ghc cabal-install
    elif [ "$OS" = "Linux" ]; then
        echo "Linux detected."
        # For Ubuntu/Debian
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y ghc cabal-install libncurses-dev
        # For Fedora/RHEL
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y ghc cabal-install ncurses-devel
        # For Arch
        elif command -v pacman &> /dev/null; then
            sudo pacman -S ghc cabal-install
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

echo "Cabal version:"
cabal --version
echo ""

echo "Installing dependencies..."
cabal update

echo "Building Gulliver..."
cabal build

echo ""
echo "================================"
echo "Installation Complete!"
echo "================================"
echo ""
echo "To run Gulliver:"
echo "  cabal exec gulliver-cli -- examples/bell_state.gll"
echo ""
echo "To run tests:"
echo "  cabal test"
echo ""
echo "For more information, see README.md"
