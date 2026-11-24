// ============================================================================
// 手書き答案.swift — 東大国語（3ページ）の発行PDFに、手書き風・スキャン風の答案を書き込む
// ============================================================================
//
// 【使い方】
//   swift 手書き答案.swift --fields
//       解答欄の一覧（ラベル・ページ・種類・容量）を表示する。答案の字数はこれに合わせる。
//
//   swift 手書き答案.swift <発行PDF> <解答.json> <出力フォルダ>
//       発行PDF（1人3ページ × 人数）に解答を手書き風に書き込み、スキャン風の画像PDFにして
//       <出力フォルダ>/答案_01.pdf, 答案_02.pdf … を書き出す（各3ページ）。
//       n人目は発行PDFの 3n-2〜3n ページを使う。QRコードはそのまま残り、読めることを自己検査する。
//
//   オプション（省略可）:
//       --seed <整数>      筆跡の揺れの乱数の種（既定 64）。同じ種なら毎回同じ出力になる。
//       --dpi <整数>       スキャン解像度（既定 200）。
//       --debug <フォルダ>  検査用に、インク層PNGと字の配置JSONを書き出す。
//
// 【解答JSONの形式】（UTF-8）
//   {
//     "答案": [
//       {
//         "氏名": "青木　遥",            ← 省略可（氏名欄に横書き）
//         "科類": "文一",                ← 省略可（科類欄に横書き）
//         "解答": {
//           "第一問（一）": "……。",
//           "第一問（五）": "……",
//           "第一問（六）a": "縮図",
//           "第二問（一）ア": "……",
//           …
//         },
//         "消し跡": ["第一問（二）"]     ← 省略可（消しゴムで消して書き直した跡を付ける欄）
//       },
//       { … 2人目 … }
//     ]
//   }
//   ・「答案」の1番目が1人目（発行PDFの1〜3ページ）、2番目が2人目（4〜6ページ）。
//   ・書かないラベル、または "" の欄は空欄（無答）になる。
//   ・ラベルは下の一覧どおり。括弧は全角（半角の ( ) も受け付ける）。
//   ・縦書き。1字＝1マス（句読点・かぎ括弧・長音「ー」も1字と数える）。
//   ・全角スペース「　」は1マス空け。半角スペースは無視する。半角英数字は全角にする。
//   ・"\n" で次の行（マス目なら次の列）へ改行する。
//   ・行頭禁則：、。が行の先頭に来るときは、マス目では前の行の最後のマスにその字と一緒に入れ
//     （句読点は右下）、縦罫では前の行の最後の字を次の行へ送る。容量ちょうどの後の 、。 も
//     最後のマスにぶら下げる（この 1 字は容量に数えない）。
//   ・漢字枠は2字まで（上下に1字ずつ）。1字なら上の段に書く。
//   ・容量を超えた分は切り捨て、標準エラーに警告を出す（枠の外には決して書かない）。
//
// 【ラベル一覧】（容量は --fields で確認。字数は1行あたり）
//   1ページ  第一問（一） 第一問（二） 第一問（三） 第一問（四）     縦罫 2行×15字
//            第一問（五）                                             マス目 6列×20マス
//            第一問（六）a  第一問（六）b  第一問（六）c              漢字枠 2字
//   2ページ  第二問（一）ア  第二問（一）イ  第二問（一）カ           縦罫 1行×14字
//            第二問（二） 第二問（三） 第二問（四） 第二問（五）     縦罫 1行×15字
//            第三問（一） 第三問（四） 第三問（五）                   縦罫 2行（15字＋7字）
//            第三問（二）                                             縦罫 1行×2字
//            第三問（三）                                             縦罫 1行×15字
//   3ページ  第四問（一） 第四問（二） 第四問（三） 第四問（四）     縦罫 2行×15字
//
// 【仕組み】解答欄の位置は 用紙見本.pdf の罫線から mm 単位で埋め込んである（下の FIELDS）。
//   発行PDFの各ページについて、見出し（第一問 など）でページの順番を確かめ、罫線の位置を測る。
//   罫線が見本から全体にずれていれば、解答欄も同じだけ動かす（±2mm まで）。
//   字形は CoreText で Klee（クレー）→ 教科書体 → ヒラギノ明朝 の順に探して使い、
//   1字ごとに大きさ・傾き・位置を揺らし、字形全体をなめらかに歪め、線の太さを筆圧と
//   起筆・終筆で変え、鉛筆の濃淡とかすれを付ける（2人目は1人目より揺れが大きい）。
//   書いた字はすべて、外接矩形がマス（行）の内側に収まっているかを検査する（はみ出せば終了コード3）。
//   最後にページ全体を 200dpi の画像にし、わずかな傾き・ずれ・紙の色・ノイズ・ぼけを
//   加えて JPEG にし、元と同じ用紙サイズのPDFに収める。加工後に QR が読めることも確かめる。
//   使うのは macOS 標準の PDFKit / CoreGraphics / CoreText / ImageIO / CoreImage（QR読み取り）のみ。
//   終了コード: 0 成功 / 1 使い方の誤り / 2 入力の誤り（JSON・ラベル）/ 3 用紙の不一致・検査NG
// ============================================================================

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import CoreImage
import PDFKit

// MARK: - 出力ヘルパ

var warnedOnce = Set<String>()
func warn(_ s: String) {
    if warnedOnce.contains(s) { return }   // 氏名欄などページごとに同じ警告を繰り返さない
    warnedOnce.insert(s)
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}
func fail(_ s: String, code: Int32 = 2) -> Never { warn("エラー: " + s); exit(code) }

// MARK: - 幾何（すべて mm、用紙の左上が原点、y は下向き）

