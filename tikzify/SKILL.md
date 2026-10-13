---
name: tikzify
description: 手書きの図(紙・ホワイトボードの写真、スキャン、タブレットのメモ)や、別形式の図版(PNG/JPGのスクショ、PDF/SVG/EPS、PowerPoint・Keynote・draw.io・Excalidrawの図、Mermaid/Graphviz、matplotlib・Excelのグラフ、論文の図)をTikZに起こし、自分のLaTeX文書へそのまま\inputで挿入できる形(.tikz + 必要パッケージ + figure環境)で納品する。座標グリッドで読み取り、元画像との重ね合わせで検証し、文書のプリアンブルへ不足分だけ追記する。「この図をTikZにして」「手書きをtikzで清書」「図をLaTeXで描き直して」「この画像をtikzに起こして論文に入れたい」「pgfplotsで再現」などで使う。
---

# tikzify: 図版をTikZに起こして文書へ挿入する

目標は、利用者の文書にそのまま入る図を短時間で作ること。手書きの線をなぞった絵ではなく、描き手が意図した構造(揃った位置、同じ大きさの箱、正しい記号、数式)をTikZで組み直す。

スクリプトはこの SKILL.md と同じフォルダの `scripts/` にある(以下 `$S`)。必要なもの: Python 3.7 以上、ImageMagick 7(`magick`)、poppler(pdftoppm・pdftocairo・pdftotext・pdfinfo)、TeX Live などの TeX 環境。`measure.py` は numpy、EPS 入力は Ghostscript も使う。各スクリプトは `-h` で全オプションの説明を出す。

## 納品物の形(すべての図で共通)

```
figs/<name>.tikz           tikzpicture 環境ひとつだけ。プリアンブルもfigure環境も書かない
figs/<name>.preamble.tex   この図が要求する \usepackage / \usetikzlibrary 行だけ
figs/<name>.pdf .svg .png  build.py が生成(Word・Markdown・スライド用)
figs/<name>.snippet.tex    貼り付け用 figure 環境 + 必要プリアンブル(コメント)
```

`.tikz` の中で完結させる規則:

- スタイルは `\begin{tikzpicture}[box/.style={...}]` のようにローカルに定義する。グローバルな `\tikzset`、`\definecolor` を文書側に要求しない。色はピクチャ内で `\definecolor` / `\colorlet` する(グループ内なので外へ漏れない)。
- スタイル名にTikZの既存キー名(`in` `out` `at` `label` `step` `size` `name` `node` `shape` `color` `fill` `draw` `text` `font` `left` `right` `scale` など)を使わない。`out/.style` や `at/.style` は「requires a value」エラーになる。`blk` `proc` `sink` のように付ける。
- フォント指定はしない(文書のフォントを継承させる)。大きさは `\small` `\footnotesize` などの相対指定まで。`fontspec` や和文フォント指定も書かない。
- 数式は `$...$`。手書きの f(x)、添字、ギリシャ文字、ベクトル矢印は数式として起こす。
- 大きさは座標そのもの(cm)で決まる。後から全体の大きさを変えるときは `[x=0.8cm,y=0.8cm]` を足す(文字の大きさは変わらない)。`scale=` や `\resizebox` は文字まで縮むので避ける。
- `remember picture`、`overlay`、外部画像の読み込みは使わない。

## 手順

### 0. 挿入先を決める

利用者の文書(main.tex など)が分かっていれば先に読む。次を確認する。

- エンジン: `\documentclass`(`ltjsarticle`/`luatexja` → LuaLaTeX、`jsarticle`+`uplatex`/`platex`、`article`+pdfLaTeX、`fontspec` → Lua/XeLaTeX)。`latexmkrc` や `%!TEX program` も見る。和文を含む図をpdfLaTeX文書に入れるなら事前に伝える。
- 既に読み込み済みの tikz ライブラリ・pgfplots の `compat`・図フォルダ(`figs/`, `figures/`)・図番号の付け方と `\label` の命名規則。
- 仕上がり幅: 本文幅の何割に置くか。A4 一段組なら本文幅はおよそ 15〜16 cm、二段組の段幅はおよそ 8.5 cm。決めた幅を `--width-cm` に使う(既定 12)。

文書が無い・不明なら、汎用の standalone 構成で作り、最後にスニペットを渡す。

### 1. 入力の種類で経路を選ぶ

