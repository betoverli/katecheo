import UIKit

/// First-launch intro: 4 swipeable pages before the auth screen.
///
/// Layout contract:
/// - Wordmark "Katecheo" never wraps/hyphenates — single line, shrinks instead.
/// - Titles/bodies use the full page width (~32pt side padding).
/// - Page dots + Get started stay **above the home indicator**: bottom chrome is
///   pinned to `view.bottomAnchor` with an explicit inset of
///   `effectiveBottomSafeInset + 16`, never to a possibly-zero
///   `safeAreaLayoutGuide.bottom` alone (TF 325: guide bottom matched the
///   physical edge when the scene window race zeroed bottom insets).
final class OnboardingViewController: UIViewController, UIScrollViewDelegate {
    /// Called after Skip / Get started marks the intro seen.
    /// First-launch uses this to swap the window root; Settings replay dismisses.
    var onFinished: (() -> Void)?

    private let pages: [Page] = Page.all
    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let skipButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let bottomBar = UIStackView()
    /// Pins `bottomBar` to the physical bottom, with a constant that includes
    /// the home-indicator inset (+ 16pt). Updated whenever safe-area changes.
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private var pageWidth: CGFloat = 0
    private(set) var currentPageIndex = 0

    /// Standard home-indicator inset used when top is clearly inset (notch /
    /// Dynamic Island) but bottom reports 0 — the TF 325 failure mode.
    static let homeIndicatorFallback: CGFloat = 34

    private struct Page {
        let symbolName: String
        let title: String
        let body: String
        let accessibilityHint: String
        let usesBrandMark: Bool

        static let all: [Page] = [
            Page(
                symbolName: "book.closed.fill",
                title: String(localized: "Katecheo"),
                body: String(localized: "Seu estudo bíblico, organizado"),
                accessibilityHint: String(localized: "Boas-vindas ao Katecheo"),
                usesBrandMark: true
            ),
            Page(
                symbolName: "note.text",
                title: String(localized: "Notas com referências"),
                body: String(localized: "Anote sermões e estudos e marque referências bíblicas que abrem no seu app de Bíblia."),
                accessibilityHint: String(localized: "Notas com referências"),
                usesBrandMark: false
            ),
            Page(
                symbolName: "square.stack.3d.up",
                title: String(localized: "Temas e leitura"),
                body: String(localized: "Organize por temas e acompanhe planos de leitura."),
                accessibilityHint: String(localized: "Temas e leitura"),
                usesBrandMark: false
            ),
            Page(
                symbolName: "person.2.fill",
                title: String(localized: "Grupos e amigos"),
                body: String(localized: "Compartilhe notas com amigos e grupos da igreja."),
                accessibilityHint: String(localized: "Grupos e amigos"),
                usesBrandMark: false
            ),
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        view.accessibilityIdentifier = "onboarding.root"
        // Bottom chrome must receive taps; don't let a sibling scroll view steal them.
        view.clipsToBounds = true

        skipButton.setTitle(String(localized: "Pular"), for: .normal)
        skipButton.titleLabel?.font = KCDesign.headline()
        skipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skipButton.tintColor = KCDesign.accent
        skipButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        skipButton.accessibilityLabel = String(localized: "Pular")
        skipButton.accessibilityHint = String(localized: "Pula a introdução e continua")
        skipButton.accessibilityIdentifier = "onboarding.skip"
        skipButton.translatesAutoresizingMaskIntoConstraints = false

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "onboarding.scroll"
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = KCDesign.accent
        pageControl.pageIndicatorTintColor = KCDesign.spine.withAlphaComponent(0.35)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        pageControl.accessibilityLabel = String(localized: "Páginas da introdução")
        pageControl.accessibilityIdentifier = "onboarding.pageControl"
        pageControl.isAccessibilityElement = true

        KCButtonStyle.applyPrimary(to: startButton, title: String(localized: "Começar"))
        startButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        startButton.accessibilityIdentifier = "onboarding.start"
        // Keep the button in the stack at all times (alpha only) so showing it on
        // the last page cannot reflow the stack past the bottom edge.
        startButton.alpha = 0
        startButton.isUserInteractionEnabled = false
        startButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        bottomBar.axis = .vertical
        bottomBar.spacing = KCDesign.Space.md
        bottomBar.alignment = .fill
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.accessibilityIdentifier = "onboarding.bottomBar"
        bottomBar.setContentCompressionResistancePriority(.required, for: .vertical)
        bottomBar.setContentHuggingPriority(.required, for: .vertical)
        bottomBar.addArrangedSubview(pageControl)
        bottomBar.addArrangedSubview(startButton)

        view.addSubview(skipButton)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)
        // Ensure chrome is above the paging scroll view for hit-testing.
        view.bringSubviewToFront(bottomBar)
        view.bringSubviewToFront(skipButton)

