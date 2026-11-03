import UIKit

/// Native note settings: title, date, tags, whole-note speaker.
final class NoteSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private var note: NativeAPIClient.NoteDocument
    private let speakers: [NativeAPIClient.SpeakerDTO]
    private let onSave: (NativeAPIClient.NoteDocument) -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let titleField = UITextField()
    private let datePicker = UIDatePicker()
    private let tagField = UITextField()

    init(note: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO], onSave: @escaping (NativeAPIClient.NoteDocument) -> Void) {
        self.note = note
        self.speakers = speakers
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Configurações"
        V2NChrome.styleCanvas(view)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancelar", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Pronto", style: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItem?.tintColor = V2NDesign.accent

        titleField.placeholder = "Título"
        titleField.text = note.title
        titleField.borderStyle = .roundedRect
        titleField.clearButtonMode = .whileEditing

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        let formatter = Self.dayFormatter
        if let date = formatter.date(from: note.happenedAt) {
            datePicker.date = date
        }

        tagField.placeholder = "Tag"
        tagField.borderStyle = .roundedRect
        tagField.autocapitalizationType = .none
        tagField.returnKeyType = .done
        tagField.addTarget(self, action: #selector(addTag), for: .editingDidEndOnExit)

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
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func done() {
        note.title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        note.happenedAt = Self.dayFormatter.string(from: datePicker.date)
        onSave(note)
        dismiss(animated: true)
    }

    @objc private func addTag() {
        let raw = (tagField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard !raw.isEmpty else { return }
        let tag = String(raw.prefix(24))
        if !note.tags.contains(tag) { note.tags.append(tag) }
        tagField.text = ""
        table.reloadSections(IndexSet(integer: 2), with: .automatic)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0, 1: return 1
        case 2: return note.tags.count + 1 // tags + add row
        case 3: return speakers.count + 1 // none + speakers
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Título"
        case 1: return "Data"
        case 2: return "Tags"
        case 3: return "Speaker da nota"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.contentConfiguration = nil
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        switch indexPath.section {
        case 0:
            cell.selectionStyle = .none
            embed(titleField, in: cell)
        case 1:
            cell.selectionStyle = .none
            datePicker.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(datePicker)
            NSLayoutConstraint.activate([
                datePicker.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                datePicker.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])
        case 2:
            if indexPath.row < note.tags.count {
                var config = cell.defaultContentConfiguration()
                config.text = "#\(note.tags[indexPath.row])"
                config.secondaryText = "Toque para remover"
                cell.contentConfiguration = config
            } else {
                cell.selectionStyle = .none
                embed(tagField, in: cell)
                let add = UIButton(type: .system)
                add.setTitle("＋", for: .normal)
                add.addTarget(self, action: #selector(addTag), for: .touchUpInside)
                cell.accessoryView = add
            }
        case 3:
            if indexPath.row == 0 {
                var config = cell.defaultContentConfiguration()
                config.text = "Nenhum"
                cell.contentConfiguration = config
                cell.accessoryType = note.noteSpeakerId == nil ? .checkmark : .none
            } else {
                let speaker = speakers[indexPath.row - 1]
                var config = cell.defaultContentConfiguration()
                config.text = speaker.name
                cell.contentConfiguration = config
                cell.accessoryType = note.noteSpeakerId == speaker.id ? .checkmark : .none
            }
        default:
            break
        }
        return cell
    }

    private func embed(_ field: UITextField, in cell: UITableViewCell) {
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
        ])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2, indexPath.row < note.tags.count {
            note.tags.remove(at: indexPath.row)
            tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
        }
        if indexPath.section == 3 {
            note.noteSpeakerId = indexPath.row == 0 ? nil : speakers[indexPath.row - 1].id
            tableView.reloadSections(IndexSet(integer: 3), with: .none)
        }
    }
}
