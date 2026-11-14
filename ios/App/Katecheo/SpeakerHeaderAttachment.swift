import UIKit

/// Non-editable speaker section chrome (web `.note-speaker-head`).
///
/// Drawn as an `NSTextAttachment` so the caret cannot enter the name. Hit regions:
/// - chevron → collapse/expand
/// - × → delete section
/// - name / remaining header → rename via speaker picker
///
/// Colors are **hard RGB** for the requested interface style (never dynamic label colors),
/// baked into `.alwaysOriginal` images. `attachmentBounds` must **not** re-bake from
/// ambient process traits — TextKit layout can run under system Dark while the window
/// override is Light, which previously stamped white names onto beige (TF222).
final class SpeakerHeaderAttachment: NSTextAttachment {
    enum Hit: Equatable {
        case toggleCollapse
        case remove
        case rename
    }

    let blockId: String
    var speakerId: String?
    var speakerName: String
    var colorHex: String?
    var collapsed: Bool
    var preview: String

    /// Relative x ranges inside the attachment image (0…1) for hit testing.
    private(set) var chevronEndX: CGFloat = 0.12
    private(set) var removeStartX: CGFloat = 0.88

    /// Last style / width used to bake `image` — drives dirty checks.
    private(set) var renderedInterfaceStyle: UIUserInterfaceStyle = .unspecified
    private(set) var renderedWidth: CGFloat = 0

    init(
        blockId: String,
        speakerId: String?,
        speakerName: String,
        colorHex: String?,
        collapsed: Bool,
        preview: String = "",
        preferredInterfaceStyle: UIUserInterfaceStyle = .unspecified
    ) {
        self.blockId = blockId
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.colorHex = colorHex
        self.collapsed = collapsed
        self.preview = preview
        super.init(data: nil, ofType: nil)
        // Prefer the caller's effective style (text view / window). Offline decode without a
        // view still falls back through Appearance → ambient → light.
        let seed = Self.resolvedBakeStyle(preferred: preferredInterfaceStyle)
        refreshImage(width: 320, traits: Self.bakeTraits(style: seed))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let width = max(lineFrag.width, textContainer?.size.width ?? 300, 120)
        let widthDirty = abs(renderedWidth - width) > 1
        if widthDirty || image == nil {
            // Resize only — keep the last explicit style. Never consult ambient process traits
            // (system Dark + app Light made names white on device; TF214/TF219 tests missed it).
            let style = Self.resolvedBakeStyle(preferred: renderedInterfaceStyle)
            refreshImage(width: width, traits: Self.bakeTraits(style: style))
        }
        let height = image?.size.height ?? 36
        return CGRect(x: 0, y: -6, width: width, height: height)
    }

    func hit(at pointInAttachment: CGPoint) -> Hit {
        let width = max(image?.size.width ?? 1, 1)
        let x = pointInAttachment.x / width
        if x >= removeStartX { return .remove }
        if x <= chevronEndX { return .toggleCollapse }
        return .rename
    }

