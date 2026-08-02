# KKTeX LaTeX Style Files

LaTeX (LuaLaTeX / pLaTeX 系) 向けに作成したスタイルファイル群を公開するリポジトリです。

## 構成

```
textboxes_pub/        装飾テキストボックス（ChartBox, PracticeBox, TetsuKeyBox）
sectioncustomize_pub/ 見出しのカスタマイズ（sectioncustomize0）
chemstruct_pub/       化学構造式（KKchemstruct）
  doc/                取扱説明書（日本語版・英語版、.tex と .pdf）
  tests/              回帰テストと出力
tests/                textboxes_pub / sectioncustomize_pub の回帰テスト
Qiita/                解説記事の原稿
```

## 収録パッケージ

### `textboxes_pub/`
本文中で使う装飾テキストボックス類。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `ChartBox.sty` | `ChartBox` | ★/☆ による評価マークを伴うチャート用ボックス。 |
| `PracticeBox.sty` | `PracticeBox` | 練習問題向けのボックス。Lua を利用した文字処理を含むため LuaLaTeX で使用。 |
| `TetsuKeyBox.sty` | `TetsuKeyBox` | タイトル横にサブタイトル領域を持つ「鉄則」型ボックス。 |

いずれも `tcolorbox` (`most` ライブラリ) に依存します。

#### `ptbs`（TetsuKeyBox）

```latex
\begin{ptbs}{鉄則}[短い説明]
本文をここに書きます。
\end{ptbs}
```

第1引数はタイトル、第2引数（省略可）は右側の説明、第3引数（省略可）は
`tcolorbox` の追加設定です。長いタイトルはタイトル行の30%を上限として
横方向に縮小され、説明を省略または空にした場合も右側の領域を維持します。

### `sectioncustomize_pub/`
セクション見出しのカスタマイズ用パッケージ。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `sectioncustomize0.sty` | `sectioncustomize0` | `tikz` (shadows.blur) と `tcolorbox`、`needspace` を用いた section〜chapter の見出し装飾。 |

### `chemstruct_pub/`
高校化学の構造式を組むためのマクロ集。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `KKchemstruct.sty` | `KKchemstruct` | `chemfig` を参考書の図版に合わせて設定し、置換ベンゼン・示性式・反応式・注釈をまとめて扱えるようにしたもの。 |

寸法はすべて `em` 指定なので、本文サイズを変えても比率が保たれます。
数値は `\KKchemsetup{ring sep=1.35em,bond width=0.05em,...}` で一括変更でき、
グループ内で呼べば変更はそのグループに閉じます。

#### 主なマクロ

| マクロ | 用途 |
| --- | --- |
| `\KKbenzene[2=OH,3=COOH]` | 置換ベンゼン。位置は真上を 1 として時計回りに 1〜6。`angle=`（回転）、`sep=`（一辺）、`kekule=b`（二重結合の反転）も指定可。 |
| `\KKphenyl{COOH}` / `\KKphenylene{SO_3H}` / `\KKphenylring` | 本文中に流し込む横向き（flat-top）の環。 |
| `\KKchemring[<chemfigキー>]{...}` | 縮合環など、chemfig の生の記法で書く環（原子中心間距離が一定）。 |
| `\KKchemchain[<chemfigキー>]{...}` | 示性式。可視線の長さが一定になるので `CH_2` のような広いラベルでも潰れません。 |
| `\KKcarbonyl` / `\KKcarbonyldown` / `\KKdative{<角度>}` | 鎖の中で使う断片（上下向きの C=O、配位結合の矢印）。 |
| `\KKscheme{...}` / `\KKbranchscheme{...}` | 反応式と、1 つの基質から 2 つの生成物へ分かれる反応式。 |
| `\KKname{<構造>}{<名称>}` | 構造式の下に化合物名を添える。 |
| `\KKchemmark{<節点>}{<節点>}` / `\KKhbond` / `\KKchemcross` | 脱離部分の点線囲み・水素結合の点線・「反応しない」を示す×印。 |
| `\ck{<式>}`（`\KKchemformula`）、`\ckm` / `\ckp` | 数式モードに入らない場所（矢印ラベルなど）で使う化学式とイオンの右肩。 |

