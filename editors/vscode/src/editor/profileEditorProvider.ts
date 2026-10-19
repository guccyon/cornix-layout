// プロファイル丸ごとの編集画面（ADR 001・015）。cornix-profile: の仮想ドキュメントを開くカスタムエディタ。
// 画面は src/webview/。サーバーへのリクエスト（候補・解釈）は画面に代わってここが中継する。
import * as crypto from 'node:crypto';
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { CornixServer } from '../server/cornixServer';
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { ProfileDocument } from './profileDocument';
import { profileDirOf } from './profileUri';
import type { Range } from '../protocol';

export class ProfileEditorProvider implements vscode.CustomEditorProvider<ProfileDocument>, vscode.Disposable {
  static readonly viewType = 'cornix.profileEditor';

  private readonly onDidChangeEmitter = new vscode.EventEmitter<vscode.CustomDocumentEditEvent<ProfileDocument>>();
  readonly onDidChangeCustomDocument = this.onDidChangeEmitter.event;

  private readonly onDidReceiveMessageEmitter = new vscode.EventEmitter<{ document: ProfileDocument; message: WebviewMessage }>();
  /** 編集画面から届いたメッセージ（統合テストが描画を待つため） */
  readonly onDidReceiveWebviewMessage = this.onDidReceiveMessageEmitter.event;

  private readonly documents = new Set<ProfileDocument>();
  private readonly disposables: vscode.Disposable[] = [];

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly server: CornixServer,
  ) {
    this.disposables.push(
      server.onNotification('profile/didChange', (params) => {
        for (const document of this.documents) document.handleExternalChange(params);
      }),
    );
  }

  static register(context: vscode.ExtensionContext, server: CornixServer): ProfileEditorProvider {
    const provider = new ProfileEditorProvider(context.extensionUri, server);
    context.subscriptions.push(
      provider,
      vscode.window.registerCustomEditorProvider(ProfileEditorProvider.viewType, provider, {
        supportsMultipleEditorsPerDocument: false,
      }),
    );
    return provider;
  }

  /** 開いているドキュメント（テストと、段 3 の保存の作業から使う） */
  get openDocuments(): readonly ProfileDocument[] {
    return [...this.documents];
  }

  async openCustomDocument(
    uri: vscode.Uri,
    openContext: vscode.CustomDocumentOpenContext,
    _token: vscode.CancellationToken,
  ): Promise<ProfileDocument> {
    const dir = profileDirOf(uri);
    const root = vscode.workspace.workspaceFolders?.[0]?.uri;
    if (!dir || !root) throw new Error(`Cornix のプロファイルとして開けません: ${uri.toString()}`);
    const document = await ProfileDocument.open(uri, dir, this.server, root, openContext.backupId);
    this.documents.add(document);
    document.onDidEdit((edit) => this.onDidChangeEmitter.fire(edit));
    document.onDidDispose(() => this.documents.delete(document));
    return document;
  }

  async resolveCustomEditor(
    document: ProfileDocument,
    panel: vscode.WebviewPanel,
    _token: vscode.CancellationToken,
  ): Promise<void> {
    const outUri = vscode.Uri.joinPath(this.extensionUri, 'out');
    const mediaUri = vscode.Uri.joinPath(this.extensionUri, 'media');
    panel.webview.options = { enableScripts: true, localResourceRoots: [outUri, mediaUri] };
    panel.webview.html = this.html(panel.webview);

    const post = () => {
      const message: HostMessage = { type: 'snapshot', snapshot: document.snapshot, changes: document.changes.list() };
      void panel.webview.postMessage(message);
    };
    const subscriptions = [
      document.onDidChangeContent(post),
      panel.webview.onDidReceiveMessage((message: WebviewMessage) => {
        this.onDidReceiveMessageEmitter.fire({ document, message });
        switch (message.type) {
          case 'ready':
            post();
            return;
          case 'change':
            document.applyChange(message.change);
            return;
          case 'request':
            // サーバーへの中継。profileId はそのときのもの（再起動で変わる）を入れる
            this.server.request(message.method, { ...message.params, profileId: document.profileId }).then(
              (result) => void panel.webview.postMessage({ type: 'response', id: message.id, result } satisfies HostMessage),
              (error: unknown) =>
                void panel.webview.postMessage({
                  type: 'response',
                  id: message.id,
                  error: error instanceof Error ? error.message : String(error),
                } satisfies HostMessage),
            );
            return;
          case 'openFile':
            void openProfileFile(document, message.file, message.range);
            return;
        }
      }),
    ];
    panel.onDidDispose(() => subscriptions.forEach((s) => s.dispose()));
  }

  saveCustomDocument(document: ProfileDocument, cancellation: vscode.CancellationToken): Thenable<void> {
    return document.save(cancellation);
  }

  async saveCustomDocumentAs(): Promise<void> {
    throw new Error('Cornix のプロファイルは別名で保存できません。');
  }

  revertCustomDocument(document: ProfileDocument): Thenable<void> {
    return document.revert();
  }

  backupCustomDocument(
    document: ProfileDocument,
    context: vscode.CustomDocumentBackupContext,
  ): Thenable<vscode.CustomDocumentBackup> {
    return document.backup(context.destination);
  }

  dispose(): void {
    for (const disposable of this.disposables) disposable.dispose();
    this.onDidChangeEmitter.dispose();
    this.onDidReceiveMessageEmitter.dispose();
  }

  private html(webview: vscode.Webview): string {
    const nonce = crypto.randomBytes(16).toString('base64');
    const script = webview.asWebviewUri(vscode.Uri.joinPath(this.extensionUri, 'out', 'webview.js'));
    const csp = [
      "default-src 'none'",
      `img-src ${webview.cspSource} data:`,
      `font-src ${webview.cspSource}`,
      `style-src ${webview.cspSource} 'unsafe-inline'`,
      `script-src 'nonce-${nonce}'`,
    ].join('; ');
    return `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="${csp}">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cornix</title>
</head>
<body>
  <div id="app"></div>
  <script nonce="${nonce}" src="${script.toString()}"></script>
</body>
</html>`;
  }
}

/** 設定ディレクトリのファイルをテキストで開く（構造の問題の一覧の「ファイルを開く」） */
async function openProfileFile(document: ProfileDocument, file: string, range: Range | undefined): Promise<void> {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri;
  // dir はワークスペースからの相対パス（外なら絶対パス。protocol.md の 2.）
  const base = path.isAbsolute(document.dir) ? vscode.Uri.file(document.dir) : root && vscode.Uri.joinPath(root, document.dir);
  if (!base) return;
  const uri = vscode.Uri.joinPath(base, file);
  const selection = range
    ? new vscode.Range(range.start.line, range.start.character, range.end.line, range.end.character)
    : undefined;
  await vscode.window.showTextDocument(uri, { preview: false, ...(selection ? { selection } : {}) });
}