struct MMRect {
    var x0: Double, y0: Double, x1: Double, y1: Double
    var w: Double { x1 - x0 }
    var h: Double { y1 - y0 }
    var cx: Double { (x0 + x1) / 2 }
    var cy: Double { (y0 + y1) / 2 }
    func inset(_ dx: Double, _ dy: Double) -> MMRect { MMRect(x0: x0 + dx, y0: y0 + dy, x1: x1 - dx, y1: y1 - dy) }
    func contains(_ r: CGRect) -> Bool {
        Double(r.minX) >= x0 - 1e-6 && Double(r.maxX) <= x1 + 1e-6 && Double(r.minY) >= y0 - 1e-6 && Double(r.maxY) <= y1 + 1e-6
    }
    func intersects(_ o: MMRect) -> Bool { x0 < o.x1 && o.x0 < x1 && y0 < o.y1 && o.y0 < y1 }
    var cg: CGRect { CGRect(x: x0, y: y0, width: w, height: h) }
    var json: [Double] { [x0, y0, x1, y1].map { ($0 * 1000).rounded() / 1000 } }
}
func R(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> MMRect { MMRect(x0: x0, y0: y0, x1: x1, y1: y1) }

enum Kind { case ruled, grid, kanji, horizontal }

struct Field {
    let label: String
    let page: Int          // 1〜3（1人分の中のページ）
    let kind: Kind
    let rects: [MMRect]    // ruled: 各行の内側（右の行から順に） / grid・kanji・horizontal: 枠の内側1つ
    var cols = 0           // grid: 列数
    var rows = 0           // grid: 1列のマス数 / kanji: 上下の分割数
}

// 用紙見本.pdf（A4横 297×210mm）の罫線から読み取った解答欄。
//   縦罫: 見出し行の下の横線（45.4、第二問（一）は 52.9）から、枠の下端 179.5 まで。
//         途中の横線と×印で打ち切られた行（第三問）は、その横線（64.7・112.8）まで。
//   マス目: 外枠 88.0〜135.1 × 35.2〜190.6 を縦線5本・横点線19本で 6列×20行に分割（7.85×7.77mm）。
//   漢字枠: 75.2〜88.1、点線で上下2マスに分割（a 52.5/63.5/74.5、b 81.6/92.6/103.6、c 110.7/121.7/132.7）。
let FIELDS: [Field] = [
    // ---- 1ページ 第一問 ----
    Field(label: "第一問（一）", page: 1, kind: .ruled, rects: [R(209.6, 45.4, 218.4, 179.5), R(200.8, 45.4, 209.6, 179.5)]),
    Field(label: "第一問（二）", page: 1, kind: .ruled, rects: [R(192.0, 45.4, 200.8, 179.5), R(183.2, 45.4, 192.0, 179.5)]),
    Field(label: "第一問（三）", page: 1, kind: .ruled, rects: [R(174.4, 45.4, 183.2, 179.5), R(165.6, 45.4, 174.4, 179.5)]),
    Field(label: "第一問（四）", page: 1, kind: .ruled, rects: [R(156.8, 45.4, 165.6, 179.5), R(148.0, 45.4, 156.8, 179.5)]),
    Field(label: "第一問（五）", page: 1, kind: .grid, rects: [R(88.0, 35.2, 135.1, 190.6)], cols: 6, rows: 20),
    Field(label: "第一問（六）a", page: 1, kind: .kanji, rects: [R(75.2, 52.5, 88.1, 74.5)], rows: 2),
    Field(label: "第一問（六）b", page: 1, kind: .kanji, rects: [R(75.2, 81.6, 88.1, 103.6)], rows: 2),
    Field(label: "第一問（六）c", page: 1, kind: .kanji, rects: [R(75.2, 110.7, 88.1, 132.7)], rows: 2),
    // ---- 2ページ 第二問（右側） ----
    Field(label: "第二問（一）ア", page: 2, kind: .ruled, rects: [R(209.6, 52.9, 218.4, 179.5)]),
    Field(label: "第二問（一）イ", page: 2, kind: .ruled, rects: [R(200.8, 52.9, 209.6, 179.5)]),
    Field(label: "第二問（一）カ", page: 2, kind: .ruled, rects: [R(192.0, 52.9, 200.8, 179.5)]),
    Field(label: "第二問（二）", page: 2, kind: .ruled, rects: [R(183.2, 45.4, 192.0, 179.5)]),
    Field(label: "第二問（三）", page: 2, kind: .ruled, rects: [R(174.4, 45.4, 183.2, 179.5)]),
    Field(label: "第二問（四）", page: 2, kind: .ruled, rects: [R(165.6, 45.4, 174.4, 179.5)]),
    Field(label: "第二問（五）", page: 2, kind: .ruled, rects: [R(156.8, 45.4, 165.6, 179.5)]),
    // ---- 2ページ 第三問（左側） ----
    Field(label: "第三問（一）", page: 2, kind: .ruled, rects: [R(88.0, 45.4, 96.8, 179.5), R(79.2, 45.4, 88.0, 112.8)]),
    Field(label: "第三問（二）", page: 2, kind: .ruled, rects: [R(70.4, 45.4, 79.2, 64.7)]),
    Field(label: "第三問（三）", page: 2, kind: .ruled, rects: [R(61.6, 45.4, 70.4, 179.5)]),
    Field(label: "第三問（四）", page: 2, kind: .ruled, rects: [R(52.8, 45.4, 61.6, 179.5), R(44.0, 45.4, 52.8, 112.8)]),
    Field(label: "第三問（五）", page: 2, kind: .ruled, rects: [R(35.35, 45.4, 44.0, 179.5), R(26.7, 45.4, 35.35, 112.8)]),
    // ---- 3ページ 第四問 ----
    Field(label: "第四問（一）", page: 3, kind: .ruled, rects: [R(209.6, 45.4, 218.4, 179.5), R(200.8, 45.4, 209.6, 179.5)]),
    Field(label: "第四問（二）", page: 3, kind: .ruled, rects: [R(192.0, 45.4, 200.8, 179.5), R(183.2, 45.4, 192.0, 179.5)]),
    Field(label: "第四問（三）", page: 3, kind: .ruled, rects: [R(174.4, 45.4, 183.2, 179.5), R(165.6, 45.4, 174.4, 179.5)]),
    Field(label: "第四問（四）", page: 3, kind: .ruled, rects: [R(156.8, 45.4, 165.6, 179.5), R(148.0, 45.4, 156.8, 179.5)]),
]

// 氏名欄・科類欄（各ページ共通・横書き・省略可）
let NAME_BOX = R(180.1, 7.4, 254.0, 18.9)
let CLASS_BOX = R(138.6, 7.4, 175.6, 18.9)

// 何も書かない領域（QRコード・四隅のマーカー、各 5mm の余白込み）
let KEEP_OUT: [MMRect] = [
    R(263.4, 0, 288.3, 23.7),                       // QR（268.4〜283.2 × 3.9〜18.7）
    R(0, 0, 17.4, 17.4), R(279.6, 0, 297, 17.4),     // 上の角マーカー（6.0〜12.35）
    R(0, 192.6, 17.4, 210), R(279.6, 192.6, 297, 210), // 下の角マーカー
]

let RULED_MARGIN = 1.2        // 縦罫の行の上下端から空ける量（mm）
let RULED_PITCH_FACTOR = 0.96 // 縦罫の字送り ≈ 行幅 × この値
let CELL_CLEAR = 0.55         // マス・漢字枠の罫線から墨を離す量（mm）
let COL_CLEAR = 0.6           // 縦罫の罫線から墨を離す量（mm）

// スキャン風加工の強さ。ぼけ・ノイズを強くすると OpenCV の QR 検出が落ちやすくなるので控えめにしてある。
let SCAN_MAX_ANGLE = 0.26     // 傾き（度、0.08〜この値、向きはランダム）
let SCAN_MAX_SHIFT = 0.7      // ずれ（mm、縦横それぞれ ±）
let SCAN_BLUR: Float = 0.35   // 3×3 二項フィルタを混ぜる割合
let SCAN_GRAIN: Float = 3     // 画素ごとのノイズ（階調、幅）
let SCAN_MOTTLE: Float = 3    // 紙のむら（階調、幅）
let SCAN_SHADE: Float = 1     // 照明むら（1 で右下が約2.6%暗い）
let JPEG_QUALITY = 0.9

// MARK: - 字の置き場所（スロット）

/// 各欄のスロット。外側の配列が「行（列）」で右から左、内側が上から下（横書きは左から右）。
func layoutSlots(_ f: Field) -> [[MMRect]] {
    switch f.kind {
    case .ruled:
        // 字送りは欄の中でそろえる：最も長い行で決め、短い行も同じ字送りで上から詰める。
        let maxH = f.rects.map { $0.h }.max()!
        let minW = f.rects.map { $0.w }.min()!
        let usable = maxH - 2 * RULED_MARGIN
        let n = max(1, Int(floor(usable / (minW * RULED_PITCH_FACTOR) + 0.05)))
        let pitch = usable / Double(n)
        return f.rects.map { c in
            let k = max(0, Int(floor((c.h - 2 * RULED_MARGIN) / pitch + 0.02)))
            return (0..<k).map { i in
                R(c.x0, c.y0 + RULED_MARGIN + Double(i) * pitch, c.x1, c.y0 + RULED_MARGIN + Double(i + 1) * pitch)
            }
        }
    case .grid:
        let r = f.rects[0]
        let cw = r.w / Double(f.cols), ch = r.h / Double(f.rows)
        return (0..<f.cols).map { ci in
            let x1 = r.x1 - cw * Double(ci)
            return (0..<f.rows).map { ri in R(x1 - cw, r.y0 + ch * Double(ri), x1, r.y0 + ch * Double(ri + 1)) }
        }
    case .kanji:
        let r = f.rects[0]
        let ch = r.h / Double(f.rows)
        return [(0..<f.rows).map { i in R(r.x0, r.y0 + ch * Double(i), r.x1, r.y0 + ch * Double(i + 1)) }]
    case .horizontal:
        let r = f.rects[0]
        let pitch = r.h * 0.68
        let left = r.x0 + 2.0
        let k = Int(floor((r.w - 4.0) / pitch))
        return [(0..<k).map { i in R(left + pitch * Double(i), r.y0, left + pitch * Double(i + 1), r.y1) }]
    }
}

/// 墨がはみ出してはいけない範囲（スロットごと）
func allowedRect(_ f: Field, _ slot: MMRect) -> MMRect {
    switch f.kind {
    case .ruled: return R(slot.x0 + COL_CLEAR, slot.y0 + 0.15, slot.x1 - COL_CLEAR, slot.y1 - 0.15)
    case .grid, .kanji: return slot.inset(CELL_CLEAR, CELL_CLEAR)
    case .horizontal: return R(slot.x0 + 0.15, slot.y0 + 1.2, slot.x1 - 0.15, slot.y1 - 1.2)
    }
}

/// 字の大きさ（em の mm）
func emSize(_ f: Field, _ slot: MMRect) -> Double {
    switch f.kind {
    case .ruled: return 0.74 * min(slot.w, slot.h)
    case .grid: return 0.77 * min(slot.w, slot.h)
    case .kanji: return 0.74 * min(slot.w, slot.h)
    case .horizontal: return 0.60 * slot.h
    }
}

func capacityText(_ f: Field) -> String {
    let s = layoutSlots(f)
    let total = s.reduce(0) { $0 + $1.count }
    switch f.kind {
    case .grid: return "マス目  \(f.cols)列×\(f.rows)マス = \(total)字"
    case .kanji: return "漢字枠  \(total)字（上下に1字ずつ）"
    case .horizontal: return "横書き  \(total)字"
    case .ruled:
        let counts = s.map { $0.count }
        if Set(counts).count == 1 { return "縦罫    \(counts.count)行×\(counts[0])字 = \(total)字" }
        return "縦罫    \(counts.count)行（" + counts.map { "\($0)字" }.joined(separator: "＋") + "）= \(total)字"
    }
}

// MARK: - 乱数・ノイズ

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x632BE59BD9B4E019 }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func u() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func r(_ a: Double, _ b: Double) -> Double { a + (b - a) * u() }
    /// -1〜1 の三角分布（0付近が多い）
    mutating func tri() -> Double { u() + u() - 1 }
}

func mixSeed(_ parts: [UInt64]) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for p in parts { h = (h ^ p) &* 0x100000001b3; h ^= h >> 29 }
    return h
}

@inline(__always) func hash01(_ x: Int, _ y: Int, _ seed: UInt32) -> Float {
    var h = (UInt32(truncatingIfNeeded: x) &* 0x8da6b343) ^ (UInt32(truncatingIfNeeded: y) &* 0xd8163841) ^ (seed &* 0xcb1ab31f)
    h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
    return Float(h & 0xFFFFFF) / Float(0x1000000)
}

