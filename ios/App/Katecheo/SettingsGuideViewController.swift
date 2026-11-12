import UIKit

/// Short post-sign-in setup: Bible app → translation → notifications.
/// Shown once per account/device (`OnboardingStore.hasSeenSettingsGuide`).
final class SettingsGuideViewController: UIViewController {
    var onFinished: (() -> Void)?

    private enum Step: Int, CaseIterable {
        case bibleApp
        case translation
        case notifications
    }

    private var step: Step = .bibleApp
    private var selectedAppId = "youversion"
    private var selectedTranslationId = ProfileBibleCatalog.defaultTranslationId()

    private let skipButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let stepLabel = UILabel()
    private let listStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let bottomBar = UIStackView()
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private var saving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        view.accessibilityIdentifier = "settingsGuide.root"
        _ = KCGlassMaterial.sdkHasLiquidGlass()

        skipButton.setTitle(String(localized: "Pular"), for: .normal)
        skipButton.titleLabel?.font = KCDesign.headline()
        skipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skipButton.tintColor = KCDesign.accent
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipButton.accessibilityLabel = String(localized: "Pular")
        skipButton.accessibilityHint = String(localized: "Usa os padrões e continua")
        skipButton.accessibilityIdentifier = "settingsGuide.skip"
        skipButton.translatesAutoresizingMaskIntoConstraints = false

        stepLabel.font = KCDesign.caption()
        stepLabel.textColor = .secondaryLabel
        stepLabel.textAlignment = .center
        stepLabel.adjustsFontForContentSizeCategory = true
        stepLabel.accessibilityIdentifier = "settingsGuide.step"

        titleLabel.font = KCDesign.screenTitle()
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityIdentifier = "settingsGuide.title"

        bodyLabel.font = KCDesign.body()
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.accessibilityIdentifier = "settingsGuide.body"

        listStack.axis = .vertical
        listStack.spacing = KCDesign.Space.xs
        listStack.alignment = .fill
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.accessibilityIdentifier = "settingsGuide.list"

        KCButtonStyle.applyPrimary(to: primaryButton, title: String(localized: "Continuar"))
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "settingsGuide.primary"
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        KCButtonStyle.applySecondary(to: secondaryButton, title: String(localized: "Agora não"))
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        secondaryButton.accessibilityIdentifier = "settingsGuide.secondary"
        secondaryButton.isHidden = true
        secondaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        bottomBar.axis = .vertical
        bottomBar.spacing = KCDesign.Space.sm
        bottomBar.alignment = .fill
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addArrangedSubview(primaryButton)
        bottomBar.addArrangedSubview(secondaryButton)

        let content = UIStackView(arrangedSubviews: [stepLabel, titleLabel, bodyLabel, listStack])
        content.axis = .vertical
        content.spacing = KCDesign.Space.md
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setCustomSpacing(KCDesign.Space.sm, after: titleLabel)
        content.setCustomSpacing(KCDesign.Space.lg, after: bodyLabel)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.addSubview(content)

        view.addSubview(skipButton)
        view.addSubview(scroll)
        view.addSubview(bottomBar)

