# ABEMA — Omarchy バーウィジェット

[ABEMA](https://abema.tv/) の全チャンネルで「いま何が放送中か」を 1 枚のパネルにまとめます。
番組をクリックするとそのまま ABEMA で開きます。チャンネル名（列の頭）をクリックすると、そのチャンネルの番組表 — このあと流れるものが 1 行ずつ、あらすじ付き — が出るので、そこから選べます。

- abema.tv/timetable と同じ形のグリッド。チャンネルが横に並び、時間が縦に流れます
- あるいは新聞のテレビ欄のように、開始時刻ごとにまとめた縦リスト
- チャンネルロゴ・終了時刻・残り時間、そして「いま」を示す横線
- チャンネル名を押すと、そのチャンネルの番組表（およそ 1 日分）
- ステータスバーには ABEMA のマーク（バーの前景色に染めて表示）
- チャンネルを選ぶと、ウィンドウは増えず 1 枚のまま入れ替わります
- チャンネル名／番組名でフィルタ
- パネルを開いている間だけ 1 分ごとに更新（閉じている間は何も取りにいきません）

## レイアウト

`grid`（既定）は abema.tv/timetable と同じ形です。チャンネルごとに 1 列、
時間が縦に流れ、左に 1 時間ごとの目盛り、「いま」の位置に明るい横線が入ります。
4 時間の枠からはみ出す番組は切られ、前から続いているものには `↑` が付きます。
残りのチャンネルは横スクロール（または `h` / `l`）で。

`listing` は新聞のテレビ欄です。開始時刻ごとに行をまとめ、各行に進捗バーが付きます。
前日以前に始まった枠には `-1d` の印が付くので、21:40 が今夜とは読めません。

どちらのレイアウトでも、番組を押せば ABEMA が開き、チャンネル名やロゴを押せば
そのチャンネルだけの番組表（1 日分ほど）が 1 行 1 番組で出ます。放送中の番組は
ライブのチャンネルへ、まだ始まっていない番組はその番組のページへ飛びます。

## インストール

```bash
omarchy plugin add https://github.com/polidog/omarchy-abematv.git --enable
```

`--enable` を付けるとバーに追加して置き場所（左/中央/右）を聞かれます。あとから
入れ替えるなら次のとおり。

```bash
omarchy plugin update io.github.polidog.abematv   # 更新
omarchy plugin remove io.github.polidog.abematv   # 削除
omarchy bar move io.github.polidog.abematv --section right
```

プラグインは `omarchy-shell` の中で素のまま動くので、入れる前にコードを読んでく
ださい。QML 1 枚・JS 1 枚・シェルスクリプト 1 本・Python 1 本だけです。

### 手元で触る場合

```bash
git clone https://github.com/polidog/omarchy-abematv
cd omarchy-abematv
tools/install-local
```

## 設定

| キー | 既定値 | 内容 |
|------|--------|------|
| `layout` | `grid` | `grid` は番組表グリッド、`listing` は新聞のテレビ欄風リスト。 |
| `openWith` | `webapp` | `webapp` は専用ウィンドウ、`browser` は既定ブラウザのタブで開きます。 |
| `showFilter` | `true` | パネルにフィルタ欄を出すか。 |

## キー操作

`h` / `l`（または `j` / `k`）移動 · `Enter` チャンネルを開く → もう一度でカーソル上の番組を視聴 · `/` フィルタ · `r` 更新 · `Esc` 戻る → もう一度で閉じる。
バーのボタンを右クリックすると、パネルを開かずに更新だけします。

## できないこと

- **自前での再生も、パネル内への映像表示もしません。** ABEMA のライブ HLS は独自方式
  （`abematv-license://`）で暗号化されていて、復号できるのは本家プレイヤーだけです。
  シェル側で描画できるものが無いので、このウィジェットは番組表とランチャーに徹します。
  そのかわりプレイヤーのウィンドウは 1 枚に保ちます。チャンネルを選ぶと、すでに開いている
  ABEMA の web app ウィンドウを閉じてから新しいものを開くので、ウィンドウは積み上がりません。
  出る場所を固定したいときは `class:^(chrome-abema\.tv)` に Hyprland の window rule を。
- **番組表グリッド／テレビ欄に「このあと」は出ません。** 1 分ごとに叩いている
  `broadcast/slots` は日時指定を受け付けず、いま放送中の枠だけを返します。全体の
  番組表はトークンの向こう側なので、チャンネルを 1 つ開いたときだけ取りにいきます。
- **無料枠のみ。** プレミアム対象の番組は、プレイヤー側でログインを求められます。

番組表は ABEMA の公開エンドポイント（`api.abema.io/v1/channels` と
`/v1/broadcast/slots`、どちらもトークン不要）から取得しています。チャンネル 1 つ分の
番組表は `/v1/timetable/dataSet` から取っていて、こちらはトークンが要ります。
`bin/abematv-listing` が ABEMA のクライアントと同じ匿名の端末トークンを作り
（アカウントもログインも不要で、再生や DRM には一切触りません）、番組表ごと
`~/.cache/omarchy-abematv` にキャッシュします。非公式プラグインであり、
ABEMA / サイバーエージェントとは関係ありません。

## 依存

どれも Omarchy に最初から入っています。`python3`（番組表ヘルパー）、`curl`（1 分ごとに
叩く 2 つのエンドポイント）、`jq` と `hyprctl`（置き換える ABEMA ウィンドウを探す）、
`omarchy-launch-webapp` / `omarchy-launch-browser`（プレイヤーを開く）。書き込むのは
`~/.cache/omarchy-abematv` の自分のキャッシュだけです。

## 開発

```bash
tools/test-model               # シェルなしでデータ処理だけをテスト
tools/test-listing             # 番組表ヘルパーの接続先・サイズ・キャッシュの制限
tools/install-local            # ~/.config/omarchy/plugins へ同期
tools/install-local --restart  # QML を変えたときはシェル再起動が要る
```

MIT.