@inline(__always) func vnoise(_ x: Float, _ y: Float, _ seed: UInt32) -> Float {
    let xi = Int(floor(x)), yi = Int(floor(y))
    var fx = x - Float(xi), fy = y - Float(yi)
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    let a = hash01(xi, yi, seed), b = hash01(xi + 1, yi, seed)
    let c = hash01(xi, yi + 1, seed), d = hash01(xi + 1, yi + 1, seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
}

// MARK: - 字形（CoreText）

struct GlyphShape {
    let path: CGPath      // 字形の輪郭（em = 100、y 上向き）
    let bbox: CGRect
    let special: Bool     // 句読点・括弧・長音・小書きかな：字面枠どおりの位置に置く
    let small: Bool       // 小書きかな
    let vertical: Bool
    let contours: [[CGPoint]]  // 輪郭を 1 単位おきの点列にしたもの
    let normals: [[CGPoint]]   // 各点の外向き法線（墨の外側へ）
    let caps: [[Double]]       // 各点が画の端（起筆・終筆）にどれだけ近いか 0〜1
}

/// 輪郭を等間隔の点列にし、外向き法線と「画の端らしさ」を求める。
/// 画の端は、輪郭が短い区間で 180° 近く折り返すところ（線の幅ほどの間に向きが反転する）。
func outlineData(_ path: CGPath) -> ([[CGPoint]], [[CGPoint]], [[Double]]) {
    var raw: [[CGPoint]] = []
    var cur: [CGPoint] = []
    path.flattened(threshold: 0.2).applyWithBlock { ep in
        let e = ep.pointee
        switch e.type {
        case .moveToPoint:
            if cur.count > 2 { raw.append(cur) }
            cur = [e.points[0]]
        case .addLineToPoint:
            cur.append(e.points[0])
        case .closeSubpath:
            if cur.count > 2 { raw.append(cur) }
            cur = []
        default:
            break
        }
    }
    if cur.count > 2 { raw.append(cur) }
    // 弧長 1 単位ごとに打ち直す
    let step: CGFloat = 1.0
    var contours: [[CGPoint]] = []
    for c in raw {
        var pts = c
        if let f = pts.first, let l = pts.last, hypot(f.x - l.x, f.y - l.y) < 1e-3 { pts.removeLast() }
        if pts.count < 3 { continue }
        var out: [CGPoint] = [pts[0]]
        var carry: CGFloat = 0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let len = hypot(b.x - a.x, b.y - a.y)
            if len < 1e-6 { continue }
            var t = step - carry
            while t <= len {
                out.append(CGPoint(x: a.x + (b.x - a.x) * t / len, y: a.y + (b.y - a.y) * t / len))
                t += step
            }
            carry = len - (t - step)
        }
        if out.count > 1, let l = out.last, hypot(l.x - out[0].x, l.y - out[0].y) < step * 0.5 { out.removeLast() }
        if out.count >= 4 { contours.append(out) }
    }
    // 向き：最も大きい輪郭の符号付き面積で、墨が進行方向の左右どちらにあるかを決める
    func area(_ c: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in 0..<c.count { let p = c[i], q = c[(i + 1) % c.count]; a += p.x * q.y - q.x * p.y }
        return a / 2
    }
    let main = contours.max(by: { abs(area($0)) < abs(area($1)) }).map { area($0) } ?? 1
    let inkLeft = main > 0
    var normals: [[CGPoint]] = [], caps: [[Double]] = []
    for c in contours {
        let n = c.count
        var tang = [CGPoint](repeating: .zero, count: n)
        var nor = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let a = c[(i - 1 + n) % n], b = c[(i + 1) % n]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(1e-6, hypot(dx, dy))
            tang[i] = CGPoint(x: dx / l, y: dy / l)
            nor[i] = inkLeft ? CGPoint(x: tang[i].y, y: -tang[i].x) : CGPoint(x: -tang[i].y, y: tang[i].x)
        }
        // 前後 4 単位の接線のなす角が 115° を超えるところを画の端とみなす
        let k = 4
        var score = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = tang[(i - k + n * 4) % n], b = tang[(i + k) % n]
            let ang = acos(Double(max(-1, min(1, a.x * b.x + a.y * b.y))))
            score[i] = max(0, min(1, (ang - 2.0) / 0.9))
        }
        var cap = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var m = 0.0
            for j in -6...6 { m = max(m, score[(i + j + n * 4) % n] * (1 - Double(abs(j)) / 8)) }
            cap[i] = m
        }
        normals.append(nor); caps.append(cap)
    }
    return (contours, normals, caps)
}

let SMALL_KANA: Set<Character> = Set("ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ")
let SPECIAL_CHARS: Set<Character> = Set("。、，．・：；「」『』（）［］【】〔〕〈〉《》ー―－…‥〜～").union(SMALL_KANA)

final class GlyphSource {
    let font: CTFont
    let name: String
    var cache: [String: GlyphShape] = [:]
    var missing: Set<String> = []
    var ref = CGPoint(x: 50, y: 38)   // 漢字の墨の中心（字面枠に置く字の基準）

    init(names: [String]) {
        var chosen: CTFont? = nil
        for n in names {
            let f = CTFontCreateWithName(n as CFString, 100, nil)
            if (CTFontCopyPostScriptName(f) as String) == n { chosen = f; break }
        }
        font = chosen ?? CTFontCreateWithName("HiraMinProN-W3" as CFString, 100, nil)
        name = CTFontCopyPostScriptName(font) as String
        var xs = 0.0, ys = 0.0, k = 0.0
        for c in ["国", "田", "回", "日", "口", "語"] {
            if let g = shape(c, vertical: false) { xs += Double(g.bbox.midX); ys += Double(g.bbox.midY); k += 1 }
        }
        if k > 0 { ref = CGPoint(x: xs / k, y: ys / k) }
    }

    func shape(_ s: String, vertical: Bool) -> GlyphShape? {
        let key = (vertical ? "v" : "h") + s
        if let g = cache[key] { return g }
        if missing.contains(key) { return nil }
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTVerticalFormsAttributeName: vertical]
        let astr = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(astr)
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let n = CTRunGetGlyphCount(run)
            if n == 0 { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            let ra = CTRunGetAttributes(run) as NSDictionary
            let rf = (ra[kCTFontAttributeName as String] as! CTFont?) ?? font
            for i in 0..<n {
                if let gp = CTFontCreatePathForGlyph(rf, glyphs[i], nil) {
                    path.addPath(gp, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
                }
            }
        }
        if path.isEmpty { missing.insert(key); return nil }
        let ch = s.first!
        let (contours, normals, caps) = outlineData(path)
        let g = GlyphShape(path: path, bbox: path.boundingBoxOfPath, special: SPECIAL_CHARS.contains(ch),
                           small: SMALL_KANA.contains(ch), vertical: vertical,
                           contours: contours, normals: normals, caps: caps)
        cache[key] = g
        return g
    }
}

/// 1字ごとの字形の崩し（字形座標 em=100）。
///   ・低い周波数のなめらかな歪み（字全体がゆがむ、振幅 3〜5%）
///   ・字面の四隅を別々に動かす双一次ゆがみ（縦横のつり合いが変わる）
///   ・短い波長の揺れ（線が少し曲がる）
struct Warp {
    var f: [Double] = [], p: [Double] = []
    var lf: [Double] = [], lp: [Double] = []
    var corner: [(Double, Double)] = []
    let amp: Double, lowAmp: Double
    init(_ rng: inout RNG, amp: Double, cornerAmp: Double, lowAmp: Double) {
        self.amp = amp; self.lowAmp = lowAmp
        for _ in 0..<6 { f.append(2 * .pi / rng.r(18, 44)); p.append(rng.r(0, 2 * .pi)) }
        for _ in 0..<4 { lf.append(2 * .pi / rng.r(70, 150)); lp.append(rng.r(0, 2 * .pi)) }
        for _ in 0..<4 { corner.append((rng.r(-cornerAmp, cornerAmp), rng.r(-cornerAmp, cornerAmp))) }
    }
    func map(_ x: Double, _ y: Double) -> CGPoint {
        let dx = sin(x * f[0] + p[0]) * cos(y * f[1] + p[1]) + 0.5 * sin((x + y) * f[2] + p[2])
        let dy = cos(x * f[3] + p[3]) * sin(y * f[4] + p[4]) + 0.5 * cos((x - y) * f[5] + p[5])
        let lx = sin(y * lf[0] + lp[0]) + 0.6 * sin(x * lf[1] + lp[1])
        let ly = sin(x * lf[2] + lp[2]) + 0.6 * sin(y * lf[3] + lp[3])
        let u = max(0, min(1, x / 100)), v = max(0, min(1, (y + 12) / 100))
        let bx = corner[0].0 * (1 - u) * (1 - v) + corner[1].0 * u * (1 - v) + corner[2].0 * (1 - u) * v + corner[3].0 * u * v
        let by = corner[0].1 * (1 - u) * (1 - v) + corner[1].1 * u * (1 - v) + corner[2].1 * (1 - u) * v + corner[3].1 * u * v
        return CGPoint(x: x + amp * dx / 1.5 + lowAmp * lx / 1.6 + bx, y: y + amp * dy / 1.5 + lowAmp * ly / 1.6 + by)
    }
}

/// 字形を手書きらしく作り直す：輪郭を法線方向に押し広げて線の太さを変え（画の端は太く、
/// 途中は筆圧のむらで太細）、そのあと全体を歪める。
func handPath(_ g: GlyphShape, warp: Warp, weight: Double, weightVar: Double, capBoost: Double, noiseSeed: UInt32) -> CGPath {
    let out = CGMutablePath()
    for (ci, c) in g.contours.enumerated() {
        let nor = g.normals[ci], cap = g.caps[ci]
        var pts: [CGPoint] = []
        pts.reserveCapacity(c.count)
        for i in 0..<c.count {
            let p = c[i]
            let press = Double(vnoise(Float(p.x) / 22, Float(p.y) / 22, noiseSeed)) * 2 - 1
            let d = max(-0.6, weight + weightVar * press + capBoost * cap[i])
            let q = warp.map(Double(p.x + nor[i].x * CGFloat(d)), Double(p.y + nor[i].y * CGFloat(d)))
            pts.append(q)
        }
        out.addLines(between: pts)
        out.closeSubpath()
    }
    return out
}

// MARK: - 筆跡の個性

