import UIKit

/// Non-editable speaker section chrome (web `.note-speaker-head`).
///
/// Drawn as an `NSTextAttachment` so the caret cannot enter the name. Hit regions:
/// - chevron → collapse/expand
/// - × → delete section
/// - name / remaining header → rename via speaker picker
///
/// Colors are flattened to concrete RGB under an explicit trait collection and baked
/// into `alwaysOriginal` images. Re-call `refreshImage` when appearance changes (TF214/TF219).
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

    /// Last traits / width used to bake `image` — drives dirty checks.
    private(set) var renderedInterfaceStyle: UIUserInterfaceStyle = .unspecified
    private(set) var renderedWidth: CGFloat = 0

    init(
        blockId: String,
        speakerId: String?,
        speakerName: String,
        colorHex: String?,
        collapsed: Bool,
        preview: String = ""
    ) {
        self.blockId = blockId
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.colorHex = colorHex
        self.collapsed = collapsed
        self.preview = preview
        super.init(data: nil, ofType: nil)
        // Prefer light as a safe default when no window traits exist yet (decode / tests).
        let seed = UITraitCollection(traitsFrom: [
            UITraitCollection.current,
            UITraitCollection(userInterfaceStyle: .light),
        ])
        refreshImage(width: 320, traits: seed)
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
        // Prefer ambient traits here; NativeNoteEditorView also refreshes with textView.traitCollection.
        let traits = UITraitCollection.current
        let style = traits.userInterfaceStyle
        let widthDirty = abs(renderedWidth - width) > 1
        let styleDirty = renderedInterfaceStyle != style && style != .unspecified
        if widthDirty || styleDirty || image == nil {
            refreshImage(width: width, traits: traits)
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

    /// Rebuild the chrome image with colors resolved for `traits`.
    func refreshImage(width: CGFloat, traits: UITraitCollection = .current) {
        let w = max(width, 120)
        // ≥44pt tall so the × hit box meets HIG without enlarging the glyph.
        let height: CGFloat = 44
        let nameFont = V2NDesign.preferred(.title3, weight: .semibold)
        let previewFont = V2NDesign.preferred(.caption1, weight: .regular)
        // Flatten dynamic colors under the requested traits so UIGraphicsImageRenderer
        // cannot re-resolve against ambient (often dark) traits during draw (TF219).
        let nameColor = Self.concreteColor(UIColor.label, traits: traits)
        let muted = Self.concreteColor(UIColor.secondaryLabel, traits: traits)
        let name = speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Speaker")
            : speakerName

        let chevronSize: CGFloat = 10
        // Visual × column stays ~36pt; hit zone is ≥44pt (web `.note-speaker-remove` 2.75rem).
        let removeVisualSize: CGFloat = 36
        let removeHitSize: CGFloat = 44
        // Nudge chevron + name further left (TF194 #5) — web chevron margin ~0.2rem.
        let padL: CGFloat = 4
        let gap: CGFloat = 8

        chevronEndX = (padL + chevronSize + gap) / w
        removeStartX = (w - removeHitSize) / w

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = traits.displayScale > 0 ? traits.displayScale : UIScreen.main.scale

        var baked: UIImage!
        traits.performAsCurrent {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: height), format: format)
            baked = renderer.image { _ in
                // Chevron (CSS-like rotated square borders).
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
                    .font: V2NDesign.preferred(.title2, weight: .regular),
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
        renderedInterfaceStyle = traits.userInterfaceStyle
    }

    /// Snapshot a dynamic color to concrete RGB under `traits` (survives later draw contexts).
    static func concreteColor(_ color: UIColor, traits: UITraitCollection) -> UIColor {
        let resolved = color.resolvedColor(with: traits)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        // Fallback for grayscale / pattern colors.
        var white: CGFloat = 0
        if resolved.getWhite(&white, alpha: &a) {
            return UIColor(white: white, alpha: a)
        }
        return resolved
    }

    /// Luminance of an opaque name-area pixel (0…1). Used by AppTests.
    func testing_namePixelLuminance() -> CGFloat? {
        guard let image, let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        guard w > 8, h > 8 else { return nil }
        guard let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else { return nil }
        let bpp = max(cg.bitsPerPixel / 8, 4)
        let y = h / 2
        let startX = Int(CGFloat(w) * 0.08)
        let endX = Int(CGFloat(w) * 0.55)
        for x in startX..<min(endX, w) {
            let idx = (y * cg.bytesPerRow) + x * bpp
            let a = bpp >= 4 ? Int(ptr[idx + 3]) : 255
            if a < 80 { continue }
            let r = CGFloat(ptr[idx]) / 255
            let g = CGFloat(ptr[idx + 1]) / 255
            let b = CGFloat(ptr[idx + 2]) / 255
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return nil
    }
}
