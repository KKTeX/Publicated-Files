# KKTeX LaTeX Style Files

LaTeX (LuaLaTeX / pLaTeX 系) 向けに作成したスタイルファイル群を公開するリポジトリです。

## 構成

```
textboxes_pub/        装飾テキストボックス（ChartBox, PracticeBox, TetsuKeyBox）
sectioncustomize_pub/ 見出しのカスタマイズ（sectioncustomize0）
tests/                回帰テストと出力
Qiita/                解説記事の再現用 LaTeX と PDF
```

## 収録パッケージ

### `textboxes_pub/`
本文中で使う装飾テキストボックス類。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `ChartBox.sty` | `ChartBox` | ★/☆ による評価マークを伴うチャート用ボックス。 |
| `PracticeBox.sty` | `PracticeBox` | 練習問題向けのボックス。タイトル文字を交互の白黒マスで表示。 |
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

#### `mydec8`（ChartBox）

```latex
\begin{mydec8}[blue]{分類}{項目}{説明}{3}
本文をここに書きます。
\end{mydec8}
```

色、第1見出し、第2見出し、第3見出し、評価数の順に指定します。色は省略時 `red`、
評価数が1〜3なら不足分を `☆`、指定数を `★` で表示します。

#### `practicebox`（PracticeBox）

```latex
\begin{practicebox}{演習問題}[基本]
本文をここに書きます。
\end{practicebox}
```

第1引数は白黒マスで表示するタイトル、第2引数（省略可）は右側の補足、
第3引数（省略可）は `tcolorbox` の追加設定です。

### `sectioncustomize_pub/`
セクション見出しのカスタマイズ用パッケージ。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `sectioncustomize0.sty` | `sectioncustomize0` | `tikz` (shadows.blur) と `tcolorbox`、`needspace` を用いた section〜chapter の見出し装飾。 |

## 別リポジトリに分離したパッケージ

化学構造式用の `KKchemstruct` は、単独のリポジトリに履歴ごと移しました。

- [KKTeX/KKchemstruct](https://github.com/KKTeX/KKchemstruct) — `chemfig` を用いた
  構造式マクロ集（置換ベンゼン・示性式・反応式・注釈、日英の取扱説明書つき）

## Qiita 記事の作成例

| 作成例 | LaTeX | PDF |
| --- | --- | --- |
| オシャレな `tcolorbox` を誰でも作る方法 | [`.tex`](./Qiita/オシャレなtcolorboxを誰でも作る方法（LaTeX確認シリーズ%23５）/qiita-tcolorbox-examples.tex) | [`.pdf`](./Qiita/オシャレなtcolorboxを誰でも作る方法（LaTeX確認シリーズ%23５）/qiita-tcolorbox-examples.pdf) |
| `chemfig` で化学構造式を短く書く「KKchemstruct」の使い方 | [`.tex`](./Qiita/chemfigで化学構造式を短く書く「KKchemstruct」の使い方（LaTeX確認シリーズ%23８）/qiita-kkchemstruct-examples.tex) | [`.pdf`](./Qiita/chemfigで化学構造式を短く書く「KKchemstruct」の使い方（LaTeX確認シリーズ%23８）/qiita-kkchemstruct-examples.pdf) |

`KKchemstruct` の作成例をコンパイルする場合は、先に
[`KKTeX/KKchemstruct`](https://github.com/KKTeX/KKchemstruct) の
`KKchemstruct.sty` を文書と同じディレクトリか TeX の検索パスへ配置してください。

## 使い方

各 `.sty` を TeX のサーチパス上に配置するか、文書と同じディレクトリに置いた上で `\usepackage{...}` で読み込んでください。

```latex
\usepackage{TetsuKeyBox}
\usepackage{ChartBox}
\usepackage{PracticeBox}
\usepackage{sectioncustomize0}
```

## 動作環境

- TeX エンジン: LuaLaTeX を推奨
- 主な依存パッケージ: `tcolorbox`, `tikz`, `calc`, `varwidth`, `needspace`

## 動作確認

`tests/ptbs-regression.tex` は、通常・長いタイトル、空の説明欄、追加キー、
改ページを確認します。リポジトリ直下で次のいずれかを実行してください。

```sh
TEXINPUTS=./textboxes_pub: lualatex -output-directory=/tmp tests/ptbs-regression.tex
TEXINPUTS=./textboxes_pub: platex -kanji=utf8 -output-directory=/tmp tests/ptbs-regression.tex
dvipdfmx -o /tmp/ptbs-regression.pdf /tmp/ptbs-regression.dvi
```

`tests/chart-practice-regression.tex` は、評価数、和文タイトル、追加キー、
両ボックスの改ページを LuaLaTeX で確認します。

```sh
TEXINPUTS=./textboxes_pub: lualatex -output-directory=/tmp tests/chart-practice-regression.tex
```

`tests/sectioncustomize0-regression.tex` は、chapter から subsubsection までと
見出しが連続する場合の余白を確認します。

```sh
TEXINPUTS=./sectioncustomize_pub: lualatex -output-directory=/tmp tests/sectioncustomize0-regression.tex
TEXINPUTS=./sectioncustomize_pub: platex -kanji=utf8 -output-directory=/tmp tests/sectioncustomize0-regression.tex
dvipdfmx -o /tmp/sectioncustomize0-regression.pdf /tmp/sectioncustomize0-regression.dvi
```

各テストの出力 PDF は `tests/output/` に置いてあります。

## ライセンス

本リポジトリのコードは [MIT License](./LICENSE.md) の下で公開しています。
