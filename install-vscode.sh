#!/usr/bin/env bash
set -euo pipefail
command -v git >/dev/null || { echo "git required"; exit 1; }
command -v npm >/dev/null || { echo "npm required"; exit 1; }
command -v code >/dev/null || { echo "VS Code CLI required"; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --depth 1 https://github.com/samwise1776/Rublang.git "$work/Rublang"
cd "$work/Rublang/vscode-extension"
version="$(node -p "require('./package.json').version")"
echo "Packaging Rublang v$version"
npx --yes @vscode/vsce package --no-dependencies --allow-missing-repository
code --install-extension "rublang-$version.vsix" --force
echo "Installed Rublang v$version. Reload VS Code and set language mode to Rublang for .lang files."