| 入力 | 経路 |
|---|---|
| 写真・スキャン・スクショ (png/jpg/heic) | `grid.py` で座標グリッドを重ねて読む(手順2) |
| SVG / PDF / EPS(ベクター) | `svg2tikz.py` で正確な座標の下書きを作り、意味的に書き直す |
| PDF の中の画像(入試問題・論文に多い。線画は画像、ラベルは文字として上に重なっている) | `svg2tikz.py --crop` で画像の配置とラベル位置を取り、`pdfimages -png` で取り出した画像を grid.py へ(`references/sources.md`) |
| 図の元データ(Mermaid, Graphviz dot, draw.io XML, Excalidraw JSON, matplotlibコード, CSV/Excelの数値) | ソースから構造と数値を直接読む。画像を経由しない |
| PowerPoint / Keynote / Word の図 | PDF に書き出してもらい(またはアプリで書き出し)ベクター経路へ。無理ならスクショで画像経路 |
| 論文PDFの一部 | `svg2tikz.py PDF --page N --crop X,Y,W,H` でその範囲だけをベクターの下書きにする(`references/sources.md`)。ラスター図なら画像経路 |

形式ごとの細かい手順は `references/sources.md`。

### 2. 画像を読む(ラスター入力)

```bash
python3 $S/grid.py photo.jpg --clean --width-cm 12 -o work/photo-grid.png
```

- `--clean`: 写真用。グレースケール化、影・ムラの除去、傾き補正。机などの濃い縁は自動で切り落とす(標準エラーに `autocrop:` と表示。不要なら `--no-autocrop`)。スクショには付けない。
- 出力の `*-grid.png` を Read で見る。赤線が 1 cm、青線が `--step`(既定 0.5 cm)、原点は左下、y は上向き。この座標がそのまま TikZ の座標になる。
- 図番号やキャプションが図の一部と同じ高さにあって `--frame` では除けないときは、`--mask X0,Y0,X1,Y1`(1回目のグリッドの cm)で白く塗る。複数回指定できる。`--frame` や `--mask` を使うと参照画像は `*-framed.png` になり、元の画像は残る。
- 紙の縁の線、余白、関係ないメモが残っていたら、1回目のグリッドで図の範囲を cm で読み、同じ `--width-cm` のまま `--frame X0,Y0,X1,Y1` を付けて再実行する。縮尺は変わらず、範囲の左下が新しい原点になる。表示される `width_cm` が手順5の `--ref-width-cm`。
- `--width-cm` は「(切り取った後の)画像全体の幅」。図が画像いっぱいなら、仕上がり幅をそのまま指定すればよい。`--frame` で余白を落とすと幅はその分小さくなる。仕上がり幅との差が大きければ、`--width-cm` を比例して変えて最初からやり直す(`--frame` の値も同じ比率で変える)。
- 細部は `--zoom x0,y0,x1,y1`(cm)で拡大して読む。ラベルは全体座標のまま。
- `-o` を省くと、グリッド画像と作業用ファイル(`*-src.png`、`*-clean.png`、`*-framed.png`、`*-up.png`、`*-zoomsrc.png`)は元画像の隣の `work/` にできる。grid.py は自分が作っていないファイルを上書きしない。`reference_image` は手順5の `--ref` に使う(`--frame`/`--mask` を使ったときは `*-framed.png`)。
- 解像度の分かるスキャン(300 dpi など)は、`--width-cm` の代わりに `--dpi 300` で原寸の幅になる。

書き始める前に、図の中身を一覧にする(箱・ノード、線と矢印の向き、文字列、数式、色・破線・塗り)。読めない字や曖昧な線は推測で確定させず、一覧に「?」で残して最後に利用者へ確認する。

手書きの解釈規則(どこまで揃えるか、記号の読み方)は `references/handdrawn.md` を読む。要点:

- ほぼ揃っている位置(±0.2 cm 程度)は同じ値に揃える。ほぼ同じ大きさの箱は同じスタイルにする。ほぼ水平・垂直・45°の線はその角度にする。
- 等間隔に見える並びは等間隔にする(`positioning` の `right=of` や `\foreach`)。
- 曲線は端点と通過点を拾い、`to[out=..,in=..]` か `.. controls ..` で近い形にする。
- 描き手の意図ではない揺れ・はみ出し・消し跡は再現しない。

### 3. 図の種類に合う道具を選ぶ

`references/figure-types.md` に種類別の雛形がある。ブロック図・フローチャート(positioning, shapes, arrows.meta)、グラフ理論・状態遷移(automata, graphs)、木(forest)、可換図式(tikz-cd)、回路(circuitikz)、関数・データのグラフ(pgfplots)、幾何(calc, angles, quotes, intersections / tkz-euclide)、物理の図(patterns.meta, decorations)、3D(tikz-3dplot)など。座標をなぞるより、その分野の道具で書いた方が短く正確で、文書の他の図とも揃う。

