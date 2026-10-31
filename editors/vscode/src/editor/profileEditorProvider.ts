// プロファイル丸ごとの編集画面（ADR 001・015）。cornix-profile: の仮想ドキュメントを開くカスタムエディタ。
// 画面は src/webview/。サーバーへのリクエスト（候補・解釈）は画面に代わってここが中継する。
import * as crypto from 'node:crypto';
import * as vscode from 'vscode';
import type { CornixServer } from '../server/cornixServer';
import type { DeviceAction, DeviceViewState, HostMessage, WebviewMessage } from '../webviewMessages';
import { isDeviceAction } from '../device/deviceTexts';
import type { ProfileSnapshot } from '../protocol';
import { keyboardSpecFor } from '../keyboard';
import { isItemEdit } from './itemEdits';
import { ProfileDocument } from './profileDocument';
import { PROFILE_EDITOR_VIEW_TYPE, profileDirOf } from './profileUri';
import { openProfileFile, profileFileUri } from './profileFiles';
import { vscodePrompts, type ProfilePrompts } from './prompts';
import { textDiagnostics } from './textDiagnostics';
import { relayRequest } from './webviewRelay';

/** 実機への反映の途中の状態と操作（v0.4。device/deviceController.ts がつなぐ） */
export interface DeviceBridge {
  stateOf(dir: string): DeviceViewState;
  /** 状態が変わった dir（undefined はすべて） */
  readonly onDidChangeState: vscode.Event<string | undefined>;
  /** 画面のボタン（節の「反映のプレビュー」とモーダルの「確定」「やめる」など） */
  run(action: DeviceAction, dir: string): void;
}

export class ProfileEditorProvider implements vscode.CustomEditorProvider<ProfileDocument>, vscode.Disposable {
  static readonly viewType = PROFILE_EDITOR_VIEW_TYPE;

  private readonly onDidChangeEmitter = new vscode.EventEmitter<vscode.CustomDocumentEditEvent<ProfileDocument>>();
  readonly onDidChangeCustomDocument = this.onDidChangeEmitter.event;

  private readonly onDidReceiveMessageEmitter = new vscode.EventEmitter<{ document: ProfileDocument; message: WebviewMessage }>();
  /** 編集画面から届いたメッセージ（統合テストが描画を待つため） */
  readonly onDidReceiveWebviewMessage = this.onDidReceiveMessageEmitter.event;

  private readonly onDidChangeDocumentEmitter = new vscode.EventEmitter<ProfileDocument>();
  /** プロファイルを開いた・snapshot や未保存の変更が変わった（実機と比べた状態を「未確認」に戻すかを見るため） */
  readonly onDidChangeDocument = this.onDidChangeDocumentEmitter.event;
  private readonly onDidCloseDocumentEmitter = new vscode.EventEmitter<ProfileDocument>();
  readonly onDidCloseDocument = this.onDidCloseDocumentEmitter.event;
  private device: DeviceBridge | undefined;

