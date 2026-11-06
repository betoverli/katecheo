import UIKit

/// Non-editable speaker section chrome (web `.note-speaker-head`).
///
/// Drawn as an `NSTextAttachment` so the caret cannot enter the name. Hit regions:
/// - chevron → collapse/expand
/// - × → delete section
/// - name / remaining header → rename via speaker picker
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
        refreshImage(width: 320)
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
        if abs((image?.size.width ?? 0) - width) > 1 {
            refreshImage(width: width)
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

    func refreshImage(width: CGFloat) {
        let w = max(width, 120)
        // ≥44pt tall so the × hit box meets HIG without enlarging the glyph.
        let height: CGFloat = 44
        let nameFont = V2NDesign.preferred(.title3, weight: .semibold)
        let previewFont = V2NDesign.preferred(.caption1, weight: .regular)
        let nameColor = UIColor.label
        let muted = UIColor.secondaryLabel
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

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: height))
        image = renderer.image { _ in
            // Chevron (CSS-like rotated square borders).
            let chevronCenter = CGPoint(x: padL + chevronSize / 2, y: height / 2)
            let path = UIBezierPath()
            let arm: CGFloat = 4.5
            if collapsed {
                // ▸ pointing right-ish
                path.move(to: CGPoint(x: chevronCenter.x - 2, y: chevronCenter.y - arm))
                path.addLine(to: CGPoint(x: chevronCenter.x + 3, y: chevronCenter.y))
                path.addLine(to: CGPoint(x: chevronCenter.x - 2, y: chevronCenter.y + arm))
            } else {
                // ▾ pointing down
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

            // × remove control (web `.note-speaker-remove`) — glyph centered in the
            // visual column; hit testing uses the wider `removeHitSize` band.
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
        bounds = CGRect(x: 0, y: -8, width: w, height: height)
    }
}
