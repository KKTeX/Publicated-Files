# KKTeX LaTeX Style Files

LaTeX (LuaLaTeX / pLaTeX 系) 向けに作成したスタイルファイル群を公開するリポジトリです。

## 収録パッケージ

### `textboxes_pub/`
本文中で使う装飾テキストボックス類。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `ChartBox_mydecseries.sty` | `ChartBox` | ★/☆ による評価マークを伴うチャート用ボックス。 |
| `PracticeBox_mydecseries.sty` | `PracticeBox` | 練習問題向けのボックス。Lua を利用した文字処理を含むため LuaLaTeX で使用。 |
| `TetsuKeyBox_mydecseries.sty` | `TetsuKeyBox` | タイトル横にサブタイトル領域を持つ「鉄則」型ボックス。 |

いずれも `tcolorbox` (`most` ライブラリ) に依存します。

### `sectioncustomize_pub/`
セクション見出しのカスタマイズ用パッケージ。

| ファイル | パッケージ名 | 概要 |
| --- | --- | --- |
| `sectioncustomize0_pub.sty` | `sectioncustomize0` | `tikz` (shadows.blur) と `tcolorbox`、`needspace` を用いた見出し装飾。 |

## 使い方

各 `.sty` を TeX のサーチパス上に配置するか、文書と同じディレクトリに置いた上で `\usepackage{...}` で読み込んでください。

```latex
\usepackage{TetsuKeyBox}
\usepackage{ChartBox}
\usepackage{PracticeBox}     % LuaLaTeX 必須
\usepackage{sectioncustomize0}
```

## 動作環境

- TeX エンジン: LuaLaTeX を推奨 (`PracticeBox` は LuaLaTeX 必須)
- 主な依存パッケージ: `tcolorbox`, `tikz`, `calc`, `varwidth`, `needspace`

## ライセンス

本リポジトリのコードは [MIT License](./LICENSE.md) の下で公開しています。