struct Style {
    let fontNames: [String]
    let ink: (Double, Double, Double)  // 鉛筆の色（最も濃いところ）
    let pressure: Double               // 筆圧（濃さ）
    let sizeBias: Double
    let sizeJit: Double                // 大きさの揺れ（±割合）
    let rotJit: Double                 // 傾きの揺れ（±度）
    let posJit: Double                 // 位置の揺れ（マスに対する±割合）
    let slant: Double                  // 傾きのくせ（度）
    let slantDrift: Double             // 書き進むうちに傾きが変わる幅（±度）
    let rise: Double                   // 横画の右上がり（x 1 に対する y の上がり）
    let thicken: Double                // 輪郭に足す細線（mm）
    let weight: Double                 // 線を太らせる量（em=100 に対して、片側）
    let weightVar: Double              // 筆圧による太さのむら（同上、±）
    let capBoost: Double               // 起筆・終筆を太らせる量（同上）
    let wobble: Double                 // 短い波長の線の揺れ（同上）
    let corner: Double                 // 字形のつり合いの崩し（同上）
    let lowWarp: Double                // 字全体のなめらかな歪み（同上）
}

func styleFor(student: Int) -> Style {
    if student % 2 == 1 {
        // 1人目：比較的ていねい
        return Style(fontNames: ["Klee-Medium", "YuKyokasho-Medium", "YuKyo-Medium", "HiraMinProN-W3"],
                     ink: (0.17, 0.17, 0.20), pressure: 0.97, sizeBias: 1.0, sizeJit: 0.09, rotJit: 3.5, posJit: 0.065,
                     slant: -0.6, slantDrift: 0.8, rise: 0.05, thicken: 0.04,
                     weight: 0.55, weightVar: 0.55, capBoost: 1.1, wobble: 1.8, corner: 2.8, lowWarp: 3.5)
    } else {
        // 2人目：やや雑
        return Style(fontNames: ["Klee-Demibold", "YuKyokasho-Bold", "YuKyo-Bold", "HiraMinProN-W6"],
                     ink: (0.22, 0.22, 0.25), pressure: 0.90, sizeBias: 0.96, sizeJit: 0.11, rotJit: 4.5, posJit: 0.075,
                     slant: 1.0, slantDrift: 1.5, rise: 0.08, thicken: 0.03,
                     weight: 0.25, weightVar: 0.7, capBoost: 1.3, wobble: 2.4, corner: 3.6, lowWarp: 4.8)
    }
}

// MARK: - 字を書く

struct Placed {
    let page: Int
    let label: String
    let ch: String
    let cell: MMRect
    let allowed: MMRect
    let bbox: CGRect
    let ghost: Bool
    var hang = false      // 行頭禁則で前の行の最後のマスに入れた句読点
    var fitted = false    // 揺れの結果はみ出しそうになり、縮小・移動して収めた字
}

/// 1字を mm 座標の文脈に描く。墨の外接矩形（mm）と、収めるために縮小・移動したかを返す。
///   inkCentered: 字面枠ではなく墨の中心をマスの中心に置く（ぶら下げの句読点用）
func drawGlyph(_ ctx: CGContext, shape: GlyphShape, src: GlyphSource, slot: MMRect, allowed: MMRect,
               em: Double, style: Style, rng: inout RNG, drift: (Double, Double), slantOffset: Double,
               alpha: Double, ghost: Bool, inkCentered: Bool = false) -> (CGRect, Bool) {
    // 1字ごとの揺れ：大きさ・縦横比・傾き・位置・横画の右上がり
    let size = style.sizeBias * (1 + style.sizeJit * rng.r(-1, 1))
    let sx = 1 + 0.04 * rng.r(-1, 1), sy = 1 + 0.04 * rng.r(-1, 1)
    let rotMax = style.rotJit + 0.5
    let theta = max(-rotMax, min(rotMax, style.slant * 0.5 + slantOffset + rng.r(-style.rotJit, style.rotJit))) * .pi / 180
    let special = shape.special && !inkCentered
    let rise = special ? 0 : style.rise * rng.r(0.3, 1.5)
    let ox = style.posJit * slot.w * rng.r(-1, 1) + drift.0
    let oy = style.posJit * slot.h * rng.r(-1, 1) + drift.1
    var anchor = special ? src.ref : CGPoint(x: shape.bbox.midX, y: shape.bbox.midY)
    if special && shape.small && shape.vertical { anchor.y -= 10 }   // 縦書きの小書きかなはマスの右上寄りに
    let warp = Warp(&rng, amp: style.wobble, cornerAmp: special ? style.corner * 0.4 : style.corner,
                    lowAmp: special ? style.lowWarp * 0.4 : style.lowWarp)
    let shaped = handPath(shape, warp: warp, weight: style.weight, weightVar: style.weightVar,
                          capBoost: style.capBoost * rng.r(0.5, 1.3), noiseSeed: UInt32(truncatingIfNeeded: rng.next()))

    // 鉛筆らしい重ね描きのずれ量（mm）
    let w1 = style.thicken * rng.r(0.7, 1.3)
    let o2 = (rng.r(-0.07, 0.07), rng.r(-0.07, 0.07)), w2 = rng.r(0.04, 0.10)
    let o3 = (rng.r(-0.08, 0.08), rng.r(-0.08, 0.08))
    var spread = max(w1 / 2, max(abs(o2.0), abs(o2.1)) + w2 / 2, max(abs(o3.0), abs(o3.1))) + 0.04
    if ghost { spread = max(spread, 0.34) }

    let target = allowed.inset(spread, spread)
    var c = CGPoint(x: slot.cx + ox, y: slot.cy + oy)
    var gs = em * size / 100.0
    var t = CGAffineTransform.identity
    var p: CGPath = shaped
    var fitted = false
    for _ in 0..<10 {
        // 字形座標（y上向き）→ 基準点を原点へ → 右上がりのずれ → 拡大と上下反転 → 回転 → マスの中心へ
        t = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(a: 1, b: CGFloat(rise), c: 0, d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(scaleX: CGFloat(gs * sx), y: CGFloat(-gs * sy)))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(theta)))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        p = shaped.copy(using: &t) ?? shaped
        let bb = p.boundingBoxOfPath
        if target.contains(bb) { break }
        fitted = true
        let fit = min(target.w / Double(bb.width), target.h / Double(bb.height))
        if fit < 1 { gs *= fit * 0.985; continue }
        var dx = 0.0, dy = 0.0
        if Double(bb.minX) < target.x0 { dx = target.x0 - Double(bb.minX) } else if Double(bb.maxX) > target.x1 { dx = target.x1 - Double(bb.maxX) }
        if Double(bb.minY) < target.y0 { dy = target.y0 - Double(bb.minY) } else if Double(bb.maxY) > target.y1 { dy = target.y1 - Double(bb.maxY) }
        c.x += dx * 1.001; c.y += dy * 1.001
    }
    let bb = p.boundingBoxOfPath

    if ghost {
        // 消した跡：薄く、こすれて広がった字
        ctx.setFillColor(gray: 1, alpha: alpha * 0.17)
        ctx.addPath(p); ctx.fillPath()
        for _ in 0..<3 {
            var tt = CGAffineTransform(translationX: rng.r(-0.28, 0.28), y: rng.r(-0.28, 0.28))
            if let q = p.copy(using: &tt) { ctx.setFillColor(gray: 1, alpha: alpha * 0.06); ctx.addPath(q); ctx.fillPath() }
        }
    } else {
        let a1 = alpha
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        // 1回目：太さを変えた輪郭を塗る（細い線でわずかに縁をやわらげる）
        ctx.setFillColor(gray: 1, alpha: a1)
        ctx.setStrokeColor(gray: 1, alpha: a1)
        ctx.setLineWidth(w1)
        ctx.addPath(p); ctx.drawPath(using: .fillStroke)
        // 2回目：わずかにずらした細線（線の縁のむら）
        var t2 = CGAffineTransform(translationX: o2.0, y: o2.1)
        if let q = p.copy(using: &t2) {
            ctx.setStrokeColor(gray: 1, alpha: a1 * 0.5); ctx.setLineWidth(w2)
            ctx.addPath(q); ctx.strokePath()
        }
        // 3回目：薄い重ね塗り（鉛筆の二度なぞり）
        var t3 = CGAffineTransform(translationX: o3.0, y: o3.1)
        if let q = p.copy(using: &t3) {
            ctx.setFillColor(gray: 1, alpha: a1 * 0.28); ctx.addPath(q); ctx.fillPath()
        }
    }
    return (bb.insetBy(dx: -CGFloat(spread - 0.04), dy: -CGFloat(spread - 0.04)), fitted)
}

/// 解答文字列を字の並びにする（"\n" は改行、"　" は1マス空け）
func tokenize(_ text: String, kind: Kind) -> [String] {
    var out: [String] = []
    // 前後の改行・半角空白は捨てる（全角スペースの字下げは残す）
    let t = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n"))
    for ch in t {
        if ch == "\n" { if kind == .ruled || kind == .grid { out.append("\n") }; continue }
        if ch == " " || ch == "\t" { continue }
        if ch == "　" { if kind != .kanji { out.append("　") }; continue }
        var s = String(ch)
        if let sc = s.unicodeScalars.first, s.unicodeScalars.count == 1, sc.value >= 0x21, sc.value <= 0x7E {
            s = String(UnicodeScalar(sc.value + 0xFEE0)!)
        }
        out.append(s)
    }
    return out
}

/// 行頭に来てはいけない句読点
let LINE_START_NG: Set<String> = ["、", "。", "，", "．"]

struct Item {
    var ch: String
    var col: Int
    var row: Int
    var hang = false   // 前の行の最後のマスに、その字と一緒に入れた句読点
}

