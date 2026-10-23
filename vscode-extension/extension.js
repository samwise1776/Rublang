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