`\KKsalicylicacid`、`\KKphthalicanhydride`、`\KKtriglyceride{R_1}{R_2}{R_3}` など、
頻出化合物のマクロも同梱しています（`.sty` の末尾の節）。

```latex
\KKbenzene[2=OH,3=COOH]                     % サリチル酸
\KKchemchain{H-O-S(\KKdative{2}O)(\KKdative{6}O)-O-H}
\KKscheme{\KKsalicylicacid\arrow{->[\ck{CH_3OH}][エステル化]}\KKmethylsalicylate}
```

`\KKchemmark` と `\KKhbond` は TikZ のノード参照を使うため、位置が定まるまでに
2 回コンパイルが要ります。

全マクロの説明・オプション一覧・作例は取扱説明書にあります。

- [`chemstruct_pub/doc/KKchemstruct-manual-ja.pdf`](./chemstruct_pub/doc/KKchemstruct-manual-ja.pdf)（日本語版）
- [`chemstruct_pub/doc/KKchemstruct-manual-en.pdf`](./chemstruct_pub/doc/KKchemstruct-manual-en.pdf)（英語版）

原稿は同じディレクトリの `.tex`（`jlreq` クラス）です。組み直すときは
リポジトリ直下で次のように実行してください（注釈の位置決めのため 2 回）。

```sh
TEXINPUTS=./chemstruct_pub: lualatex -output-directory=/tmp chemstruct_pub/doc/KKchemstruct-manual-ja.tex
```

## 使い方

各 `.sty` を TeX のサーチパス上に配置するか、文書と同じディレクトリに置いた上で `\usepackage{...}` で読み込んでください。

```latex
\usepackage{TetsuKeyBox}
\usepackage{ChartBox}
\usepackage{PracticeBox}     % LuaLaTeX 必須
\usepackage{sectioncustomize0}
\usepackage{KKchemstruct}
```

## 動作環境

- TeX エンジン: LuaLaTeX を推奨 (`PracticeBox` は LuaLaTeX 必須)。
  `KKchemstruct` は LuaLaTeX / pLaTeX + dvipdfmx の両方で動作確認済み。
- 主な依存パッケージ: `tcolorbox`, `tikz`, `calc`, `varwidth`, `needspace`,
  `chemfig`, `etoolbox`, `xkeyval`

## 動作確認

`tests/ptbs-regression.tex` は、通常・長いタイトル、空の説明欄、追加キー、
改ページを確認します。リポジトリ直下で次のいずれかを実行してください。

```sh
TEXINPUTS=./textboxes_pub: lualatex -output-directory=/tmp tests/ptbs-regression.tex
TEXINPUTS=./textboxes_pub: platex -kanji=utf8 -output-directory=/tmp tests/ptbs-regression.tex
dvipdfmx -o /tmp/ptbs-regression.pdf /tmp/ptbs-regression.dvi
```

`tests/sectioncustomize0-regression.tex` は、chapter から subsubsection までと
見出しが連続する場合の余白を確認します。

```sh
TEXINPUTS=./sectioncustomize_pub: lualatex -output-directory=/tmp tests/sectioncustomize0-regression.tex
TEXINPUTS=./sectioncustomize_pub: platex -kanji=utf8 -output-directory=/tmp tests/sectioncustomize0-regression.tex
dvipdfmx -o /tmp/sectioncustomize0-regression.pdf /tmp/sectioncustomize0-regression.dvi
```

`chemstruct_pub/tests/kkchemstruct-regression.tex` は、置換ベンゼン、横向きの環、
示性式、縮合環、注釈、反応式、寸法の一括変更を一通り確認します。`\KKchemmark` と
`\KKhbond` の位置決めのため、2 回コンパイルしてください。

```sh
TEXINPUTS=./chemstruct_pub: lualatex -output-directory=/tmp chemstruct_pub/tests/kkchemstruct-regression.tex
TEXINPUTS=./chemstruct_pub: platex -kanji=utf8 -output-directory=/tmp chemstruct_pub/tests/kkchemstruct-regression.tex
dvipdfmx -o /tmp/kkchemstruct-regression.pdf /tmp/kkchemstruct-regression.dvi
```

各テストの出力 PDF は `tests/output/`（`KKchemstruct` は
`chemstruct_pub/tests/output/`）に置いてあります。

## ライセンス

本リポジトリのコードは [MIT License](./LICENSE.md) の下で公開しています。