  private readonly documents = new Set<ProfileDocument>();
  /** 保存と外での変更で利用者に聞くこと（統合テストが差し替える） */
  prompts: ProfilePrompts = vscodePrompts;
  private readonly disposables: vscode.Disposable[] = [];
  /** テキストで開いたときの波線（protocol.md の 12.7）。保存済みのファイルの検証の結果（snapshot の diagnostics）を出す */
  readonly diagnostics = vscode.languages.createDiagnosticCollection('cornix');
  /** ドキュメントごとの、波線を出したファイルと、そのときの snapshot（同じ snapshot なら出し直さない） */
  private readonly published = new Map<ProfileDocument, { snapshot: ProfileSnapshot; uris: vscode.Uri[] }>();

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly server: CornixServer,
  ) {
    this.disposables.push(
      this.diagnostics,
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

  /** 実機の状態と操作をつなぐ（開いている画面にも今の状態を送る） */
  attachDevice(bridge: DeviceBridge): void {
    this.device = bridge;
  }

  /** 開いているドキュメント（テスト用） */
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
    const env = { server: this.server, workspaceRoot: root, prompts: () => this.prompts };
    const document = await ProfileDocument.open(uri, dir, env, openContext.backupId);
    this.documents.add(document);
    document.onDidEdit((edit) => this.onDidChangeEmitter.fire(edit));
    document.onDidChangeContent(() => {
      this.publishDiagnostics(document);
      this.onDidChangeDocumentEmitter.fire(document);
    });
    document.onDidDispose(() => {
      this.documents.delete(document);
      this.clearDiagnostics(document);
      this.onDidCloseDocumentEmitter.fire(document);
    });
    this.publishDiagnostics(document);
    this.onDidChangeDocumentEmitter.fire(document);
    return document;
  }

  /**
   * snapshot（profile/open・profile/saved・profile/didChange）の diagnostics をファイルごとの波線にする。
   * 未保存の変更の検証の結果（画面だけのもの）は、ファイルの中身と位置が合わないので出さない
   */
  private publishDiagnostics(document: ProfileDocument): void {
    const snapshot = document.snapshot;
    const previous = this.published.get(document);
    if (previous?.snapshot === snapshot) return;
    const uris: vscode.Uri[] = [];
    for (const [file, entries] of textDiagnostics(snapshot)) {
      const uri = profileFileUri(document.dir, file);
      if (!uri) continue;
      uris.push(uri);
      this.diagnostics.set(
        uri,
        entries.map((entry) => {
          const { start, end } = entry.range;
          const severity = entry.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning;
          const diagnostic = new vscode.Diagnostic(new vscode.Range(start.line, start.character, end.line, end.character), entry.message, severity);
          diagnostic.source = 'cornix';
          return diagnostic;
        }),
      );
    }
    const current = new Set(uris.map((uri) => uri.toString()));
    for (const uri of previous?.uris ?? []) if (!current.has(uri.toString())) this.diagnostics.delete(uri);
    this.published.set(document, { snapshot, uris });
  }

  /** プロファイルを閉じたら波線を消す */
  private clearDiagnostics(document: ProfileDocument): void {
    for (const uri of this.published.get(document)?.uris ?? []) this.diagnostics.delete(uri);
    this.published.delete(document);
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

    let disposed = false;
    const post = () => {
      // changes は v0.1 の値の書き換え（set だけ）、pending は未保存の変更の全部を当てる順に（12.3）
      const message: HostMessage = {
        type: 'snapshot',
        snapshot: document.viewSnapshot,
        changes: document.changes.plainSets(),
        pending: document.changes.list(),
      };
      void panel.webview.postMessage(message);
    };
    // キーボード固有の情報（今は常に Cornix）。snapshot より前に送る（Webview はこれを受けてから描く）
    const postKeyboard = () => {
      const message: HostMessage = { type: 'keyboard', spec: keyboardSpecFor(document.dir) };
      void panel.webview.postMessage(message).then(undefined, () => undefined);
    };
    const postDevice = () => {
      if (!this.device) return;
      const message: HostMessage = { type: 'device', state: this.device.stateOf(document.dir) };
      void panel.webview.postMessage(message).then(undefined, () => undefined);
    };
    // 解放されている機能。聞けなければ（古いサーバーなど）何も解放しない
    const postFeatures = () => {
      void this.server
        .request('features/status', {})
        .then(
          (result) => result.unlocked,
          () => [],
        )
        .then((unlocked) => {
          if (disposed) return;
          const message: HostMessage = { type: 'features', unlocked };
          return panel.webview.postMessage(message);
        })
        .then(undefined, () => undefined);
    };
    const subscriptions = [
      document.onDidChangeContent(post),
      ...(this.device ? [this.device.onDidChangeState((dir) => (dir === undefined || dir === document.dir) && postDevice())] : []),
      panel.webview.onDidReceiveMessage((message: WebviewMessage) => {
        this.onDidReceiveMessageEmitter.fire({ document, message });
        switch (message.type) {
          case 'ready':
            postKeyboard();
            post();
            postDevice();
            postFeatures();
            return;
          case 'deviceAction':
            // 画面のボタン。プレビューはコマンドと同じ流れ（保存の促し）を通す
            if (isDeviceAction(message.action)) this.device?.run(message.action, document.dir);
            return;
          case 'change':
          case 'edit':
            // v0.1 の値の書き換えも v0.2 の並びの操作・削除・注記も、同じ未保存の変更の並びに足す（形の違うものは足さない）
            document.applyChange(message.change);
            return;
          case 'itemEdit':
            // 確認のダイアログのあとすぐファイルに書く（結果は snapshot で描き直す。失敗は通知で知らせる）。
            // v0.5 の番号の操作とショートカットの追加は書かずに未保存の変更に積む（結果は snapshot のメッセージの pending）
            if (isItemEdit(message.edit)) void document.applyItemEdit(message.edit);
            return;
          case 'request':
            // サーバーへの中継（RELAYED_METHODS だけ。profileId はそのときのもの（再起動で変わる）を入れる）。
            // 返ってくるまでにパネルを閉じていたら送らない
            void relayRequest(
              message,
              // params の形は Webview の型（WebviewRequestMap）で決まり、サーバーが InvalidParams で確かめる
              (method, params) => this.server.request(method, params as never),
              document.profileId,
            ).then((response) => {
              if (!disposed) void panel.webview.postMessage(response).then(undefined, () => undefined);
            });
            return;
          case 'openFile':
            void openProfileFile(document.dir, message.file, message.range);
            return;
        }
      }),
    ];
    panel.onDidDispose(() => {
      disposed = true;
      subscriptions.forEach((s) => s.dispose());
    });
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
    this.onDidChangeDocumentEmitter.dispose();
    this.onDidCloseDocumentEmitter.dispose();
  }

  private html(webview: vscode.Webview): string {
    const nonce = crypto.randomBytes(16).toString('base64');
    const script = webview.asWebviewUri(vscode.Uri.joinPath(this.extensionUri, 'out', 'webview.js'));
    const csp = [
      "default-src 'none'",
      `img-src ${webview.cspSource} data:`,
      `font-src ${webview.cspSource}`,
      `style-src ${webview.cspSource}`, // 画面は style を CSSOM（element.style）でだけ付ける
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
