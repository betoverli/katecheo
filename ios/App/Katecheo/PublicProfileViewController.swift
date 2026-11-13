import UIKit

/// Amigos → tap friend: read-only public profile (photo/initials, name, @handle) + ⋯ menu.
final class PublicProfileViewController: UIViewController {
    private var person: NativeAPIClient.LinkPersonDTO
    private var friendshipStatus: String
    private let onRelationshipChanged: (() -> Void)?

    private let avatarView = KCAvatarView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let stack = UIStackView()
    private var moreButton: UIBarButtonItem!
    private var loading = false

    init(
        person: NativeAPIClient.LinkPersonDTO,
        friendshipStatus: String = "accepted",
        onRelationshipChanged: (() -> Void)? = nil
    ) {
        self.person = person
        self.friendshipStatus = friendshipStatus
        self.onRelationshipChanged = onRelationshipChanged
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(
        profile: NativeAPIClient.PublicProfileDTO,
        onRelationshipChanged: (() -> Void)? = nil
    ) {
        self.init(
            person: profile.asPerson,
            friendshipStatus: profile.status,
            onRelationshipChanged: onRelationshipChanged
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Perfil")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            KCChrome.style(navigationController: nav)
        }

        moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(openMore)
        )
        moreButton.accessibilityLabel = String(localized: "Mais opções")
        navigationItem.rightBarButtonItem = moreButton

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = KCDesign.Space.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: KCDesign.Space.xl,
            left: KCDesign.Space.lg,
            bottom: KCDesign.Space.lg,
            right: KCDesign.Space.lg
        )
        view.addSubview(stack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 112),
            avatarView.heightAnchor.constraint(equalToConstant: 112),
        ])

        nameLabel.font = KCDesign.screenTitle()
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true

        handleLabel.font = KCDesign.rowSubtitle()
        handleLabel.textColor = .secondaryLabel
        handleLabel.textAlignment = .center
        handleLabel.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(avatarView)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(handleLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        applyPerson()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await refreshFromServer() }
    }

    /// Test seam — apply fixture without network.
    func testing_apply(person: NativeAPIClient.LinkPersonDTO, status: String = "accepted") {
        self.person = person
        self.friendshipStatus = status
        applyPerson()
    }

    private func applyPerson() {
        let display = person.displayName.isEmpty ? String(localized: "Sem nome") : person.displayName
        nameLabel.text = display
        if person.handle.isEmpty {
            handleLabel.text = nil
            handleLabel.isHidden = true
        } else {
            handleLabel.text = "@\(person.handle)"
            handleLabel.isHidden = false
        }
        avatarView.configure(displayName: display, handle: person.handle, avatarUrl: person.avatarUrl)
    }

    private func refreshFromServer() async {
        guard NativeAPIClient.hasBearer, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let profile = try await NativeAPIClient.getPublicProfile(userId: person.userId)
            await MainActor.run {
                self.person = profile.asPerson
                self.friendshipStatus = profile.status
                self.applyPerson()
            }
        } catch {
            if case NativeAPIClient.APIError.http(404, _) = error {
                await MainActor.run {
                    self.presentUnavailableThenPop()
                }
            }
            // Soft-fail other errors — keep seeded friend row data on screen.
        }
    }

    private func presentUnavailableThenPop() {
        let alert = UIAlertController(
            title: String(localized: "Perfil indisponível"),
            message: String(localized: "Não é possível ver este perfil."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
            self?.onRelationshipChanged?()
        })
        present(alert, animated: true)
    }

    @objc private func openMore() {
        let sheet = UIAlertController(title: person.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Denunciar"), style: .default) { [weak self] _ in
            guard let self else { return }
            ReportBlockSupport.presentReport(
                target: .user(userId: self.person.userId, displayName: self.person.displayName),
                from: self,
                barButtonItem: self.moreButton
            )
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Bloquear"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            ReportBlockSupport.confirmBlock(
                userId: self.person.userId,
                displayName: self.person.displayName,
                from: self,
                barButtonItem: self.moreButton
            ) { [weak self] in
                guard let self else { return }
                self.onRelationshipChanged?()
                self.navigationController?.popViewController(animated: true)
            }
        })
        if friendshipStatus == "accepted" {
            sheet.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive) { [weak self] _ in
                self?.confirmRemoveFriend()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(sheet, from: self, barButtonItem: moreButton)
    }

    private func confirmRemoveFriend() {
        let sheet = UIAlertController(
            title: String(localized: "Remover amigo?"),
            message: String(localized: "Vocês deixam de ser amigos nos dois lados."),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        sheet.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive) { [weak self] _ in
            Task { await self?.removeFriend() }
        })
        KCConfirmation.presentActionSheet(sheet, from: self, barButtonItem: moreButton)
    }

    private func removeFriend() async {
        let handle = person.handle
        guard !handle.isEmpty else { return }
        do {
            try await NativeAPIClient.removeLink(handle: handle)
            await MainActor.run {
                self.onRelationshipChanged?()
                self.navigationController?.popViewController(animated: true)
            }
        } catch {
            await MainActor.run {
                let alert = UIAlertController(
                    title: String(localized: "Erro"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}
