import UIKit

/// Accept / decline a notebook-group friend invite (opened from push or inbox).
final class GroupInviteDetailViewController: UIViewController {
    private let inviteId: String
    private var invite: NativeAPIClient.GroupInviteDTO?
    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let acceptButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private let emptyState = KCEmptyStateView()
    private var busy = false

    init(inviteId: String, invite: NativeAPIClient.GroupInviteDTO? = nil) {
        self.inviteId = inviteId
        self.invite = invite
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Convite de grupo")
        navigationItem.largeTitleDisplayMode = .never

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = KCDesign.surface
        card.layer.cornerRadius = 16
        view.addSubview(card)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = KCDesign.screenTitle()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = KCDesign.body()
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        var acceptConfig = UIButton.Configuration.filled()
        acceptConfig.cornerStyle = .large
        acceptConfig.baseBackgroundColor = KCDesign.accent
        acceptConfig.baseForegroundColor = .white
        acceptConfig.title = String(localized: "Aceitar convite")
        acceptButton.configuration = acceptConfig
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)

        declineButton.translatesAutoresizingMaskIntoConstraints = false
        var declineConfig = UIButton.Configuration.plain()
        declineConfig.cornerStyle = .large
        declineConfig.baseForegroundColor = .systemRed
        declineConfig.title = String(localized: "Recusar")
        declineButton.configuration = declineConfig
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, acceptButton, declineButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        card.addSubview(stack)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -24),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),

            acceptButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            declineButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        applyInvite()
        Task { await reload() }
    }

    private func applyInvite() {
        guard let invite else {
            card.isHidden = true
            return
        }
        card.isHidden = false
        emptyState.hide()
        titleLabel.text = invite.groupName
        bodyLabel.text = String(
            format: String(localized: "%@ convidou você para este grupo."),
            invite.inviter.displayName
        )
        let pending = invite.isPending
        acceptButton.isHidden = !pending
        declineButton.isHidden = !pending
        if !pending {
            bodyLabel.text = invite.status == "accepted"
                ? String(localized: "Você já entrou neste grupo.")
                : String(localized: "Este convite não está mais disponível.")
        }
    }

    private func reload() async {
        do {
            let fresh = try await NativeAPIClient.getGroupInvite(id: inviteId)
            await MainActor.run {
                self.invite = fresh
                self.applyInvite()
            }
        } catch {
            await MainActor.run {
                if self.invite == nil {
                    self.card.isHidden = true
                    self.emptyState.show(
                        symbol: "envelope.badge.shield.half.filled",
                        title: String(localized: "Convite indisponível"),
                        message: String(localized: "Este convite expirou ou já foi respondido.")
                    )
                }
            }
        }
    }

    @objc private func acceptTapped() {
        respond(accept: true)
    }

    @objc private func declineTapped() {
        respond(accept: false)
    }

    private func respond(accept: Bool) {
        guard !busy else { return }
        busy = true
        acceptButton.isEnabled = false
        declineButton.isEnabled = false
        Task { @MainActor in
            defer {
                busy = false
                acceptButton.isEnabled = true
                declineButton.isEnabled = true
            }
            do {
                let group = try await NativeAPIClient.respondGroupInvite(id: inviteId, accept: accept)
                KCHaptics.success()
                if accept, let group {
                    if let nav = navigationController {
                        nav.popViewController(animated: false)
                        nav.pushViewController(NotebookListViewController(group: group), animated: true)
                    }
                } else {
                    navigationController?.popViewController(animated: true)
                }
            } catch {
                let alert = UIAlertController(
                    title: String(localized: "Erro"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }
}