/// 字をスロットに割り付ける。戻り値：字の並びと、入りきらなかった字。
/// 行頭禁則：、。が行（列）の先頭に来るとき
///   ・前の行に空きがあれば（"\n" で改行した直後）、前の行のその字の次のマスへ
///   ・マス目：前の行の最後のマスに、その行の最後の字と一緒に入れる（右下にぶら下げ）
///   ・縦罫：前の行の最後の字を次の行へ送り、その下に続ける（追い出し）
///   ・最後の行の末尾の後（容量ちょうどで、、。が余る）は、マス目・縦罫とも最後のマスにぶら下げる
func assign(_ tokens: [String], slots: [[MMRect]], kind: Kind) -> ([Item], [String]) {
    var res: [Item] = []
    var col = 0, row = 0
    var overflow: [String] = []
    for tk in tokens {
        if !overflow.isEmpty { if tk != "\n" { overflow.append(tk) }; continue }
        if tk == "\n" {
            if row > 0 { col += 1; row = 0 }
            continue
        }
        while col < slots.count && row >= slots[col].count { col += 1; row = 0 }
        if LINE_START_NG.contains(tk) && (kind == .grid || kind == .ruled) && row == 0 && col > 0,
           let li = res.indices.last, !res[li].hang, res[li].col == col - 1 {
            let prevRow = res[li].row, prevLen = slots[col - 1].count
            if prevRow < prevLen - 1 {
                res.append(Item(ch: tk, col: col - 1, row: prevRow + 1))
                continue
            }
            if kind == .ruled && col < slots.count && slots[col].count >= 2 {
                res[li].col = col; res[li].row = 0
                res.append(Item(ch: tk, col: col, row: 1))
                row = 2
                continue
            }
            res.append(Item(ch: tk, col: col - 1, row: prevRow, hang: true))
            continue
        }
        if col >= slots.count { overflow.append(tk); continue }
        if tk != "　" { res.append(Item(ch: tk, col: col, row: row)) }
        row += 1
    }
    return (res, overflow)
}

/// 1つの欄を書く
func drawField(_ ctx: CGContext, field f: Field, text: String, style: Style, src: GlyphSource,
               rng: inout RNG, smudge: Bool, placed: inout [Placed]) {
    let vertical = f.kind != .horizontal
    let slots = layoutSlots(f)
    var tokens = tokenize(text, kind: f.kind)
    if f.kind == .kanji {
        let cap = slots[0].count
        if tokens.count > cap {
            warn("警告: 「\(f.label)」は漢字枠で\(cap)字までです。「\(tokens.joined())」の末尾「\(tokens[cap...].joined())」を切り捨てました。")
            tokens = Array(tokens[0..<cap])
        }
    }
    let (items, overflow) = assign(tokens, slots: slots, kind: f.kind)
    if !overflow.isEmpty {
        let cap = slots.reduce(0) { $0 + $1.count }
        warn("警告: 「\(f.label)」は最大\(cap)字です。入りきらない末尾\(overflow.count)字「\(overflow.joined())」を切り捨てました。")
    }
    if items.isEmpty { return }
    // ぶら下げの句読点が入るマス
    let hangCells = Set(items.filter { $0.hang }.map { $0.col * 1000 + $0.row })

    // 行ごとのゆらぎ（横方向のふらつきと筆圧の変化）
    var colPhase: [Double] = [], colAmp: [Double] = [], colPress: [Double] = []
    for c in slots.indices {
        colPhase.append(rng.r(0, 2 * .pi))
        colAmp.append(0.045 * (slots[c].first?.w ?? 8) * rng.r(0.6, 1.0))
        colPress.append(rng.r(0.93, 1.0))
    }
    var walk = 0.0

    // 消し跡：消しゴムでこすった薄い黒ずみと、先に書いて消した字の薄い残り
    if smudge {
        let n = min(items.count, Int(rng.r(6, 12)))
        let shift = max(1, min(items.count - 1, Int(rng.r(2, 5))))
        // こすれる範囲：縦罫は行の中（罫線から離す）、マス目・漢字枠はマスの中
        var regions: [MMRect] = []
        if f.kind == .ruled {
            var byCol: [Int: (Int, Int)] = [:]
            for it in items.prefix(n) { let v = byCol[it.col] ?? (it.row, it.row); byCol[it.col] = (min(v.0, it.row), max(v.1, it.row)) }
            for (c, (r0, r1)) in byCol.sorted(by: { $0.key < $1.key }) {
                let a = slots[c][r0], b = slots[c][r1]
                regions.append(R(a.x0 + COL_CLEAR + 0.1, a.y0 + 0.2, a.x1 - COL_CLEAR - 0.1, b.y1 - 0.2))
            }
        } else {
            regions = Array(Set(items.prefix(n).map { $0.col * 1000 + $0.row })).sorted().map {
                allowedRect(f, slots[$0 / 1000][$0 % 1000]).inset(0.1, 0.1) }
        }
        ctx.saveGState()
        ctx.clip(to: regions.map { $0.cg })
        let gray = CGColorSpaceCreateDeviceGray()
        for reg in regions {
            let k = max(2, Int(reg.h / 3))
            for _ in 0..<k {
                let ew = reg.w * rng.r(0.55, 1.0)
                let eh = min(reg.h, reg.w * rng.r(0.9, 2.6))
                let ex = reg.x0 + rng.u() * (reg.w - ew), ey = reg.y0 + rng.u() * (reg.h - eh)
                let a = rng.r(0.06, 0.11)
                let grad = CGGradient(colorsSpace: gray, colors: [CGColor(gray: 1, alpha: a), CGColor(gray: 1, alpha: a * 0.45),
                                                                    CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.55, 1])!
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(ex + ew / 2), y: CGFloat(ey + eh / 2))
                ctx.scaleBy(x: CGFloat(ew / 2), y: CGFloat(eh / 2))
                ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                ctx.restoreGState()
            }
            // 消しゴムの往復でできる、行に沿った薄いすじ
            ctx.setLineCap(.round)
            for _ in 0..<Int(rng.r(2, 5)) {
                let x = reg.x0 + 0.4 + rng.u() * max(0.1, reg.w - 0.8)
                let y0 = reg.y0 + 0.4 + rng.u() * reg.h * 0.4
                let y1 = min(reg.y1 - 0.4, y0 + reg.h * rng.r(0.3, 0.6))
                ctx.setStrokeColor(gray: 1, alpha: rng.r(0.04, 0.08)); ctx.setLineWidth(rng.r(0.25, 0.6))
                ctx.move(to: CGPoint(x: x, y: y0)); ctx.addLine(to: CGPoint(x: x + rng.r(-0.3, 0.3), y: y1)); ctx.strokePath()
            }
            placed.append(Placed(page: f.page, label: f.label, ch: "（こすれ）", cell: reg, allowed: reg, bbox: reg.cg, ghost: true))
        }
        for k in 0..<n where !items[k].hang {
            let it = items[k]
            let slot = slots[it.col][it.row]
            let ghostChar = items[(k + shift) % items.count].ch
            guard let g = src.shape(ghostChar, vertical: vertical) else { continue }
            let al = allowedRect(f, slot)
            let (bb, _) = drawGlyph(ctx, shape: g, src: src, slot: slot, allowed: al, em: emSize(f, slot), style: style,
                                    rng: &rng, drift: (rng.r(-0.3, 0.3), rng.r(-0.3, 0.3)), slantOffset: 0,
                                    alpha: style.pressure, ghost: true)
            placed.append(Placed(page: f.page, label: f.label, ch: ghostChar, cell: slot, allowed: al, bbox: bb, ghost: true))
        }
        ctx.restoreGState()
    }

    // 書き進むうちに傾きのくせが少しずつ変わる
    var slantWalk = rng.r(-1, 1) * style.slantDrift
    for (i, it) in items.enumerated() {
        let (ch, c, r) = (it.ch, it.col, it.row)
        let cell = slots[c][r]
        guard let g = src.shape(ch, vertical: vertical) else {
            warn("警告: 「\(f.label)」の字「\(ch)」の字形が見つからないので空けました。")
            continue
        }
        walk = max(-1, min(1, walk + rng.r(-0.25, 0.25)))
        slantWalk = max(-style.slantDrift, min(style.slantDrift, slantWalk + rng.r(-0.35, 0.35)))
        let along = Double(r)
        let wander = colAmp[c] * (0.7 * sin(along * 0.42 + colPhase[c]) + 0.3 * walk)
        var drift: (Double, Double) = vertical ? (wander, 0) : (0, wander * 0.6)
        let press = style.pressure * colPress[c] * rng.r(0.88, 1.0) * (0.96 + 0.04 * sin(Double(i) * 0.3))
        let al = allowedRect(f, cell)
        var slot = cell, area = al, em = emSize(f, cell), inkCentered = false
        if it.hang {
            // ぶら下げの句読点：マスの右下 36% の範囲に、墨の中心を合わせて置く
            slot = R(cell.x1 - 0.36 * cell.w, cell.y1 - 0.36 * cell.h, cell.x1, cell.y1)
            area = R(max(al.x0, slot.x0), max(al.y0, slot.y0), al.x1, al.y1)
            inkCentered = true; drift = (0, 0)
        } else if hangCells.contains(c * 1000 + r) {
            // 句読点がぶら下がるマスの字：少し小さくして左上に寄せる
            slot = R(cell.x0, cell.y0, cell.x1 - 0.24 * cell.w, cell.y1 - 0.24 * cell.h)
            area = R(al.x0, al.y0, al.x1 - 0.24 * cell.w, al.y1 - 0.24 * cell.h)
            em *= 0.84; drift = (0, 0)
        }
        let (bb, fitted) = drawGlyph(ctx, shape: g, src: src, slot: slot, allowed: area, em: em, style: style,
                                     rng: &rng, drift: drift, slantOffset: slantWalk, alpha: press, ghost: false,
                                     inkCentered: inkCentered)
        placed.append(Placed(page: f.page, label: f.label, ch: ch, cell: cell, allowed: area, bbox: bb, ghost: false,
                             hang: it.hang, fitted: fitted))
    }
}

