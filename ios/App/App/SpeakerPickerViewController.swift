import UIKit

/// Manage or pick speakers for a note.
final class SpeakerPickerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    enum Mode {
        case manage
        case pick(selectedId: String?)
    }

    private let mode: Mode
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let seed: [NativeAPIClient.SpeakerDTO]
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let onPicked: ((String?) -> Void)?
    private let onManaged: (() -> Void)?

    init(
        mode: Mode,
        seed: [NativeAPIClient.SpeakerDTO] = [],
        onPicked: ((String?) -> Void)? = nil,
        onManaged: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.seed = seed
        self.onPicked = onPicked
        self.onManaged = onManaged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Speakers")
        V2NChrome.styleCanvas(view)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "Fechar"), style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSpeaker))

        table.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(table)
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        applyMerged(seed)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Always refresh so the full catalog shows (TF194 #8 / TF200 #3).
        reload()
    }

    private func applyMerged(_ list: [NativeAPIClient.SpeakerDTO]) {
        // Cache is the source of truth for the registered catalog; seed/list only enrich.
        speakers = LocalNoteCache.mergeSpeakers(seed + list)
        table.reloadData()
    }

    private func reload() {
        applyMerged([])
        Task { @MainActor in
            do {
                let remote = try await NativeAPIClient.listSpeakers()
                applyMerged(remote)
            } catch {
                /* keep merged seed + cache */
            }
        }
    }

    @objc private func close() {
        onManaged?()
        dismiss(animated: true)
    }

    @objc private func addSpeaker() {
        let alert = UIAlertController(title: String(localized: "Novo speaker"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = String(localized: "Nome") }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Criar"), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            let colors = ["#c4a574", "#7a9e8a", "#8aa0b8", "#c4897a", "#9b8ab0", "#7aa8b0"]
            let speaker = NativeAPIClient.SpeakerDTO(
                id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                name: String(name.prefix(40)),
                color: colors.randomElement()!,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            Task { @MainActor in
                do {
                    try await NativeAPIClient.upsertSpeaker(speaker)
                    self?.reload()
                } catch {
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .manage: return speakers.count
        case .pick: return speakers.count + 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        switch mode {
        case .manage:
            config.text = speakers[indexPath.row].name
            cell.accessoryType = .none
        case .pick(let selectedId):
            if indexPath.row == 0 {
                config.text = String(localized: "Nenhum")
                cell.accessoryType = selectedId == nil ? .checkmark : .none
            } else {
                let speaker = speakers[indexPath.row - 1]
                config.text = speaker.name
                cell.accessoryType = selectedId == speaker.id ? .checkmark : .none
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case .pick = mode else { return }
        if indexPath.row == 0 {
            onPicked?(nil)
        } else {
            onPicked?(speakers[indexPath.row - 1].id)
        }
        dismiss(animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard case .manage = mode else { return nil }
        let speaker = speakers[indexPath.row]
        let delete = UIContextualAction.v2nIconOnly(
            style: .destructive,
            systemName: "trash",
            accessibilityLabel: String(localized: "Excluir")
        ) { [weak self] _, _, done in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteSpeaker(id: speaker.id)
                    self?.reload()
                    done(true)
                } catch {
                    done(false)
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