        let guide = view.safeAreaLayoutGuide
        let bottomPin = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -KCDesign.Space.md)
        bottomBarBottomConstraint = bottomPin

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: KCDesign.Space.xs),
            skipButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.md),

            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: KCDesign.Space.sm),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -KCDesign.Space.md),

            bottomBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: KCDesign.Space.lg),
            bottomBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.lg),
            bottomPin,
        ])

        buildPages()
        updateBottomChromeInset()
        updateChrome(animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomChromeInset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomChromeInset()
        let width = scrollView.bounds.width
        guard width > 0, abs(width - pageWidth) > 0.5 else { return }
        pageWidth = width
        let height = scrollView.bounds.height
        scrollView.contentSize = CGSize(width: width * CGFloat(pages.count), height: height)
        for (index, pageView) in scrollView.subviews.enumerated() {
            pageView.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
        scrollView.setContentOffset(CGPoint(x: CGFloat(currentPageIndex) * width, y: 0), animated: false)
    }

    /// Resolves the bottom safe inset that Get started must clear.
    /// Pure — unit-tested. Prefer the larger of view/window insets; if top is
    /// clearly inset (notch / island) but bottom is 0, use the home-indicator
    /// fallback so chrome never sits flush with the physical bottom edge.
    static func effectiveBottomSafeInset(
        viewInset: CGFloat,
        windowInset: CGFloat,
        topInset: CGFloat
    ) -> CGFloat {
        let resolved = max(0, max(viewInset, windowInset))
        if resolved < 1, topInset > 20 {
            return homeIndicatorFallback
        }
        return resolved
    }

    private func updateBottomChromeInset() {
        let windowInset = view.window?.safeAreaInsets.bottom
            ?? view.window?.windowScene?.windows.map(\.safeAreaInsets.bottom).max()
            ?? 0
        let inset = Self.effectiveBottomSafeInset(
            viewInset: view.safeAreaInsets.bottom,
            windowInset: windowInset,
            topInset: view.safeAreaInsets.top
        )
        let constant = -(inset + KCDesign.Space.md)
        if bottomBarBottomConstraint?.constant != constant {
            bottomBarBottomConstraint?.constant = constant
        }
    }

    private func buildPages() {
        scrollView.subviews.forEach { $0.removeFromSuperview() }
        for (index, page) in pages.enumerated() {
            let pageView = makePageView(page, index: index)
            scrollView.addSubview(pageView)
        }
    }

    private func makePageView(_ page: Page, index: Int) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = "onboarding.page.\(index)"

        let pageScroll = UIScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.showsVerticalScrollIndicator = false
        pageScroll.alwaysBounceVertical = true
        pageScroll.contentInsetAdjustmentBehavior = .never
        container.addSubview(pageScroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = KCDesign.Space.lg
        stack.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.addSubview(stack)

        if page.usesBrandMark {
            let brand = UIImageView(image: UIImage(named: "BrandMark"))
            brand.contentMode = .scaleAspectFit
            brand.translatesAutoresizingMaskIntoConstraints = false
            brand.isAccessibilityElement = false
            brand.heightAnchor.constraint(equalToConstant: 96).isActive = true
            brand.widthAnchor.constraint(equalToConstant: 96).isActive = true
            stack.addArrangedSubview(centeredRow(brand))
        } else {
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 56, weight: .medium)
            let icon = UIImageView(image: UIImage(systemName: page.symbolName, withConfiguration: symbolConfig))
            icon.tintColor = KCDesign.accent
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.isAccessibilityElement = false
            icon.heightAnchor.constraint(equalToConstant: 88).isActive = true
            icon.widthAnchor.constraint(equalToConstant: 88).isActive = true

            let halo = UIView()
            halo.translatesAutoresizingMaskIntoConstraints = false
            halo.backgroundColor = KCDesign.accentSoft
            halo.layer.cornerRadius = 56
            halo.layer.cornerCurve = .continuous

            let iconWrap = UIView()
            iconWrap.translatesAutoresizingMaskIntoConstraints = false
            iconWrap.addSubview(halo)
            iconWrap.addSubview(icon)
            NSLayoutConstraint.activate([
                iconWrap.widthAnchor.constraint(equalToConstant: 120),
                iconWrap.heightAnchor.constraint(equalToConstant: 120),
                halo.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
                halo.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
                halo.widthAnchor.constraint(equalToConstant: 112),
                halo.heightAnchor.constraint(equalToConstant: 112),
                icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            ])
            stack.addArrangedSubview(centeredRow(iconWrap))
        }

        let title = UILabel()
        title.text = page.title
        title.font = page.usesBrandMark ? KCDesign.displayTitle() : KCDesign.screenTitle()
        title.textAlignment = .center
        title.textColor = .label
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = page.usesBrandMark ? "onboarding.wordmark" : "onboarding.title.\(index)"
        if page.usesBrandMark {
            title.numberOfLines = 1
            title.lineBreakMode = .byClipping
            title.adjustsFontSizeToFitWidth = true
            title.minimumScaleFactor = 0.6
            title.allowsDefaultTighteningForTruncation = true
            title.setContentCompressionResistancePriority(.required, for: .vertical)
        } else {
            title.numberOfLines = 0
            title.lineBreakMode = .byWordWrapping
            title.setContentHuggingPriority(.required, for: .vertical)
        }

        let body = UILabel()
        body.text = page.body
        body.font = KCDesign.body()
        body.textColor = .secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.adjustsFontForContentSizeCategory = true
        body.accessibilityIdentifier = "onboarding.body.\(index)"
        body.setContentHuggingPriority(.required, for: .vertical)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body)
        stack.setCustomSpacing(KCDesign.Space.sm, after: title)

        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(page.title). \(page.body)"
        container.accessibilityHint = page.accessibilityHint
        container.accessibilityTraits = .staticText

        let sidePad = KCDesign.Space.xl
        NSLayoutConstraint.activate([
            pageScroll.topAnchor.constraint(equalTo: container.topAnchor),
            pageScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pageScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.topAnchor.constraint(greaterThanOrEqualTo: pageScroll.contentLayoutGuide.topAnchor, constant: KCDesign.Space.lg),
            stack.leadingAnchor.constraint(equalTo: pageScroll.frameLayoutGuide.leadingAnchor, constant: sidePad),
            stack.trailingAnchor.constraint(equalTo: pageScroll.frameLayoutGuide.trailingAnchor, constant: -sidePad),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: pageScroll.contentLayoutGuide.bottomAnchor, constant: -KCDesign.Space.lg),
            stack.widthAnchor.constraint(equalTo: pageScroll.frameLayoutGuide.widthAnchor, constant: -(sidePad * 2)),
            stack.centerYAnchor.constraint(equalTo: pageScroll.frameLayoutGuide.centerYAnchor).withPriority(.defaultHigh),
            pageScroll.contentLayoutGuide.heightAnchor.constraint(
                greaterThanOrEqualTo: pageScroll.frameLayoutGuide.heightAnchor
            ),
        ])
        return container
    }

    private func centeredRow(_ child: UIView) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        child.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(child)
        NSLayoutConstraint.activate([
            child.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            child.topAnchor.constraint(equalTo: row.topAnchor),
            child.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            child.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
            child.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    private func updateChrome(animated: Bool) {
        let last = currentPageIndex >= pages.count - 1
        let changes = {
            self.skipButton.alpha = last ? 0 : 1
            self.skipButton.isEnabled = !last
            self.skipButton.isUserInteractionEnabled = !last
            // Never isHidden the start button — keep stack height stable and
            // the bottom pin meaningful on every page.
            self.startButton.alpha = last ? 1 : 0
            self.startButton.isUserInteractionEnabled = last
            self.pageControl.currentPage = self.currentPageIndex
            self.pageControl.accessibilityValue = String(
                format: String(localized: "Página %lld de %lld"),
                self.currentPageIndex + 1,
                self.pages.count
            )
            self.updateBottomChromeInset()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes)
        } else {
            changes()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView, pageWidth > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / pageWidth))
        let clamped = max(0, min(pages.count - 1, page))
        if clamped != currentPageIndex {
            currentPageIndex = clamped
            updateChrome(animated: true)
        }
    }

    @objc private func pageControlChanged() {
        goToPage(pageControl.currentPage, animated: true)
    }

    @objc private func finishTapped() {
        OnboardingStore.markSeen()
        onFinished?()
    }

    // MARK: - Testing hooks

    var testing_currentPage: Int { currentPageIndex }
    var testing_isSkipVisible: Bool { skipButton.alpha > 0.01 && skipButton.isUserInteractionEnabled }
    var testing_isStartVisible: Bool { startButton.alpha > 0.01 && startButton.isUserInteractionEnabled }
    var testing_pageCount: Int { pages.count }
    var testing_skipTitle: String? { skipButton.title(for: .normal) }
    var testing_startTitle: String? { startButton.configuration?.title ?? startButton.title(for: .normal) }
    var testing_bottomBarFrameInView: CGRect { bottomBar.convert(bottomBar.bounds, to: view) }
    var testing_startButtonFrameInView: CGRect { startButton.convert(startButton.bounds, to: view) }
    var testing_skipButtonFrameInView: CGRect { skipButton.convert(skipButton.bounds, to: view) }
    var testing_startButtonFrameInWindow: CGRect {
        startButton.convert(startButton.bounds, to: view.window)
    }
    var testing_safeAreaInsets: UIEdgeInsets { view.safeAreaInsets }
    var testing_bottomBarBottomConstant: CGFloat { bottomBarBottomConstraint?.constant ?? 0 }
    var testing_wordmarkLabel: UILabel? {
        firstLabel(in: scrollView, matching: { $0.accessibilityIdentifier == "onboarding.wordmark" })
    }
    var testing_currentBodyLabel: UILabel? {
        firstLabel(in: scrollView, matching: { $0.accessibilityIdentifier == "onboarding.body.\(currentPageIndex)" })
    }
    var testing_currentTitleLabel: UILabel? {
        if currentPageIndex == 0 { return testing_wordmarkLabel }
        return firstLabel(in: scrollView, matching: { $0.accessibilityIdentifier == "onboarding.title.\(currentPageIndex)" })
    }
    var testing_pageTitle: String? { testing_currentTitleLabel?.text }
    var testing_startButton: UIButton { startButton }

    func testing_goToPage(_ index: Int, animated: Bool = false) {
        goToPage(index, animated: animated)
    }

    func testing_tapSkip() { finishTapped() }
    func testing_tapStart() { finishTapped() }
    func testing_updateBottomChromeInset() { updateBottomChromeInset() }

    private func goToPage(_ index: Int, animated: Bool) {
        let clamped = max(0, min(pages.count - 1, index))
        currentPageIndex = clamped
        let width = max(pageWidth, scrollView.bounds.width)
        guard width > 0 else {
            updateChrome(animated: false)
            return
        }
        scrollView.setContentOffset(CGPoint(x: CGFloat(clamped) * width, y: 0), animated: animated)
        updateChrome(animated: animated)
    }

    private func firstLabel(in root: UIView, matching: (UILabel) -> Bool) -> UILabel? {
        if let label = root as? UILabel, matching(label) { return label }
        for child in root.subviews {
            if let found = firstLabel(in: child, matching: matching) { return found }
        }
        return nil
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