// MARK: - 画素バッファ

final class Bitmap {
    let w: Int, h: Int, bpr: Int, comps: Int
    let data: UnsafeMutablePointer<UInt8>
    let ctx: CGContext
    init(w: Int, h: Int, gray: Bool) {
        self.w = w; self.h = h
        comps = gray ? 1 : 4
        bpr = w * comps
        data = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
        data.initialize(repeating: 0, count: bpr * h)
        if gray {
            ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        } else {
            ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        }
    }
    deinit { data.deallocate() }
    func image() -> CGImage { ctx.makeImage()! }
}

/// PDFページを w×h 画素に描く。用紙の上端を画像の1行目にそろえる（mm の y と画素の行が 0 で一致する）。
func renderPage(_ page: CGPDFPage, box: CGRect, w W: Int, h H: Int, dpi: Double) -> Bitmap {
    let pg = Bitmap(w: W, h: H, gray: false)
    pg.ctx.setFillColor(gray: 1, alpha: 1)
    pg.ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    pg.ctx.translateBy(x: 0, y: CGFloat(Double(H) - Double(box.height) / 72 * dpi))
    pg.ctx.scaleBy(x: CGFloat(dpi / 72), y: CGFloat(dpi / 72))
    pg.ctx.translateBy(x: -box.minX, y: -box.minY)
    pg.ctx.drawPDFPage(page)
    return pg
}

// MARK: - 発行PDFの確認・QR

@inline(__always) func darkness(_ bm: Bitmap, _ x: Int, _ y: Int) -> Int {
    if x < 0 || x >= bm.w || y < 0 || y >= bm.h { return 0 }
    let o = y * bm.bpr + x * 4
    return 255 - Int(min(bm.data[o], bm.data[o + 1], bm.data[o + 2]))
}

/// 発行ページの罫線の位置が見本から全体にどれだけずれているか（mm）。
/// 解答欄の左右の縦線と上下の横線の付近 ±2mm で濃さの山を探し、その中央値をとる。
func measureOffset(_ bm: Bitmap, page: Int, pxPerMM: Double) -> (Double, Double) {
    let reach = Int(2.0 * pxPerMM)
    var dxs: [Double] = [], dys: [Double] = []
    /// mm 位置 pos の付近で線の中心（mm）を探す：濃さの山の、半分以上の幅の重心
    func center(near pos: Double, _ profile: (Int) -> Int) -> Double? {
        let p0 = Int(pos * pxPerMM)
        let vals = (-reach...reach).map { profile(p0 + $0) }
        guard let mx = vals.max(), mx > 0, let im = vals.firstIndex(of: mx) else { return nil }
        var a = im, b = im
        while a > 0 && vals[a - 1] * 2 >= mx { a -= 1 }
        while b < vals.count - 1 && vals[b + 1] * 2 >= mx { b += 1 }
        var sw = 0.0, s = 0.0
        for i in a...b { sw += Double(vals[i]); s += Double(vals[i]) * Double(p0 - reach + i) }
        return (s / sw + 0.5) / pxPerMM
    }
    for f in FIELDS where f.page == page {
        for r in f.rects {
            let ys = stride(from: r.y0 + 3, to: r.y1 - 3, by: 1.5).map { Int($0 * pxPerMM) }
            for x in [r.x0, r.x1] {
                if let c = center(near: x, { px in ys.reduce(0) { $0 + darkness(bm, px, $1) } }) { dxs.append(c - x) }
            }
            let xs = stride(from: r.x0 + 1, to: r.x1 - 1, by: 0.5).map { Int($0 * pxPerMM) }
            for y in [r.y0, r.y1] {
                if let c = center(near: y, { py in xs.reduce(0) { $0 + darkness(bm, $1, py) } }) { dys.append(c - y) }
            }
        }
    }
    func median(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.sorted()[a.count / 2] }
    return (median(dxs), median(dys))
}

/// 発行ページの罫線が見本どおりの位置にあるか（解答欄の左右の縦線と上下の横線を標本点で確かめる）
func layoutHitRate(_ bm: Bitmap, page: Int, pxPerMM: Double, offset: (Double, Double) = (0, 0)) -> Double {
    var hits = 0, total = 0
    func probe(_ xmm: Double, _ ymm: Double, vertical: Bool) {
        let px = Int(((xmm + offset.0) * pxPerMM).rounded(.down)), py = Int(((ymm + offset.1) * pxPerMM).rounded(.down))
        total += 1
        for d in -2...2 where darkness(bm, vertical ? px + d : px, vertical ? py : py + d) > 40 { hits += 1; return }
    }
    for f in FIELDS where f.page == page {
        for r in f.rects {
            for k in 0..<8 {
                let y = r.y0 + 2 + (r.h - 4) * (Double(k) + 0.5) / 8
                probe(r.x0, y, vertical: true); probe(r.x1, y, vertical: true)
            }
            for k in 0..<3 {
                let x = r.x0 + 1 + (r.w - 2) * (Double(k) + 0.5) / 3
                probe(x, r.y0, vertical: false); probe(x, r.y1, vertical: false)
            }
        }
    }
    return total > 0 ? Double(hits) / Double(total) : 0
}

let qrDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

func decodeQR(_ img: CGImage) -> [String] {
    let feats = qrDetector?.features(in: CIImage(cgImage: img)) ?? []
    return feats.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
}

// MARK: - 鉛筆の質感・合成・スキャン風加工

/// インク層に紙の凹凸による粒状感と、かすれを付ける
func applyGrain(_ mk: Bitmap, seed: UInt32, pxPerMM: Double) {
    let s1 = Float(pxPerMM * 0.45), s2 = Float(pxPerMM * 1.5)
    for y in 0..<mk.h {
        let row = mk.data + y * mk.bpr
        for x in 0..<mk.w {
            let m = row[x]
            if m == 0 { continue }
            let a = Float(m) / 255
            let n1 = hash01(x, y, seed)
            let n2 = vnoise(Float(x) / (s1 * 0.7), Float(y) / (s1 * 1.4), seed &+ 17)
            let n3 = vnoise(Float(x) / s2, Float(y) / s2, seed &+ 91)
            var g = (0.58 + 0.42 * n1) * (0.76 + 0.32 * n2)
            if n3 < 0.30 { g *= 0.50 + 1.65 * n3 }
            let v = min(1, a * g * 1.10)
            row[x] = UInt8(max(0, min(255, v * 255)))
        }
    }
}

struct ScanParams { var angleDeg: Double; var shift: (Double, Double); var blur: Bool }

/// 用紙画像にインクを合成し、紙色・傾き・ぼけ・ノイズを加えた最終画像を返す
func scan(page pg: Bitmap, ink mk: Bitmap, inkRGB: (Double, Double, Double), params: ScanParams,
          seed: UInt32, pxPerMM: Double) -> CGImage {
    let w = pg.w, h = pg.h
    // 1) 合成（乗算）と紙の色
    let comp = Bitmap(w: w, h: h, gray: false)
    let tone: (Float, Float, Float) = (0.978, 0.970, 0.950)
    let ir = Float(inkRGB.0), ig = Float(inkRGB.1), ib = Float(inkRGB.2)
    for y in 0..<h {
        let prow = pg.data + y * pg.bpr, mrow = mk.data + y * mk.bpr, crow = comp.data + y * comp.bpr
        for x in 0..<w {
            let a = Float(mrow[x]) / 255
            let o = x * 4
            crow[o] = UInt8(min(255, Float(prow[o]) * tone.0 * (1 - a * (1 - ir))))
            crow[o + 1] = UInt8(min(255, Float(prow[o + 1]) * tone.1 * (1 - a * (1 - ig))))
            crow[o + 2] = UInt8(min(255, Float(prow[o + 2]) * tone.2 * (1 - a * (1 - ib))))
            crow[o + 3] = 255
        }
    }
    // 2) 傾きとずれ（原稿台の上でわずかに曲がった状態）
    let rot = Bitmap(w: w, h: h, gray: false)
    rot.ctx.setFillColor(red: 0.925, green: 0.918, blue: 0.900, alpha: 1)
    rot.ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    rot.ctx.interpolationQuality = .high
    rot.ctx.translateBy(x: CGFloat(Double(w) / 2 + params.shift.0 * pxPerMM), y: CGFloat(Double(h) / 2 - params.shift.1 * pxPerMM))
    rot.ctx.rotate(by: CGFloat(params.angleDeg * .pi / 180))
    rot.ctx.translateBy(x: CGFloat(-w / 2), y: CGFloat(-h / 2))
    rot.ctx.draw(comp.image(), in: CGRect(x: 0, y: 0, width: w, height: h))
    // 3) 軽いぼけ・照明むら・ノイズ
    let out = Bitmap(w: w, h: h, gray: false)
    let src = rot.data, dst = out.data, bpr = rot.bpr
    let fw = Float(w), fh = Float(h)
    for y in 0..<h {
        let ym = max(0, y - 1), yp = min(h - 1, y + 1)
        let shadeY: Float = 1 - SCAN_SHADE * 0.010 * Float(y) / fh
        for x in 0..<w {
            let xm = max(0, x - 1), xp = min(w - 1, x + 1)
            let shade = shadeY * (1 - SCAN_SHADE * 0.016 * Float(x) / fw)
            let n = (hash01(x, y, seed) - 0.5) * SCAN_GRAIN + (vnoise(Float(x) / 37, Float(y) / 37, seed &+ 5) - 0.5) * SCAN_MOTTLE
            for c in 0..<3 {
                var v: Float
                if params.blur {
                    let r0 = ym * bpr, r1 = y * bpr, r2 = yp * bpr
                    let s = Float(src[r0 + xm * 4 + c]) + 2 * Float(src[r0 + x * 4 + c]) + Float(src[r0 + xp * 4 + c])
                        + 2 * Float(src[r1 + xm * 4 + c]) + 4 * Float(src[r1 + x * 4 + c]) + 2 * Float(src[r1 + xp * 4 + c])
                        + Float(src[r2 + xm * 4 + c]) + 2 * Float(src[r2 + x * 4 + c]) + Float(src[r2 + xp * 4 + c])
                    // 二項フィルタを原画に少し混ぜた軽いぼけ
                    v = (1 - SCAN_BLUR) * Float(src[r1 + x * 4 + c]) + SCAN_BLUR * s / 16
                } else {
                    v = Float(src[y * bpr + x * 4 + c])
                }
                v = v * shade + n + (c == 2 ? -0.6 : 0.3)
                dst[y * bpr + x * 4 + c] = UInt8(max(0, min(255, v.rounded())))
            }
            dst[y * bpr + x * 4 + 3] = 255
        }
    }
    return out.image()
}

