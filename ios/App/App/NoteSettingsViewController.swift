import UIKit

/// Native note settings: title, date, whole-note speaker (tags live under the title in the editor).
final class NoteSettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private var note: NativeAPIClient.NoteDocument
    private let speakers: [NativeAPIClient.SpeakerDTO]
    private let onSave: (NativeAPIClient.NoteDocument) -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let titleField = UITextField()
    private let datePicker = UIDatePicker()

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
        title = String(localized: "Configurações")
        // Match the note editor paper canvas (same screen family as NoteDetail).
        V2NChrome.styleCanvas(view)
        if let nav = navigationController {
            V2NChrome.applyNavigationBarAppearance(to: nav.navigationBar, background: V2NDesign.canvas)
            nav.view.backgroundColor = V2NDesign.canvas
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "Cancelar"), style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: String(localized: "Pronto"), style: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItem?.tintColor = V2NDesign.accent

        titleField.placeholder = String(localized: "Título")
        titleField.text = note.title
        titleField.borderStyle = .roundedRect
        titleField.clearButtonMode = .whileEditing

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.locale = .current
        datePicker.calendar = .current
        let formatter = Self.dayFormatter
        if let date = formatter.date(from: note.happenedAt) {
            datePicker.date = date
        }

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = V2NDesign.canvas
        table.backgroundView = UIView()
        table.backgroundView?.backgroundColor = V2NDesign.canvas
        table.separatorColor = V2NDesign.separator
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

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0, 1: return 1
        case 2: return speakers.count + 1 // none + speakers
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return String(localized: "Título")
        case 1: return String(localized: "Data")
        case 2: return String(localized: "Speaker da nota")
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

        // Note settings sits on canvas paper — surface cells still kill bluish template.
        cell.backgroundColor = V2NDesign.surface
        cell.contentView.backgroundColor = .clear
        var bg = UIBackgroundConfiguration.listGroupedCell()
        bg.backgroundColor = V2NDesign.surface
        cell.backgroundConfiguration = bg
        cell.tintColor = V2NDesign.accent

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
            if indexPath.row == 0 {
                var config = cell.defaultContentConfiguration()
                config.text = String(localized: "Nenhum")
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
        if indexPath.section == 2 {
            note.noteSpeakerId = indexPath.row == 0 ? nil : speakers[indexPath.row - 1].id
            tableView.reloadSections(IndexSet(integer: 2), with: .none)
        }
    }
}