グラフ(横軸・縦軸のある図)は二通りある。

- 目盛りの数値・データ点・式がある(定量的なグラフ): pgfplots。グリッドで読むのは軸範囲・目盛り・特徴点だけにして、曲線は式またはデータ表で描く。
  - 軸の位置合わせ: measure.py で軸の枠(左下と右上の cm)を測り、`at={(x0cm,y0cm)}, anchor=south west, scale only axis, width=<枠の幅>cm, height=<枠の高さ>cm` を指定する。`south west` は目盛りラベルを含まない枠の角なので、そのまま重ね合わせが合う。
  - 対数軸(`ymode=log`): 座標と式は対数ではなく値そのもの。片対数で直線なら `{10^(a+b*x)}`、`samples=2`。不要な副目盛りは `yminorticks=false`。
  - 化学・物理の直線グラフは傾きが整数や簡単な分数になることが多い。読み取った点から傾きを出し、きりのよい値で一致するならその式を使う。
  - 位置は重ね合わせ(overlay)で判断する。比較画像(compare)は形と全体の印象の確認用。
- 目盛りが無い概形・模式図(「速度が増えて最大になり、振動して落ち着く」など): 素の TikZ で、軸・曲線をグリッド座標に置く。曲線は極値・変曲点・端点で区切り、区間ごとに1本の `.. controls ..` で描く(`references/handdrawn.md` の「曲線」)。

### 4. 書く

`<name>.tikz` と `<name>.preamble.tex` を同じフォルダに書く。`<name>` は内容を表す英小文字とハイフン(`feedback-loop`, `rc-circuit`)。元画像と同じ basename にしない(build.py が生成する `.svg/.png/.pdf` と衝突する。衝突時は build.py が停止する)。

```latex
% <name>.tikz
\begin{tikzpicture}[
    >={Stealth[length=2.2mm]}, line width=0.8pt,
    blk/.style={draw, rounded corners=2mm, minimum width=2.2cm, minimum height=1.2cm},
  ]
  \node[blk] (a) at (2.5,4.6) {入力};
  ...
\end{tikzpicture}
```

```latex
% <name>.preamble.tex
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning,shapes.geometric}
```

画像経路では、ノードの位置などはグリッドで読んだ cm 座標で置く(手順5の重ね合わせがそのまま効く)。構造が規則的な部分は `positioning` やノード間の相対指定に置き換えてよい。

### 5. ビルドして元図と照合する

```bash
python3 $S/build.py figs/<name>.tikz --ref work/photo-clean.png --ref-width-cm 12 --caption "..." --label fig:<name>
```

- 既定エンジンは LuaLaTeX(和文があれば luatexja を自動で読む)。文書に合わせて `--engine pdflatex` などを指定できる。
- 失敗すると、エラー行と `.tikz` の行番号だけが表示される。よくある原因と直し方は `references/pitfalls.md`。
- `_check/<name>-overlay.png` を Read で見る。赤は元図にだけある線(描き漏れ・位置ずれ)、青はTikZにだけある線、黒っぽい部分が一致。手書きの文字と組版の文字は形が違うので、文字は位置だけ見る。
- `_check/<name>-compare.png` は同じ縮尺の左右比較。全体の印象と、欠けている要素を確認する。
- 全体図では細い青線が太い赤線に隠れて小さなずれが見えない。曲線や矢じりの付近は `--zoom X0,Y0,X1,Y1`(グリッド cm)を付けて `_check/<name>-overlay-zoom.png` で確かめる。曲線の角(折れ)は重ね合わせより、仕上がりの `<name>.png` の方がよく見える。
- 意図的に整えた差(揃えた位置、直線化)以外のずれが無くなるまで直す。目安は2〜3回。
- 定規で描かれた図(印刷物、PDF、スクショ)は、目で直すより実測する。`measure.py` で線の位置・円の中心と半径を cm で測り、その値を書く。

```bash
python3 $S/measure.py work/fig-src.png --width-cm 10.96 --row 2.0 --col 2.4 \
  --circle 8.4,3.2,1.9,2.5 [--ink gray]   # 横線 y=2 上の縦線の x、縦線 x=2.4 上の横線の y、円の当てはめ
```

