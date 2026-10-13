# tikzify

手書きの図や別形式の図版を TikZ に起こし、自分の LaTeX 文書へそのまま `\input` で入れられる形で納品するための [Claude Code](https://docs.claude.com/en/docs/claude-code) 用スキルです。

*A Claude Code skill that turns hand-drawn sketches, scans, screenshots, PDF/SVG/EPS figures and diagram sources into TikZ, checks the result against the original by overlay, and inserts it into your LaTeX (or Markdown) document.*

## できること

- **入力**: 紙やホワイトボードの写真、スキャン、スクリーンショット、PDF / SVG / EPS、PowerPoint・Keynote から書き出した図、draw.io・Excalidraw・Mermaid・Graphviz・matplotlib・Excel のグラフ。
- **読み取り**: 画像に cm 単位の座標グリッドを重ね、その座標をそのまま TikZ の座標として使います。写真は傾き補正・影の除去・机の写り込みの切り取りを行います。ベクター図は座標の下書きを自動で作ります。
- **照合**: 作った図を元画像と同じ縮尺で重ね合わせ(赤 = 描き漏れ、青 = 余分)、拡大表示や画素からの実測(線の位置、円・楕円の当てはめ、曲線のなぞり、塗りの濃さ)で誤差を詰めます。
- **納品**: `.tikz`(tikzpicture だけ)と `.preamble.tex`(必要なパッケージだけ)、PDF / SVG / PNG、貼り付け用の figure 環境。
- **挿入**: 文書のプリアンブルに足りないパッケージだけを追記し、本文の目印 `%%FIG 名前` を figure 環境に置き換えます。書き込む前にバックアップを作り、差分を表示します。

## 必要なもの

- Python 3.7 以上(`measure.py` は numpy を使います)
- ImageMagick 7(`magick` コマンド)
- poppler(`pdftoppm`, `pdftocairo`, `pdftotext`, `pdfinfo`)
- TeX Live などの TeX 環境(既定は LuaLaTeX。和文は luatexja)
- EPS を読むときは Ghostscript

## 導入

このフォルダを Claude Code のスキルフォルダに置きます。

```sh
cp -R tikzify ~/.claude/skills/
```

Claude Code で「この図を TikZ にして」「手書きを tikz で清書して論文に入れたい」のように頼むと使われます。手順の詳細は [`SKILL.md`](./SKILL.md) にあります。

## 構成

```
SKILL.md            手順(入力の種類ごとの経路、書き方の規則、照合、挿入)
references/         図の種類と道具、手書き図の読み方、入力形式ごとの取り込み、よくあるエラー
templates/          図の種類別の雛形 12 種(フローチャート、状態遷移、木、可換図式、回路、
                    pgfplots、棒グラフ、幾何、力学、数直線、ベン図、ソレノイド)
scripts/grid.py     画像に cm 座標グリッドを重ねる(写真の前処理、範囲指定、マスク、拡大)
scripts/svg2tikz.py SVG / PDF / EPS から座標の下書き TikZ を作る(PDF の文字は位置付きで抽出)
scripts/build.py    図をコンパイルして PDF / SVG / PNG・貼り付け用の断片・元画像との照合画像を作る
scripts/measure.py  元画像を画素から実測する(線、円、楕円、曲線、文字の範囲、塗りの濃さ)
scripts/insert.py   文書のプリアンブルへの追記と figure 環境の挿入(LaTeX / Markdown)
```

各スクリプトは `-h` で全オプションを表示します。

## 安全性について

- 外部コマンドはすべて引数リストで呼び出し、シェルは使いません。
- PDF や SVG から取り出した文字は TeX の特殊文字をすべてエスケープしてから出力するため、ファイルに仕込まれた TeX コードは実行されません。
- 各スクリプトは自分が生成していないファイルを上書きしません。`insert.py` はすべての確認が通ってから書き込み、バックアップを残します。

## ライセンス

[MIT License](./LICENSE.md) © 2026 Kosei Kawaguchi

図を起こす対象の著作権は元の著作者にあります。他人の図版を TikZ に起こして公開する場合は、引用の要件や利用許諾を確認してください。
