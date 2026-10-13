# 入力形式ごとの取り込み方

基本方針: 元データ(ソース・数値・ベクター)があれば画像より優先する。座標や値が正確に取れるからである。

## ベクター形式

### SVG

```bash
python3 $S/svg2tikz.py figure.svg --width-cm 12 -o work/figure-raw.tikz
```

- path(直線・ベジエ・円弧)、rect(角丸含む)、circle、ellipse、line、polyline、polygon、text、use、入れ子の transform、線幅、破線、塗り、不透明度を変換する。グラデーション・クリップ・マスク・フィルタは捨てる。
- 出力は「生の下書き」。全部 `\path[draw=..]` の羅列なので、そのまま納品しない。下書きの座標を見ながら、ノード・スタイル・名前付き座標に書き直す(箱は `\node[blk]`、矢印は `\draw[->]`、同色の要素は同じスタイル)。
- 文字がアウトライン化された SVG(フォントが path になっている)は、文字の形の path が大量に出る。その部分は捨て、見た目から文字を読んで `\node` で書く。
- 照合用の参照画像: `rsvg-convert -b white -w 1600 figure.svg -o work/ref.png`。`--ref-width-cm` は svg2tikz が表示した幅。

### PDF(論文の図、PowerPoint・Keynote・Illustrator・matplotlib の書き出し)

```bash
# 1) ページを 72 dpi で画像にすると 1 px = 1 pt になる。図の範囲(左上 X,Y と幅 W,高さ H)を読む
pdftoppm -png -r 72 -f 3 -l 3 -singlefile paper.pdf work/page
# 2) その範囲だけを下書きにする(範囲の左下が TikZ の原点になる)
python3 $S/svg2tikz.py paper.pdf --page 3 --crop 100,200,300,220 -o work/fig-raw.tikz
# 3) 照合用の参照画像(同じ範囲)。-x -y -W -H は 200 dpi のピクセル = pt × 200/72
pdftoppm -png -r 200 -f 3 -l 3 -x 278 -y 556 -W 833 -H 611 -singlefile paper.pdf work/ref
```

- `--crop` の範囲に一部でもかかる要素は残る。はみ出した要素は書き直すときに整理する。
- 文字は `pdftotext -bbox` で位置付きの `\node` として取り出す(グリフの path は出さない)。数式は崩れて出るので、見た目から数式を書き直す。
- 図がラスター画像として埋め込まれている PDF(`pdfimages -list` で確認)はベクター情報が無い。画像経路(grid.py)へ。

### PDF に埋め込まれた画像の図(線画が画像、ラベルが文字)

入試問題や教科書の PDF に多い形。`pdfimages -list` で画像があるページを確かめる。

```bash
# 1) 図の範囲を --crop して下書きを取る。画像の配置がコメントで、ラベルが \node で出る
python3 $S/svg2tikz.py doc.pdf --page 3 --crop 80,200,360,200 -o work/fig-raw.tikz
#    % raster image 1200x800 px placed at (1.20,0.40) -- (11.36,7.17) (cm) ...
# 2) 画像を原寸で取り出し、配置の幅(この例では 11.36-1.20 = 10.16 cm)でグリッドを作る
pdfimages -f 3 -l 3 -png doc.pdf work/fig
python3 $S/grid.py work/fig-000.png --width-cm 10.16 -o work/fig-grid.png
```

- ラベルの座標は下書きの座標から画像の左下 (1.20,0.40) を引けば、グリッド座標になる。画像の外にあるラベル(負の座標)もそのまま使う。
- 線画は grid.py と measure.py で読む。ベクターではないので svg2tikz の線は出ない。
- 文字コードが独自の PDF では、数字や記号が `!` `"` などに化ける(独自のフォント符号化をした PDF で「図!―!」のようになる例がある)。和文と英字は正しく取れることが多い。化けた文字は画面で読んで直す。

### EPS / PS

svg2tikz.py にそのまま渡す(ghostscript で PDF に変換してから処理する)。

## アプリの図

| 元 | 取り出し方 |
|---|---|
| PowerPoint (.pptx) | 図形を選んで「図として保存」→ PDF / SVG、またはスライドを PDF に書き出す。利用者に書き出してもらうのが確実 |
| Keynote | ファイル → 書き出す → PDF |
| Word の図形 | 図をコピーして PowerPoint に貼り、PDF で書き出す。またはスクショ |
| draw.io / diagrams.net (.drawio, .xml) | XML の `mxCell` に `value`(文字)、`style`(形・色)、`mxGeometry x y width height`(px、左上原点、y 下向き)がある。px × 0.0265 で cm にし、y を反転する。エッジは `source` / `target` のIDでつなぐ。圧縮されている場合は「ファイル → 書き出し → XML(圧縮しない)」 |
| Excalidraw (.excalidraw JSON) | `elements[]` の `type`(rectangle, ellipse, arrow, text)、`x y width height`、`points`、`text`。手書き風の揺れ(roughness)は再現しない |
| GeoGebra | 「グラフィックスをエクスポート → PGF/TikZ」が使える。出力は冗長なので、点・線を整理して書き直す |
| Inkscape | SVG で保存して svg2tikz.py へ(Inkscape 用の拡張機能 svg2tikz を使ってもよい) |

## 図のソースコード

画像化せず、ソースの構造をそのまま TikZ に写す。

| 元 | 対応 |
|---|---|
| Mermaid `flowchart` / `graph` | ノード・辺を `flowchart` 雛形へ。`TD` は下方向、`LR` は右方向の `positioning`。サブグラフは `fit` で囲む |
| Mermaid `stateDiagram` | `automaton` 雛形 |
| Mermaid `sequenceDiagram` | `pgf-umlsd` か、縦線と水平矢印の素朴な TikZ |
| Graphviz dot | ノード・辺・ラベルを `automaton` / `flowchart` 雛形へ。配置を自動にしたいなら LuaLaTeX の `graphdrawing`(`\usetikzlibrary{graphs,graphdrawing}` `\usegdlibrary{layered}`)。文書が LuaLaTeX でない場合は使えない |
| matplotlib / seaborn のコード | 描画データ(配列・式)と軸設定を pgfplots に写す。`plt.plot(x, y)` → `\addplot table`、`xlim` → `xmin/xmax`、`xlabel` → `xlabel`。データが多い(数千点以上)ときは CSV を図と同じフォルダに置き `\addplot table[col sep=comma]{data.csv}`(この場合は .csv も納品物に含める) |
| Excel / CSV のグラフ | 数値を読み、`bars` / `plot` 雛形。系列名を凡例に |
| gnuplot | 同上。`set xrange` → `xmin/xmax` |

## 画像(ラスター)

手書き・ホワイトボード・スクショ・スキャン・論文のラスター図。grid.py の経路(SKILL.md 手順2)。

- スクショの図は `--clean` を付けない(色が落ちる)。
- 背景が透明な PNG は白で埋めて処理する(grid.py が自動で行う)。
- 縮小された小さな画像(幅 500px 未満など)は grid.py が拡大して表示する。細部が潰れていれば、元の大きな画像が無いか利用者に聞く。
