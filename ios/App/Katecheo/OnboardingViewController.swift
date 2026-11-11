import UIKit

/// First-launch intro: 4 swipeable pages before the auth screen.
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
    private var pageWidth: CGFloat = 0
    private(set) var currentPageIndex = 0

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
        startButton.isHidden = true
        startButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        bottomBar.axis = .vertical
        bottomBar.spacing = KCDesign.Space.md
        bottomBar.alignment = .fill
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addArrangedSubview(pageControl)
        bottomBar.addArrangedSubview(startButton)

        view.addSubview(skipButton)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: KCDesign.Space.xs),
            skipButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.md),

            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: KCDesign.Space.sm),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -KCDesign.Space.md),

            bottomBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: KCDesign.Space.lg),
            bottomBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.lg),
            bottomBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -KCDesign.Space.md),
        ])

        buildPages()
        updateChrome(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = KCDesign.Space.lg
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        if page.usesBrandMark {
            let brand = UIImageView(image: UIImage(named: "BrandMark"))
            brand.contentMode = .scaleAspectFit
            brand.translatesAutoresizingMaskIntoConstraints = false
            brand.isAccessibilityElement = false
            brand.heightAnchor.constraint(equalToConstant: 96).isActive = true
            brand.widthAnchor.constraint(equalToConstant: 96).isActive = true
            stack.addArrangedSubview(brand)
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
            stack.addArrangedSubview(iconWrap)
        }

        let title = UILabel()
        title.text = page.title
        // Katecheo must stay one complete word in a single uniform style (never split fonts).
        title.font = page.usesBrandMark ? KCDesign.displayTitle() : KCDesign.screenTitle()
        title.textAlignment = .center
        title.textColor = .label
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header

        let body = UILabel()
        body.text = page.body
        body.font = KCDesign.body()
        body.textColor = .secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body)
        stack.setCustomSpacing(KCDesign.Space.sm, after: title)

        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(page.title). \(page.body)"
        container.accessibilityHint = page.accessibilityHint
        container.accessibilityTraits = .staticText

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: container.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.layoutMarginsGuide.bottomAnchor),
        ])
        container.layoutMargins = UIEdgeInsets(
            top: KCDesign.Space.lg,
            left: KCDesign.Space.xl,
            bottom: KCDesign.Space.lg,
            right: KCDesign.Space.xl
        )
        return container
    }

    private func updateChrome(animated: Bool) {
        let last = currentPageIndex >= pages.count - 1
        let changes = {
            self.skipButton.alpha = last ? 0 : 1
            self.skipButton.isEnabled = !last
            self.skipButton.isHidden = last
            self.startButton.isHidden = !last
            self.startButton.alpha = last ? 1 : 0
            self.pageControl.currentPage = self.currentPageIndex
            self.pageControl.accessibilityValue = String(
                format: String(localized: "Página %lld de %lld"),
                self.currentPageIndex + 1,
                self.pages.count
            )
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: changes)
        } else {
            changes()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard pageWidth > 0 else { return }
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
    var testing_isSkipVisible: Bool { !skipButton.isHidden && skipButton.alpha > 0.01 }
    var testing_isStartVisible: Bool { !startButton.isHidden && startButton.alpha > 0.01 }
    var testing_pageCount: Int { pages.count }
    var testing_skipTitle: String? { skipButton.title(for: .normal) }
    var testing_startTitle: String? { startButton.configuration?.title ?? startButton.title(for: .normal) }
    var testing_pageTitle: String? {
        guard currentPageIndex < scrollView.subviews.count else { return nil }
        return scrollView.subviews[currentPageIndex]
            .subviews
            .compactMap { $0 as? UIStackView }
            .first?
            .arrangedSubviews
            .compactMap { $0 as? UILabel }
            .first?
            .text
    }

    func testing_goToPage(_ index: Int, animated: Bool = false) {
        goToPage(index, animated: animated)
    }

    func testing_tapSkip() { finishTapped() }
    func testing_tapStart() { finishTapped() }

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
}
