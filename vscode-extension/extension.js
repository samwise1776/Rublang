const vscode = require('vscode');
const path = require('path');
const styles = {
  external: vscode.window.createTextEditorDecorationType({ color: '#00C853' }),
  internal: vscode.window.createTextEditorDecorationType({ color: '#FFD600' }),
  stdoutArgs: vscode.window.createTextEditorDecorationType({ color: '#FF00FF' }),
  stdoutBare: vscode.window.createTextEditorDecorationType({ color: '#00C853' }),
  call: vscode.window.createTextEditorDecorationType({ color: '#AA55FF' }),
  def: vscode.window.createTextEditorDecorationType({ color: 'rgb(100, 100, 21)' })
};
const internal = new Set(['stdout', 'stdin', 'sound', 'File', 'time', 'gui', 'Math', 'math']);
function colorize(editor) {
  if (!editor || editor.document.languageId !== 'rublang') return;
  const doc = editor.document, text = doc.getText();
  const ranges = Object.fromEntries(Object.keys(styles).map(k => [k, []]));
  const add = (k, s, e) => ranges[k].push(new vscode.Range(doc.positionAt(s), doc.positionAt(e)));
  const hidden = [...text.matchAll(/---[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g)].map(m => [m.index, m.index + m[0].length]);
  const skip = i => hidden.some(([a, b]) => i >= a && i < b);
  for (const m of text.matchAll(/\b[A-Za-z_]\w*(?=\s*\()/g)) if (!skip(m.index)) add('call', m.index, m.index + m[0].length);
  for (const m of text.matchAll(/\b([A-Za-z_]\w*)::([A-Za-z_]\w*)/g)) {
    if (!skip(m.index)) add(internal.has(m[1]) ? 'internal' : 'external', m.index, m.index + m[0].length);
  }
  for (const m of text.matchAll(/\bstdout::[A-Za-z_]\w*/g)) {
    if (skip(m.index)) continue;
    const rest = text.slice(m.index + m[0].length).split('\n')[0].trim();
    add(/^<<\s*\S/.test(rest) ? 'stdoutArgs' : 'stdoutBare', m.index, m.index + m[0].length);
  }
  for (const m of text.matchAll(/\bdef\b/g)) if (!skip(m.index)) add('def', m.index, m.index + 3);
  for (const [name, style] of Object.entries(styles)) editor.setDecorations(style, ranges[name]);
}
function activate(context) {
  context.subscriptions.push(...Object.values(styles));
  const update = () => colorize(vscode.window.activeTextEditor);
  context.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(update));
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => {
    if (e.document === vscode.window.activeTextEditor?.document) update();
  }));
  update();
  const words = [
    ['stdout::c', 'stdout::c << "$1"'],
    ['stdout::print', 'stdout::print << "$1"'],
    ['stdin::c', 'stdin::c << "$1"'],
    ['sound::play', 'sound::play($1, $2)'],
    ['File.write', 'File.write "$1", "$2"'],
    ['File.append', 'File.append "$1", "$2"'],
    ['def', 'def $1($2) {\n\t$0\n}'],
    ['times', 'times($1) as count {\n\t$0\n}'],
    ['if', 'if $1 {\n\t$0\n}'],
    ['import', 'import $1'],
    ['vs', 'vs $1 = "$2"'], ['vi', 'vi $1 = $2'],
    ['vf', 'vf $1 = $2'], ['vb', 'vb $1 = true'],
    ['vl', 'vl $1 = $2'], ['vll', 'vll $1 = $2'],
    ['va', 'va $1 = []']
  ];
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider('rublang', {
    provideCompletionItems(doc) {
      const result = words.map(([name, snippet]) => {
        const item = new vscode.CompletionItem(name, vscode.CompletionItemKind.Snippet);
        item.insertText = new vscode.SnippetString(snippet);
        item.detail = 'Rublang snippet';
        item.sortText = '0_' + name;
        return item;
      });
      const defined = new Set([...doc.getText().matchAll(/\b(?:def|vs|vi|vf|vb|vl|vll|va)\s+([A-Za-z_]\w*)/g)].map(m => m[1]));
      for (const name of defined) result.push(new vscode.CompletionItem(name, vscode.CompletionItemKind.Variable));
      return result;
    }
  }, ':', '.', '<'));
  context.subscriptions.push(vscode.commands.registerCommand('rublang.runFile', () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return;
    if (editor.document.isUntitled) return vscode.window.showErrorMessage('Save the Rublang file first.');
    editor.document.save().then(() => {
      const folder = vscode.workspace.getWorkspaceFolder(editor.document.uri);
      const cwd = folder ? folder.uri.fsPath : path.dirname(editor.document.uri.fsPath);
      let interpreter = vscode.workspace.getConfiguration('rublang').get('interpreterPath', 'app.rb');
      if (!path.isAbsolute(interpreter)) interpreter = path.join(cwd, interpreter);
      const quote = s => "'" + s.replace(/'/g, "'\\''") + "'";
      const terminal = vscode.window.createTerminal({ name: 'Rublang', cwd });
      terminal.show();
      terminal.sendText('ruby ' + quote(interpreter) + ' ' + quote(editor.document.uri.fsPath));
    });
  }));
}
function deactivate() {}
module.exports = { activate, deactivate };
