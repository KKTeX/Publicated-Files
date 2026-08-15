# 鉄緑の校内模試模試を作ろう（非公式）

Qiita記事用の公開テンプレートです。元の制作物と同じく、B5問題冊子12ページ、B4横解答用紙5ページ、6大問、計算用紙、`KKran`解答欄を含みます。

GitHub上の公開先: <https://github.com/KKTeX/Publicated-Files/tree/main/Qiita/鉄緑の校内模試模試を作ろう（非公式）>

実際の試験問題・日付・受験者情報は含みません。フォントはmacOS固有のヒラギノではなく、TeX Live収録の原ノ味フォントを使用します。

```sh
make
make render
```

- `mock-exam.pdf`: 問題冊子
- `mock-answersheet.pdf`: 解答用紙
- `fontset-public.sty`: ヒラギノ互換コマンドを原ノ味へ写像する公開用設定