    /// Rebuild the chrome image for `traits.userInterfaceStyle`.
    /// Name/muted colors are `UIColor.label` / `secondaryLabel` resolved against those traits
    /// (never left as dynamic colors that re-resolve under ambient process traits — TF222).
    func refreshImage(width: CGFloat, traits: UITraitCollection = .current) {
        let w = max(width, 120)
        let style = Self.resolvedBakeStyle(preferred: traits.userInterfaceStyle)
        let height: CGFloat = 44
        let nameFont = KCDesign.preferred(.title3, weight: .semibold)
        let previewFont = KCDesign.preferred(.caption1, weight: .regular)
        let name = speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Speaker")
            : speakerName

        let chevronSize: CGFloat = 10
        let removeVisualSize: CGFloat = 36
        let removeHitSize: CGFloat = 44
        let padL: CGFloat = 4
        let gap: CGFloat = 8

        chevronEndX = (padL + chevronSize + gap) / w
        removeStartX = (w - removeHitSize) / w

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = traits.displayScale > 0 ? traits.displayScale : UIScreen.main.scale
        // Prefer the requested style even if the process-wide current traits are Dark.
        format.preferredRange = .standard

        let bakeTraits = Self.bakeTraits(style: style, scale: format.scale)
        // Resolve once against the bake traits — concrete RGB, safe under ambient Dark layout.
        let nameColor = UIColor.label.resolvedColor(with: bakeTraits)
        let muted = UIColor.secondaryLabel.resolvedColor(with: bakeTraits)
        var baked: UIImage!
        bakeTraits.performAsCurrent {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: height), format: format)
            baked = renderer.image { _ in
                let chevronCenter = CGPoint(x: padL + chevronSize / 2, y: height / 2)
                let path = UIBezierPath()
                let arm: CGFloat = 4.5
                if collapsed {
                    path.move(to: CGPoint(x: chevronCenter.x - 2, y: chevronCenter.y - arm))
                    path.addLine(to: CGPoint(x: chevronCenter.x + 3, y: chevronCenter.y))
                    path.addLine(to: CGPoint(x: chevronCenter.x - 2, y: chevronCenter.y + arm))
                } else {
                    path.move(to: CGPoint(x: chevronCenter.x - arm, y: chevronCenter.y - 2))
                    path.addLine(to: CGPoint(x: chevronCenter.x, y: chevronCenter.y + 3))
                    path.addLine(to: CGPoint(x: chevronCenter.x + arm, y: chevronCenter.y - 2))
                }
                path.lineWidth = 1.6
                muted.setStroke()
                path.stroke()

                let nameX = padL + chevronSize + gap
                let removeX = w - removeVisualSize
                let maxNameW = max(40, removeX - nameX - gap - (collapsed && !preview.isEmpty ? w * 0.35 : 0))

                let nameAttr = NSAttributedString(string: name, attributes: [
                    .font: nameFont,
                    .foregroundColor: nameColor,
                ])
                let nameSize = nameAttr.boundingRect(
                    with: CGSize(width: maxNameW, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    context: nil
                ).integral.size
                let nameRect = CGRect(
                    x: nameX,
                    y: (height - nameSize.height) / 2,
                    width: min(nameSize.width, maxNameW),
                    height: nameSize.height
                )
                nameAttr.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

                if collapsed {
                    let previewText = preview.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !previewText.isEmpty {
                        let previewX = nameRect.maxX + gap
                        let previewW = max(0, removeX - previewX - gap)
                        if previewW > 24 {
                            let previewAttr = NSAttributedString(string: previewText, attributes: [
                                .font: previewFont,
                                .foregroundColor: muted,
                            ])
                            let pSize = previewAttr.boundingRect(
                                with: CGSize(width: previewW, height: height),
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                context: nil
                            ).integral.size
                            let pRect = CGRect(
                                x: previewX,
                                y: (height - pSize.height) / 2,
                                width: min(pSize.width, previewW),
                                height: pSize.height
                            )
                            previewAttr.draw(
                                with: pRect,
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                context: nil
                            )
                        }
                    }
                }

                let xAttr = NSAttributedString(string: "×", attributes: [
                    .font: KCDesign.preferred(.title2, weight: .regular),
                    .foregroundColor: muted,
                ])
                let xSize = xAttr.size()
                let xRect = CGRect(
                    x: removeX + (removeVisualSize - xSize.width) / 2,
                    y: (height - xSize.height) / 2,
                    width: xSize.width,
                    height: xSize.height
                )
                xAttr.draw(in: xRect)
            }
        }

        image = baked.withRenderingMode(.alwaysOriginal)
        bounds = CGRect(x: 0, y: -8, width: w, height: height)
        renderedWidth = w
        renderedInterfaceStyle = style
    }

    /// Hard RGB — never dynamic label/secondary colors (those re-resolve under ambient traits).
    static func palette(for style: UIUserInterfaceStyle) -> (name: UIColor, muted: UIColor) {
        switch style {
        case .dark:
            return (
                UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1),
                UIColor(red: 0.72, green: 0.70, blue: 0.66, alpha: 1)
            )
        default:
            // Near-black on beige canvas (#F5EDE0) — matches body/title contrast.
            return (
                UIColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1),
                UIColor(red: 0.45, green: 0.40, blue: 0.35, alpha: 1)
            )
        }
    }

    static func bakeTraits(style: UIUserInterfaceStyle, scale: CGFloat = UIScreen.main.scale) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: scale > 0 ? scale : 2),
        ])
    }

    static func resolvedBakeStyle(preferred: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        if preferred == .light || preferred == .dark { return preferred }
        let fromApp = AppAppearance.style(forTheme: AppAppearance.storedTheme)
        if fromApp == .light || fromApp == .dark { return fromApp }
        // System theme: follow the concrete ambient style when available. Never invent
        // Light here — that stamped black speaker names on insert in Dark until reopen.
        // `attachmentBounds` still passes the last explicit `renderedInterfaceStyle`, so
        // this fallback does not revive the TF222 ambient-Dark rebake bug.
        let ambient = UITraitCollection.current.userInterfaceStyle
        if ambient == .light || ambient == .dark { return ambient }
        return .light
    }

    /// Luminance of an opaque name-area pixel (0…1). Used by AppTests.
    /// Reads via a known RGBA bitmap so channel order cannot lie about white-vs-black.
    func testing_namePixelLuminance() -> CGFloat? {
        guard let image else { return nil }
        let size = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let w = max(Int(size.width * image.scale), 8)
        let h = max(Int(size.height * image.scale), 8)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
        let y = h / 2
        let startX = Int(CGFloat(w) * 0.08)
        let endX = Int(CGFloat(w) * 0.55)
        for x in startX..<min(endX, w) {
            let idx = (y * w + x) * 4
            let a = Int(data[idx + 3])
            if a < 80 { continue }
            let r = CGFloat(data[idx]) / 255
            let g = CGFloat(data[idx + 1]) / 255
            let b = CGFloat(data[idx + 2]) / 255
            // Un-premultiply roughly for luma.
            let invA = a > 0 ? 255.0 / CGFloat(a) : 1
            let ur = min(1, r * invA)
            let ug = min(1, g * invA)
            let ub = min(1, b * invA)
            return 0.2126 * ur + 0.7152 * ug + 0.0722 * ub
        }
        return nil
    }
}
