# よくあるエラーと落とし穴

## コンパイルエラー

| メッセージ | 原因 | 直し方 |
|---|---|---|
| `Unknown arrow tip kind 'Stealth'` | `arrows.meta` 未読込 | `.preamble.tex` に `\usetikzlibrary{arrows.meta}` |
| `The key '/tikz/out' requires a value` など | 自作スタイル名が既存キーと衝突(`in` `out` `label` `step` `size` `shape` `left` `right` `color` `scale` `node`) | スタイル名を変える(`sink`、`lbl`) |
| `I do not know the key '/tikz/diamond'` / `ellipse` / `trapezium` | `shapes.geometric` 未読込 | ライブラリを足す。`rounded rectangle` は `shapes.misc` |
| `... below=of ...` が効かない、`of` がエラー | `positioning` 未読込 | ライブラリを足す |
| `File ended while scanning use of \tikz@quote@@parser` | `quotes` のラベルにカンマ | `"{$a,b$}"` と波括弧で包む |
| `Package pgfplots Warning: running in backwards compatibility mode` | `compat` 未指定 | `\pgfplotsset{compat=1.18}` を preamble に(文書側に既にあればその値に合わせる) |
| `Dimension too large` | 巨大な座標、`tan(90)`、pgfplots の極端な値 | 座標の桁を確認。pgfplots は `restrict y to domain` |
| `Missing character: There is no あ in font` | pdfLaTeX で和文 | 文書側を LuaLaTeX(luatexja)/ upLaTeX にするか、図の和文を英語にする。build.py は和文を検出すると luatexja を自動で読む |
| `Single ampersand used with wrong catcode` | `\matrix` が他のマクロの引数の中にある | `ampersand replacement=\&` を付け、`&` を `\&` にする |
| `Undefined control sequence \pic` / `angle` | `angles` 未読込 | ライブラリを足す。ラベルを付けるなら `quotes` も |
| babel の `french` / `turkish` 等で `"` `:` `!` が壊れる | babel の shorthand | 文書側に `\usetikzlibrary{babel}` |
| `Dimension too large`(`decorations.markings` を使った行) | 短い線や小さな円弧に markings で矢じりを付けた | 矢じりだけを短い `\draw[-{Stealth}]` で描く。markings は長い線に使う |
| `Text line contains an invalid character` | `.tikz` / `.preamble.tex` に制御文字(zsh の `echo '\u...'` などで混入) | ファイルはエディタか `printf '%s\n'` で書く。build.py は該当ファイルと行を表示して止まる |
| `\input` したファイルが見つからない | パスが本文ファイル基準でない | `\input` のパスは**メインの .tex があるフォルダ**基準。insert.py はこれを計算して書く |

## 見た目の落とし穴

- `scale=` で全体を縮めると、線幅と文字は縮まず座標だけ縮む(`transform shape` を付けるとノードも縮む)。大きさ調整は `x=` / `y=` の単位で行う。
- `\resizebox` は文字も線も縮むので、本文と文字の大きさがずれる。使うのは、元の大きさに戻せない事情があるときだけ。
- 本文幅より広い図は `Overfull \hbox` になる。build.py の出力サイズ(cm)と本文幅を比べる。
- 円と管・配線の接続部: 完全な円を描いてから管を足すと、接続部に円の線が残る。原図で線が途切れているなら、円は `arc[start angle=..,end angle=..]` で接続部を空けて描く(開始角は `asin(管の半幅/半径)`)。
- 網点(スクリーントーン)の塗りは、一様な `fill=black!25` 程度に置き換える。濃さは measure.py `--smooth 3 --ink any` の周辺で目視するか、網点部分の平均輝度から決める。
- 縦書きの軸題(「エネルギー」「ひずみエネルギー」など)は、1文字ずつ `\\` で縦に積んだノードにし、長音「ー」だけ `\rotatebox{90}{ー}`(graphicx)で回す。文書が縦組みの機能を持つなら、その命令を使ってもよい。
- pgfplots の軸の中に置く文字(棒の上の値など)は、`anchor=south` だと高さがずれやすい。measure.py `--bbox` で測った中心に `inner sep=0pt` で置く。
- 原図と同じ幅に文字の塊を揃えたいとき(左右に余白なく組まれた注記など)は、行ごとに `\makebox[幅][s]{...}` で均等に割り付ける。大きさは相対指定(`\footnotesize` など)を基本にし、最後の行だけ幅を変える。
- 部品(`pic`)を `xscale=-1` で左右反転すると、中のラベルの位置も反転する。原図のラベルが反転していないなら、ラベルは部品の外で個別に置く。
- 同じ枠を何度も使う図(選択肢のグラフ①〜⑥など)は `panel/.pic={...}` にまとめ、`\pic[pic text=①] at (x,y) {panel};` で置く。pic の中では `\tikzpictext` で番号を受け取る。
- luatexja の丸数字(①〜⑥)はノードの中心より上に寄って見える。`yshift=-0.1cm` 前後で調整する。
- 矢印が箱にめり込む・離れる: 座標ではなくノード名(`(a) -- (b)`)かアンカー(`(a.east)`)でつなぐ。
- `node distance` の基準: `positioning` の `below=of a` は、ノードの**境界**間の距離。中心間ではない。
- 手書きの文字の位置に `\node` を置くと、組版文字の幅が違うためはみ出す。`anchor` を意識して置く(左端揃えなら `anchor=west`)。
- 色: `xcolor` の `!` 混色(`blue!60!black`)は文書側の `xcolor` オプション(`dvipsnames` など)に依存しないので安全。`Navy` のような名前色は文書側のオプションが要る。

## 照合のときの落とし穴

- 重ね合わせで、図の右へ行くほどずれが一方向に大きくなる場合、図の座標ではなく縮尺の問題を疑う。参照画像の目盛りや線の位置を measure.py で測り、TikZ の座標と一致するなら、ずれているのは描画側である。図を「補正」しない。
- 目で直すと、重ね合わせの見え方に引きずられて余計な補正をしやすい。印刷物の図は measure.py の実測値を正とする。

- らせん・ばね・波形のように同じ形が繰り返す線は、座標をなぞらず式で描く(`templates/solenoid.tikz`)。ピッチは中心線の交点の間隔だけで決めない。半ピッチずれた2本の線は中心の高さで X 字に交わるので、ピッチ p の2本とピッチ 2p の1本を取り違えやすい。線の傾き(1本の線が上下を横切る間に進む x)も確かめる。
- 式のパラメータ(ピッチ・始点・投影の振れ a)は、原図の黒い画素に曲線がどれだけ乗るかを数値で最大化して決めると早い。numpy で曲線上の点を画素に写し、`(255-画素値)/255` の平均を格子探索する。複数の線が重なるときは、決まった線の画素を除外してから次を探す。手前と裏で線の太さが違う図(手前だけ太い)もあるので、半周ごとの一致度も見る。

## 文書へ入れるとき

- 図を多数入れる長い文書でコンパイルが遅くなったら、TikZ の外部化(`\usetikzlibrary{external}` `\tikzexternalize[prefix=tikzcache/]`、`-shell-escape` が必要)か、build.py が作った PDF を `\includegraphics` で入れる方法を案内する。
- `beamer` では `figure` 環境の浮動は不要。`\input{figs/x.tikz}` をフレームにそのまま置く。
- 二段組で段幅を超える図は `figure*`。
- Overleaf では `figs/` フォルダごとアップロードしてもらう。`.preamble.tex` の中身はメイン文書のプリアンブルへ。
- Word / Google Docs / Markdown には build.py が作った `.svg`(劣化しない)か `.png`(220 dpi)を渡す。