func jpegData(_ img: CGImage, quality: Double) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return data as Data
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    if let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

// MARK: - 入力JSON

struct StudentInput {
    var name = ""
    var klass = ""
    var answers: [String: String] = [:]
    var smudges: Set<String> = []
}

let LABELS = FIELDS.map { $0.label }

func normLabel(_ s: String) -> String {
    var t = s.filter { !$0.isWhitespace }
    t = t.replacingOccurrences(of: "(", with: "（").replacingOccurrences(of: ")", with: "）")
    let kan = ["一", "二", "三", "四", "五", "六"]
    for (i, k) in kan.enumerated() {
        let d = String(i + 1), fd = String(UnicodeScalar(0xFF11 + UInt32(i))!)
        for dd in [d, fd] {
            t = t.replacingOccurrences(of: "第\(dd)問", with: "第\(k)問")
            t = t.replacingOccurrences(of: "（\(dd)）", with: "（\(k)）")
        }
    }
    t = t.replacingOccurrences(of: "ａ", with: "a").replacingOccurrences(of: "ｂ", with: "b").replacingOccurrences(of: "ｃ", with: "c")
    t = t.replacingOccurrences(of: "A", with: "a").replacingOccurrences(of: "B", with: "b").replacingOccurrences(of: "C", with: "c")
    return t
}

func textValue(_ v: Any) -> String? {
    if let s = v as? String { return s }
    if let a = v as? [Any] { return a.compactMap { textValue($0) }.joined(separator: "\n") }
    if let n = v as? NSNumber { return n.stringValue }
    if v is NSNull { return "" }
    return nil
}

func loadStudents(_ path: String) -> [StudentInput] {
    guard let data = FileManager.default.contents(atPath: path) else { fail("解答JSONを読めません: \(path)") }
    let obj: Any
    do { obj = try JSONSerialization.jsonObject(with: data) } catch { fail("解答JSONの形式が正しくありません: \(error.localizedDescription)") }
    var arr: [[String: Any]] = []
    if let d = obj as? [String: Any] {
        if let a = (d["答案"] ?? d["students"]) as? [[String: Any]] { arr = a }
        else { fail("解答JSONの最上位に \"答案\": [ {…1人目…}, {…2人目…} ] がありません。") }
    } else if let a = obj as? [[String: Any]] { arr = a }
    else { fail("解答JSONの最上位は {\"答案\": [...]} にしてください。") }
    let meta: Set<String> = ["氏名", "科類", "消し跡", "番号", "解答", "name", "answers", "smudges"]
    var out: [StudentInput] = []
    var unknown: [String] = []
    for (i, s) in arr.enumerated() {
        var st = StudentInput()
        st.name = (s["氏名"] ?? s["name"]).flatMap { textValue($0) } ?? ""
        st.klass = (s["科類"]).flatMap { textValue($0) } ?? ""
        var ans: [String: Any] = [:]
        if let a = (s["解答"] ?? s["answers"]) as? [String: Any] { ans = a }
        else { for (k, v) in s where !meta.contains(k) { ans[k] = v } }
        for (k, v) in ans {
            let nk = normLabel(k)
            guard LABELS.contains(nk) else { unknown.append("\(i + 1)人目「\(k)」"); continue }
            guard let tv = textValue(v) else { fail("\(i + 1)人目「\(k)」の値は文字列にしてください。") }
            st.answers[nk] = tv
        }
        if let sm = (s["消し跡"] ?? s["smudges"]) as? [Any] {
            for x in sm {
                guard let k = textValue(x) else { continue }
                let nk = normLabel(k)
                if LABELS.contains(nk) { st.smudges.insert(nk) } else { unknown.append("\(i + 1)人目の消し跡「\(k)」") }
            }
        }
        out.append(st)
    }
    if !unknown.isEmpty {
        fail("知らないラベルがあります: " + unknown.joined(separator: "、") + "\n使えるラベル: " + LABELS.joined(separator: " "))
    }
    return out
}

// MARK: - --fields

func displayWidth(_ s: String) -> Int { s.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) } }
func pad(_ s: String, _ n: Int) -> String { s + String(repeating: " ", count: max(0, n - displayWidth(s))) }

func printFields() {
    print("東大国語 解答欄一覧（1人3ページ・全\(FIELDS.count)欄）。縦書き、1字＝1マス（句読点も1字）。")
    print(pad("ラベル", 18) + pad("ページ", 8) + "種類と容量")
    for f in FIELDS { print(pad(f.label, 18) + pad("  \(f.page)", 8) + capacityText(f)) }
    let nameCap = layoutSlots(Field(label: "氏名", page: 0, kind: .horizontal, rects: [NAME_BOX]))[0].count
    let classCap = layoutSlots(Field(label: "科類", page: 0, kind: .horizontal, rects: [CLASS_BOX]))[0].count
    print("（省略可）氏名 横書き\(nameCap)字まで・科類 横書き\(classCap)字まで。各ページの上の欄に書く。")
    print("縦罫は1行の字数×行数。\"\\n\" で次の行へ。容量を超えた分は切り捨てて警告する。")
}

// MARK: - メイン

func usage() -> Never {
    warn("""
    使い方:
      swift 手書き答案.swift --fields
      swift 手書き答案.swift <発行PDF> <解答.json> <出力フォルダ> [--seed 64] [--dpi 200] [--debug <フォルダ>]
    """)
    exit(1)
}

var positional: [String] = []
var seedBase: UInt64 = 64
var dpi = 200.0
var debugDir: String? = nil
var showFields = false
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--fields": showFields = true
        case "--seed": guard let v = it.next(), let n = UInt64(v) else { usage() }; seedBase = n
        case "--dpi": guard let v = it.next(), let n = Double(v), n >= 100, n <= 600 else { usage() }; dpi = n
        case "--debug": guard let v = it.next() else { usage() }; debugDir = v
        case "-h", "--help": usage()
        default: positional.append(a)
        }
    }
}

// 解答欄が QR・マーカーの近くにないこと（定義の自己点検）
for f in FIELDS {
    for col in layoutSlots(f) { for s in col { for k in KEEP_OUT where s.intersects(k) { fail("内部エラー: \(f.label) が QR/マーカー領域に重なります", code: 3) } } }
}

if showFields { printFields(); exit(0) }
guard positional.count == 3 else { usage() }
let pdfPath = positional[0], jsonPath = positional[1], outDir = positional[2]

guard let doc = CGPDFDocument(URL(fileURLWithPath: pdfPath) as CFURL) else { fail("発行PDFを開けません: \(pdfPath)") }
let pdfText = PDFDocument(url: URL(fileURLWithPath: pdfPath))   // 見出し（第一問 など）と冊子番号の確認用
let PAGE_HEADERS = [1: ["第一問"], 2: ["第二問", "第三問"], 3: ["第四問"]]
let students = loadStudents(jsonPath)
if students.isEmpty { fail("解答JSONに答案がありません。") }
let pageCount = doc.numberOfPages
if pageCount < 3 * students.count {
    fail("発行PDFは\(pageCount)ページですが、答案は\(students.count)人分（\(3 * students.count)ページ必要）あります。")
}
if pageCount > 3 * students.count {
    warn("注意: 発行PDFは\(pageCount / 3)人分ありますが、解答JSONは\(students.count)人分なので、先頭の\(students.count)人分だけ作ります。")
}
do { try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) }
catch { fail("出力フォルダを作れません: \(outDir)") }
if let d = debugDir { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }

let pxPerMM = dpi / 25.4
var totalGlyphs = 0, totalGhosts = 0, badGlyphs = 0, qrOK = 0, qrPages = 0, totalFitted = 0, totalHang = 0
var debugLayout: [[String: Any]] = []
var pageOffsets: [String: [Double]] = [:]