`--circle` の帯(RMIN〜RMAX)は、測りたい円だけが入るよう狭く取る。同心の弧、円の中の文字、近くの直線が帯に入ると引っ張られる(当てはめが怪しいと WARNING が出る)。網点の塗りがある図は `--smooth 3` を付ける。

ほかの計測: `--ellipse X,Y,RMAX`(斜めから見た円)、`--trace X0,X1,Y0,Y1`(曲線をなぞって点列を出す。式の当てはめに使う)、`--bbox X0,Y0,X1,Y1`(ラベルなど文字の塊の位置)、`--mean X0,Y0,X1,Y1`(網点の濃さ → `black!NN`)、`--json`(機械可読出力)。細すぎて除外した線の数も表示される(`--min-width`)。
- 位置合わせの仕組み: 重ね合わせ用にもう一度、境界を (0,0)–(参照の幅, 高さ) cm に固定して描くので、グリッド座標がそのまま参照画像の同じ位置に来る。通常ビルドで表示される大きさは図そのものの外接矩形なので、`--ref-width-cm` より小さいのが普通。
- `--doc path/to/main.tex` を付けると、`<name>.snippet.tex` の `\input` パスが文書から見た相対パスになる(付けないと現在のフォルダ基準)。
- `<name>.standalone.tex` は単体でコンパイルできる版、`_build/` は中間ファイル。どちらも消してよい(消しても再ビルドできる)。

ベクター経路やソース経路では `--ref` に元図をラスター化したもの(`pdftoppm -png -r 150 -singlefile in.pdf ref` や `rsvg-convert -b white in.svg -o ref.png`)を渡し、`--ref-width-cm` に元図の幅を指定する。

### 6. 文書に入れる

```bash
python3 $S/insert.py --doc path/to/main.tex --fig figs/<name>.tikz \
  --marker '%%FIG <name>' --caption "..." --label fig:<name> [--copy-to figs] [--dry-run]
```

- プリアンブルを読み、`<name>.preamble.tex` のうち足りない `\usepackage` と `\usetikzlibrary` だけを `\begin{document}` の直前に追記する(既にあるものは重複させない。pgfplots / circuitikz / tikz-cd があれば tikz は足さない)。それ以外の行(`\pgfplotsset{compat=...}` など)は、文書に同じ種類の設定が無いときだけ追記し、あれば提案として表示する。
- `--marker` の行(例: 本文に書いた `%%FIG feedback-loop`)を figure 環境で置き換える。行番号で入れるなら `--line N`。どちらも無ければ表示だけして書き込まない。
- `--label` を省くと `fig:<name>`。文書に既存の命名規則(`fig:ch2-loop` など)があれば合わせる。
- `--copy-to figs` で図一式を文書の隣の図フォルダへ複製し、そこを参照させる。既にそのフォルダで作業していれば不要(付けても同じファイルはコピーしない)。
- 書き込む前に `main.tex.bak` を作り、差分を表示する。同じ `\label` が既にあれば止まる(`--force` で上書き挿入)。
- Markdown(`.md` / `.qmd`)なら `![caption](figs/<name>.svg){#fig:<name>}` を入れる。

挿入場所が分からないとき、または文書を書き換える了承が無いときは、`--dry-run` の結果か `<name>.snippet.tex` を見せて、利用者に貼ってもらう。

挿入後は文書を一度コンパイルし、図のページを画像で確認する。利用者のフォルダに中間ファイルを散らかさないよう、出力先を分ける。

```bash
latexmk -lualatex -outdir=work/build -interaction=nonstopmode path/to/main.tex   # エンジンは文書に合わせる(-pdf, -pdflatex="uplatex" 等)
pdftoppm -png -r 80 -f <図のページ> -l <図のページ> work/build/main.pdf work/page
```

### 7. 報告

短く次を伝える。

- 作ったファイルと、文書に加えた変更(追記したプリアンブル行、挿入位置)
- 読み取りに自信が無い箇所(判読できない字、矢印の向き、破線か実線か)
- 意図的に整えた点(位置を揃えた、直線にした、記号を数式にした)
- 照合画像(`_check/*-compare.png`)。利用者に画像を見せられる環境なら見せると早い。

## 調整の依頼への対応

「もう少し横長に」「矢印を太く」「色を文書のテーマに合わせて」などは `.tikz` のスタイル部分を直して build.py を再実行するだけでよい。全体の大きさは `x=`/`y=`、線の太さは `line width`、間隔は `node distance` を変える。挿入済みの文書は `\input` しているので、`.tikz` を直せば文書側も変わる(`--copy-to` を使った場合は複製先を直す)。
