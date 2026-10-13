# 図の種類と道具

雛形は `templates/<name>.tikz` と `templates/<name>.preamble.tex` にある。すべて build.py でコンパイル確認済み。書き始めるときは近い雛形をコピーし、座標と文字を差し替える。

| 図の種類 | 雛形 | 主な道具 | 起こすときの要点 |
|---|---|---|---|
| ブロック図、フローチャート、システム構成図 | `flowchart` | `positioning`, `shapes.geometric`, `shapes.misc`, `arrows.meta` | 箱の種類ごとにスタイルを1つ作る。並びは `below=of` / `right=of`、折れ線は `|-` `-|`。手書きの位置が不規則でも、行・列が見えるなら揃える |
| 状態遷移、オートマトン、グラフ理論、ネットワーク | `automaton` | `automata`, `quotes`, `positioning`, (`graphs`, `graphdrawing` は LuaLaTeX のみ) | 辺ラベルは `edge["$a$"]`。カンマを含むラベルは `"{$a,b$}"`。自己ループは `loop above` |
| 木(探索木、構文木、組織図、分類) | `tree` | `forest` | 括弧記法で書くと間隔が自動で揃う。手書きの座標は使わない。環境は `forest`(tikzpicture ではない) |
| 可換図式、圏論・代数の図式 | `commutative` | `tikz-cd` | 行列状に書く。斜めの矢印は `ru` `rd`。ラベルを矢印の反対側に置くのは `"f"'` |
| 電気回路 | `circuit` | `circuitikz` | 素子は `to[R]` `to[C]` `to[L]` `to[V]` など。JIS/IEC系の図なら `european`。接点は `-*` |
| 概形・模式的なグラフ(目盛りの数値が無い) | — | 素の TikZ | 軸は `\draw[->]`、曲線は極値・変曲点で区切った `.. controls ..`。目盛りの代わりに $t_1$ などの記号を破線で示す |
| 関数のグラフ、測定データ、散布図 | `plot` | `pgfplots` (`compat=1.18`) | 曲線をなぞらない。式が分かれば式、分からなければ読み取った点を `table` にする。軸範囲・目盛り・ラベル・凡例を元図に合わせる |
| 棒グラフ、折れ線グラフ(Excel・スライドの図) | `bars` | `pgfplots` | 棒の高さや点の値は grid.py の拡大で目盛りから読む。数値ラベルがあれば数値ラベルを正とする |
| 平面幾何、作図 | `geometry` | `calc`, `angles`, `quotes`, `intersections` / `tkz-euclide` | 点は `\coordinate` で名前を付ける。中点・垂線の足・交点は計算で求め、手書きの位置を写さない。長さの比や角度が問題文で決まっているならそれに従う |
| 力学・物理の図(斜面、力、ばね、滑車) | `physics` | `patterns.meta`, `decorations.pathmorphing`, `arrows.meta` | 斜面上の物体は `rotate` した scope に入れる。地面・壁は `pattern={Lines[...]}`。ばねは `coil` |
| ソレノイド、コイル、ばね(らせん) | `solenoid` | `plot` と式 | らせんは式で描き、パラメータは画素への当てはめで決める。太い線は手前の半周だけ太くする |
| 数直線、区間、時系列、年表 | `timeline` | `\foreach` | 目盛りは `\foreach`。端点の含む・含まないは黒丸・白丸 |
| ベン図、集合 | `venn` | `\clip` | 共通部分は `\clip` してから塗る。透過で重ねるなら `fill opacity` |
| 化学構造式・反応式(有機) | — | 素の TikZ(六員環は `\foreach` の正六角形)/ 新しく描くなら chemfig | 照合しながら起こすなら、実測した原子の座標に置く素の TikZ が早い。chemfig は最初の原子と結合角から位置が決まるため、原図に重ねる調整が難しい。原子記号は文字の左端に `anchor=base west` で置くと重なりがよい。上付き・下付きは `$\mathrm{H}^{a}$`、`$\mathrm{CH_3}$` |
| 立体配座(いす形・ニューマン投影) | — | `pic` で部品化 | いす形やニューマン投影は1つの `pic` にして使い回す。結合角は正確な値(120°、60°)で描く |
| 表・行列に矢印や囲みを足した図 | — | `matrix` (`matrix of math nodes`), `fit`, `backgrounds` | 行列は `\matrix[matrix of math nodes]`。figure 環境の引数内に入れるなら `ampersand replacement=\&` |
| 3次元の図(座標軸、立体) | — | `tikz-3dplot` (`\tdplotsetmaincoords`) | 視点角を元図に合わせる。隠れ線は破線 |
| シーケンス図、UML | — | `pgf-umlsd` か `positioning` | 素朴な図は positioning の方が調整しやすい |
| 地図・イラスト・写真的な絵 | — | — | TikZ化に向かない。画像のまま `\includegraphics` を勧める |

## スタイルの基準値

元図の雰囲気を残しつつ、文書の他の図と揃えるための既定値。元図や文書側にはっきりした基準があればそちらに従う。

- 線: `line width=0.6pt`(細い図)〜`0.8pt`(手書きの太いペン)。補助線は `thin` か `densely dashed`。
- 矢じり: `>={Stealth[length=2mm]}`(`arrows.meta`)。手書きの開いた矢じりなら `>={Straight Barb[length=2mm]}`。
- 文字: 指定しない(本文と同じ)。注記だけ `\small` か `\footnotesize`。
- 色: 手書きの色ペンは意味(強調、別系統)として読み、`blue!70!black` や `red!70!black` など落ち着いた色にする。白黒印刷が前提の文書なら色を線種・塗りの濃淡に置き換える。
- 角丸: 手書きで角が丸い箱は `rounded corners=1.5mm` 程度。
- 塗り: 手書きの斜線・塗りつぶしは `pattern={Lines[angle=45,distance=2mm]}` か `fill=gray!20`。