for (si, st) in students.enumerated() {
    let sn = si + 1
    let style = styleFor(student: sn)
    let src = GlyphSource(names: style.fontNames)
    if !src.name.hasPrefix("Klee") { warn("注意: Klee が見つからないので \(src.name) で書きます。") }
    let outPath = (outDir as NSString).appendingPathComponent(String(format: "答案_%02d.pdf", sn))
    var mediaBox = CGRect(x: 0, y: 0, width: 841.89, height: 595.28)
    var pagesOut: [Data] = []
    var studentPlaced: [Placed] = []

    for p in 1...3 {
        guard let page = doc.page(at: 3 * si + p) else { fail("発行PDFの\(3 * si + p)ページを読めません。") }
        let box = page.getBoxRect(.mediaBox)
        mediaBox = CGRect(x: 0, y: 0, width: box.width, height: box.height)
        if abs(box.width - 841.89) > 3 || abs(box.height - 595.28) > 3 {
            warn("注意: 発行PDFの\(3 * si + p)ページが A4横ではありません（\(Int(box.width))×\(Int(box.height))pt）。")
        }
        let W = Int((Double(box.width) / 72 * dpi).rounded()), H = Int((Double(box.height) / 72 * dpi).rounded())

        // 発行ページを描く
        let pg = renderPage(page, box: box, w: W, h: H, dpi: dpi)

        // 見出しの確認：PDFの文字に「第N問」があれば、ページの順番が合っているかを確かめる。
        // 縦書きの見出しは読み取り順が混ざることがあるので、ページ下の「p/3」が合っていればそれでよしとする
        // （ページの取り違えは、このあとの罫線の照合でも見つかる）。
        let txt = (pdfText?.page(at: 3 * si + p - 1)?.string ?? "").filter { !$0.isWhitespace }
        if txt.contains("問") {
            let need = PAGE_HEADERS[p]!
            if !need.allSatisfy({ txt.contains($0) }) && !txt.contains("\(p)/3") {
                fail("発行PDFの\(3 * si + p)ページに「\(need.joined(separator: "・"))」がありません。\(sn)人目は 3n-2〜3n ページ（1人3ページ）を使います。ページの順番を確認してください。", code: 3)
            }
            if p == 1, let r = txt.range(of: #"B\d{5}"#, options: .regularExpression) {
                print("  \(sn)人目 = 発行PDFの冊子 \(txt[r])（\(3 * si + 1)〜\(3 * si + 3)ページ）")
            }
        }
        // 罫線の位置合わせ：見本からの全体のずれを測り、1画素（約0.13mm）以上ずれていれば解答欄も同じだけ動かす
        var off = measureOffset(pg, page: p, pxPerMM: pxPerMM)
        if abs(off.0) < 0.12 && abs(off.1) < 0.12 { off = (0, 0) }
        let hit = layoutHitRate(pg, page: p, pxPerMM: pxPerMM, offset: off)
        if hit < 0.9 {
            fail("発行PDFの\(3 * si + p)ページの罫線が見本（東大国語 \(p)/3 ページ）と合いません（一致 \(Int(hit * 100))%）。ページの順番か用紙を確認してください。", code: 3)
        }
        if off != (0, 0) {
            print(String(format: "  %d人目 p%d: 罫線が見本から (%+.2f, %+.2f)mm ずれているので、解答欄も合わせて動かします。", sn, p, off.0, off.1))
        }
        pageOffsets["\(sn)_\(p)"] = [off.0, off.1]
        let cleanImg = pg.image()
        let qrClean = decodeQR(cleanImg)

        // 答案を書く（インク層：0=白紙, 255=最も濃い）
        let mk = Bitmap(w: W, h: H, gray: true)
        mk.ctx.translateBy(x: 0, y: CGFloat(H))
        mk.ctx.scaleBy(x: CGFloat(pxPerMM), y: CGFloat(-pxPerMM))
        mk.ctx.translateBy(x: CGFloat(off.0), y: CGFloat(off.1))
        mk.ctx.setShouldAntialias(true)
        var placed: [Placed] = []
        for (fi, f) in FIELDS.enumerated() where f.page == p {
            guard let text = st.answers[f.label], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var rng = RNG(mixSeed([seedBase, UInt64(sn), UInt64(fi), 0xA11]))
            drawField(mk.ctx, field: f, text: text, style: style, src: src, rng: &rng,
                      smudge: st.smudges.contains(f.label), placed: &placed)
        }
        for (k, (v, b)) in [(st.klass, CLASS_BOX), (st.name, NAME_BOX)].enumerated() where !v.isEmpty {
            let f = Field(label: k == 0 ? "科類" : "氏名", page: p, kind: .horizontal, rects: [b])
            var rng = RNG(mixSeed([seedBase, UInt64(sn), UInt64(p), UInt64(k), 0xBEE]))
            drawField(mk.ctx, field: f, text: v, style: style, src: src, rng: &rng, smudge: false, placed: &placed)
        }
        // 自動検査：すべての字の墨の外接矩形が、そのマス（行）の許容範囲に収まっているか
        for g in placed {
            if g.ghost { totalGhosts += 1 } else { totalGlyphs += 1 }
            if g.fitted { totalFitted += 1 }
            if g.hang { totalHang += 1 }
            let hardCell = g.cell
            if !g.allowed.contains(g.bbox) || !hardCell.contains(g.bbox) {
                badGlyphs += 1
                warn("検査NG: \(sn)人目 p\(p) 「\(g.label)」の字「\(g.ch)」が枠からはみ出しています。")
            }
            for k in KEEP_OUT where k.intersects(R(Double(g.bbox.minX), Double(g.bbox.minY), Double(g.bbox.maxX), Double(g.bbox.maxY))) {
                badGlyphs += 1
                warn("検査NG: \(sn)人目 p\(p) 「\(g.label)」が QR/マーカー領域に近すぎます。")
            }
        }
        studentPlaced += placed

        let grainSeed = UInt32(truncatingIfNeeded: mixSeed([seedBase, UInt64(sn), UInt64(p), 0x6A]))
        applyGrain(mk, seed: grainSeed, pxPerMM: pxPerMM)
        if let d = debugDir { writePNG(mk.image(), (d as NSString).appendingPathComponent(String(format: "ink_%02d_p%d.png", sn, p))) }

        // スキャン風に仕上げる（QR が読めなければ、加工を弱めてやり直す）
        var prng = RNG(mixSeed([seedBase, UInt64(sn), UInt64(p), 0x5CA]))
        let angle = (prng.u() < 0.5 ? -1.0 : 1.0) * prng.r(0.08, SCAN_MAX_ANGLE)
        var params = ScanParams(angleDeg: angle, shift: (prng.r(-SCAN_MAX_SHIFT, SCAN_MAX_SHIFT), prng.r(-SCAN_MAX_SHIFT, SCAN_MAX_SHIFT)), blur: true)
        var jpeg = Data()
        var qrText = ""
        for attempt in 0..<3 {
            let img = scan(page: pg, ink: mk, inkRGB: style.ink, params: params,
                           seed: grainSeed &+ UInt32(attempt) &* 7919, pxPerMM: pxPerMM)
            jpeg = jpegData(img, quality: JPEG_QUALITY)
            if qrClean.isEmpty { qrText = "（元のQRをCoreImageで読めないため照合なし）"; break }
            let src2 = CGImageSourceCreateWithData(jpeg as CFData, nil)!
            let dec = decodeQR(CGImageSourceCreateImageAtIndex(src2, 0, nil)!)
            if dec == qrClean { qrText = "QR読取OK"; qrOK += 1; break }
            warn("注意: \(sn)人目 p\(p) の QR が加工後に読めなかったので、加工を弱めて作り直します。")
            params = ScanParams(angleDeg: attempt == 0 ? params.angleDeg * 0.5 : 0, shift: params.shift, blur: false)
            qrText = "QR読取NG"
        }
        if !qrClean.isEmpty { qrPages += 1 }
        pagesOut.append(jpeg)
        print(String(format: "  %d人目 p%d: 傾き %+.2f°  ずれ (%+.1f, %+.1f)mm  字 %d  %@", sn, p, params.angleDeg,
                     params.shift.0, params.shift.1, placed.filter { !$0.ghost }.count, qrText))
    }

    // 画像PDFに書き出す
    let url = URL(fileURLWithPath: outPath) as CFURL
    let info: [CFString: Any] = [kCGPDFContextTitle: String(format: "答案_%02d", sn), kCGPDFContextCreator: "手書き答案.swift"]
    guard let pdf = CGContext(url, mediaBox: &mediaBox, info as CFDictionary) else { fail("出力PDFを作れません: \(outPath)") }
    for jp in pagesOut {
        pdf.beginPDFPage(nil)
        let img = CGImage(jpegDataProviderSource: CGDataProvider(data: jp as CFData)!, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent)!
        pdf.draw(img, in: mediaBox)
        pdf.endPDFPage()
    }
    pdf.closePDF()
    print("書き出し: \(outPath)（3ページ、フォント \(src.name)）")

    if debugDir != nil {
        for g in studentPlaced {
            debugLayout.append(["student": sn, "page": g.page, "label": g.label, "char": g.ch, "ghost": g.ghost,
                                "hang": g.hang, "fitted": g.fitted,
                                "cell": g.cell.json, "allowed": g.allowed.json,
                                "bbox": [Double(g.bbox.minX), Double(g.bbox.minY), Double(g.bbox.maxX), Double(g.bbox.maxY)]])
        }
    }
}

if let d = debugDir {
    let obj: [String: Any] = ["dpi": dpi, "offsets": pageOffsets, "glyphs": debugLayout]
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
        try? data.write(to: URL(fileURLWithPath: (d as NSString).appendingPathComponent("layout.json")))
    }
}

print("検査: 書いた字 \(totalGlyphs) 個（うち行頭禁則のぶら下げ \(totalHang) 個、はみ出し防止で縮小・移動 \(totalFitted) 個）・消し跡 \(totalGhosts) 個のうち枠外 \(badGlyphs) 個 / QR \(qrOK)/\(qrPages) ページ読取OK")
if badGlyphs > 0 || qrOK < qrPages { exit(3) }