        let guide = view.safeAreaLayoutGuide
        let bottomPin = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -KCDesign.Space.md)
        bottomBarBottomConstraint = bottomPin

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: KCDesign.Space.xs),
            skipButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.md),

            scroll.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: KCDesign.Space.sm),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -KCDesign.Space.md),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: KCDesign.Space.lg),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: KCDesign.Space.lg),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -KCDesign.Space.lg),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -KCDesign.Space.lg),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -(KCDesign.Space.lg * 2)),

            bottomBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: KCDesign.Space.lg),
            bottomBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -KCDesign.Space.lg),
            bottomPin,
        ])

        renderStep()
        updateBottomChromeInset()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomChromeInset()
    }

    private func updateBottomChromeInset() {
        let inset = OnboardingViewController.effectiveBottomSafeInset(
            viewInset: view.safeAreaInsets.bottom,
            windowInset: view.window?.safeAreaInsets.bottom ?? 0,
            topInset: view.safeAreaInsets.top
        )
        bottomBarBottomConstraint?.constant = -(inset + KCDesign.Space.md)
    }

    private func renderStep() {
        let total = Step.allCases.count
        let index = step.rawValue + 1
        stepLabel.text = String(format: String(localized: "Passo %lld de %lld"), index, total)
        secondaryButton.isHidden = step != .notifications
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        skipButton.setTitle(String(localized: "Pular"), for: .normal)
        skipButton.accessibilityLabel = String(localized: "Pular")
        skipButton.accessibilityHint = String(localized: "Usa os padrões e continua")
        skipButton.isHidden = false

        switch step {
        case .bibleApp:
            titleLabel.text = String(localized: "App de Bíblia")
            bodyLabel.text = String(localized: "Escolha onde abrir as referências. Você pode mudar depois em Perfil.")
            KCButtonStyle.applyPrimary(to: primaryButton, title: String(localized: "Continuar"))
            for app in ProfileBibleCatalog.apps {
                listStack.addArrangedSubview(makeOptionRow(
                    title: app.name,
                    selected: selectedAppId == app.id,
                    accessibilityId: "settingsGuide.app.\(app.id)"
                ) { [weak self] in
                    self?.selectedAppId = app.id
                    self?.renderStep()
                    self?.savePrefs(["appId": app.id])
                })
            }
        case .translation:
            titleLabel.text = String(localized: "Tradução")
            bodyLabel.text = String(localized: "Usamos esta tradução nos links da Bíblia. Pode alterar a qualquer momento.")
            KCButtonStyle.applyPrimary(to: primaryButton, title: String(localized: "Continuar"))
            for tr in ProfileBibleCatalog.translations {
                listStack.addArrangedSubview(makeOptionRow(
                    title: tr.name,
                    selected: selectedTranslationId == tr.id,
                    accessibilityId: "settingsGuide.translation.\(tr.id)"
                ) { [weak self] in
                    self?.selectedTranslationId = tr.id
                    self?.renderStep()
                    self?.savePrefs(["translationId": tr.id])
                })
            }
        case .notifications:
            titleLabel.text = String(localized: "Notificações")
            bodyLabel.text = String(localized: "Avisos de planos de leitura, amigos, compartilhamentos e grupos. Você controla isso em Perfil.")
            KCButtonStyle.applyPrimary(to: primaryButton, title: String(localized: "Ativar notificações"))
            KCButtonStyle.applySecondary(to: secondaryButton, title: String(localized: "Agora não"))
            secondaryButton.isHidden = false
            skipButton.setTitle(String(localized: "Concluir"), for: .normal)
            skipButton.accessibilityLabel = String(localized: "Concluir")
            skipButton.accessibilityHint = String(localized: "Conclui a configuração")
        }

        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    private func makeOptionRow(
        title: String,
        selected: Bool,
        accessibilityId: String,
        onTap: @escaping () -> Void
    ) -> UIControl {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = accessibilityId
        button.accessibilityLabel = title
        button.accessibilityTraits = selected ? [.button, .selected] : .button

        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        config.titleAlignment = .leading
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = KCDesign.headline()
            return out
        }
        config.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        config.imagePlacement = .trailing
        config.imagePadding = 12
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        config.baseBackgroundColor = selected ? KCDesign.accentSoft : KCDesign.surface
        button.configuration = config
        button.tintColor = KCDesign.accent
        button.backgroundColor = selected ? KCDesign.accentSoft : KCDesign.surface
        button.layer.cornerRadius = KCDesign.Radius.md
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = (selected ? KCDesign.accent : KCDesign.separator).cgColor
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        button.addAction(UIAction { _ in
            KCHaptics.selection()
            onTap()
        }, for: .touchUpInside)
        return button
    }

    @objc private func skipTapped() {
        guard !saving else { return }
        switch step {
        case .bibleApp:
            selectedAppId = "youversion"
            savePrefs(["appId": selectedAppId]) { [weak self] in self?.advance() }
        case .translation:
            selectedTranslationId = ProfileBibleCatalog.defaultTranslationId()
            savePrefs(["translationId": selectedTranslationId]) { [weak self] in self?.advance() }
        case .notifications:
            finishGuide()
        }
    }

    @objc private func primaryTapped() {
        guard !saving else { return }
        switch step {
        case .bibleApp:
            savePrefs(["appId": selectedAppId]) { [weak self] in self?.advance() }
        case .translation:
            savePrefs(["translationId": selectedTranslationId]) { [weak self] in self?.advance() }
        case .notifications:
            Task { @MainActor in
                self.saving = true
                _ = await NativePushService.shared.enable()
                self.saving = false
                self.finishGuide()
            }
        }
    }

    @objc private func secondaryTapped() {
        guard step == .notifications, !saving else { return }
        finishGuide()
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finishGuide()
            return
        }
        step = next
        renderStep()
    }

    private func finishGuide() {
        OnboardingStore.markSettingsGuideSeen()
        KCHaptics.success()
        if presentingViewController != nil {
            dismiss(animated: true) { [weak self] in self?.onFinished?() }
        } else {
            onFinished?()
        }
    }

    private func savePrefs(_ patch: [String: Any], then: (() -> Void)? = nil) {
        guard NativeAPIClient.hasBearer else {
            then?()
            return
        }
        saving = true
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(patch)
            } catch {
                #if DEBUG
                print("[SettingsGuide] patchPrefs failed: \(error)")
                #endif
            }
            self.saving = false
            then?()
        }
    }

    // MARK: - Testing hooks

    var testing_stepIndex: Int { step.rawValue }
    var testing_selectedAppId: String { selectedAppId }
    var testing_selectedTranslationId: String { selectedTranslationId }
    var testing_title: String? { titleLabel.text }
    var testing_isSecondaryVisible: Bool { !secondaryButton.isHidden }

    func testing_tapSkip() { skipTapped() }
    func testing_tapPrimary() { primaryTapped() }
    func testing_tapSecondary() { secondaryTapped() }
    func testing_selectApp(_ id: String) {
        selectedAppId = id
        renderStep()
    }
    func testing_selectTranslation(_ id: String) {
        selectedTranslationId = id
        renderStep()
    }
}
