#!/usr/bin/env bash
set -euo pipefail
REPO="https://github.com/samwise1776/Rublang.git"
if ! command -v git >/dev/null || ! command -v npm >/dev/null; then
  echo "Install git, nodejs and npm first."
  exit 1
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone "$REPO" "$WORK/Rublang"
cd "$WORK/Rublang"
mkdir -p vscode-extension/syntaxes
cat > vscode-extension/package.json <<'EOF'
{
  "name": "rublang",
  "displayName": "Rublang",
  "description": "Syntax highlighting and Run File command for the Rublang programming language.",
  "version": "1.0.0",
  "publisher": "samwise1776",
  "license": "MIT",
  "engines": { "vscode": "^1.85.0" },
  "main": "./extension.js",
  "activationEvents": ["onLanguage:rublang", "onCommand:rublang.runFile"],
  "categories": ["Programming Languages"],
  "contributes": {
    "languages": [{
      "id": "rublang",
      "aliases": ["Rublang", "rublang"],
      "extensions": [".lang"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "rublang",
      "scopeName": "source.rublang",
      "path": "./syntaxes/rublang.tmLanguage.json"
    }],
    "commands": [{
      "command": "rublang.runFile",
      "title": "Rublang: Run Current File"
    }],
    "menus": {
      "editor/title": [{
        "command": "rublang.runFile",
        "when": "resourceLangId == rublang",
        "group": "navigation"
      }]
    },
    "configuration": {
      "title": "Rublang",
      "properties": {
        "rublang.interpreterPath": {
          "type": "string",
          "default": "app.rb",
          "description": "Path to the Rublang interpreter (app.rb); relative paths resolve from the workspace."
        }
      }
    }
  }
}
EOF
cat > vscode-extension/language-configuration.json <<'EOF'
{
  "comments": { "lineComment": "---" },
  "brackets": [["{", "}"], ["(", ")"], ["[", "]"]],
  "autoClosingPairs": [
    {"open": "{", "close": "}"},
    {"open": "(", "close": ")"},
    {"open": "[", "close": "]"},
    {"open": "\"", "close": "\""}
  ],
  "surroundingPairs": [["{", "}"], ["(", ")"], ["[", "]"], ["\"", "\""]]
}
EOF
cat > vscode-extension/syntaxes/rublang.tmLanguage.json <<'EOF'
{
  "name": "Rublang",
  "scopeName": "source.rublang",
  "patterns": [
    {"name": "comment.line.rublang", "match": "---.*$"},
    {"name": "string.quoted.double.rublang", "begin": "\"", "end": "\"", "patterns": [{"match": "\\\\.", "name": "constant.character.escape.rublang"}]},
    {"name": "keyword.control.rublang", "match": "\\b(?:if|else|elsif|end|while|for|times|return|break|next|begin|rescue|import|ext|extension|keyword|class|def|namespace)\\b"},
    {"name": "storage.type.rublang", "match": "\\b(?:vs|vi|vf|vb|vl|vll|va)\\b"},
    {"name": "support.function.rublang", "match": "\\b(?:stdout::c|stdout::print|stdin::c|sound::play|File\\.(?:write|append))\\b"},
    {"name": "constant.numeric.rublang", "match": "\\b\\d+(?:\\.\\d+)?\\b"},
    {"name": "constant.language.boolean.rublang", "match": "\\b(?:true|false|nil)\\b"}
  ]
}
EOF
cat > vscode-extension/extension.js <<'EOF'
const vscode = require('vscode');
const path = require('path');
function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand('rublang.runFile', () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return;
    if (editor.document.isUntitled) {
      vscode.window.showErrorMessage('Save the Rublang file first.');
      return;
    }
    editor.document.save().then(() => {
      const folder = vscode.workspace.getWorkspaceFolder(editor.document.uri);
      const cwd = folder ? folder.uri.fsPath : path.dirname(editor.document.uri.fsPath);
      const config = vscode.workspace.getConfiguration('rublang');
      let interpreter = config.get('interpreterPath', 'app.rb');
      if (!path.isAbsolute(interpreter)) interpreter = path.join(cwd, interpreter);
      const terminal = vscode.window.createTerminal({name: 'Rublang', cwd});
      terminal.show();
      const quote = s => "'" + s.replace(/'/g, "'\\''") + "'";
      terminal.sendText('ruby ' + quote(interpreter) + ' ' + quote(editor.document.uri.fsPath));
    });
  }));
}
function deactivate() {}
module.exports = {activate, deactivate};
EOF
cat > vscode-extension/README.md <<'EOF'
# Rublang for VS Code

Syntax highlighting for `.lang` files, bracket pairing and **Rublang: Run Current File**.

To run code, open your Rublang project containing `app.rb`, then use the Command Palette and select **Rublang: Run Current File**. Set `rublang.interpreterPath` if the interpreter is elsewhere.
EOF
git add vscode-extension
if ! git diff --cached --quiet; then
  git -c user.name="samwise1776" -c user.email="samwise1776@users.noreply.github.com" commit -m "Add Rublang VS Code extension"
  if ! git push origin HEAD:master; then
    echo "Git push failed. You may need to authenticate with gh auth login."
  fi
fi
cd vscode-extension
if ! command -v code >/dev/null; then
  echo "VS Code CLI not found. Extension source is at $REPO in vscode-extension."
  exit 0
fi
npx --yes @vscode/vsce package --no-dependencies --allow-missing-repository
code --install-extension rublang-1.0.0.vsix
echo "Rublang installed in local VS Code. Public Marketplace listing requires publishing separately."
