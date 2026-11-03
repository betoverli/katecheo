import UIKit

/// Placeholder tab (Leitura) until a later native phase. No web-host fallback.
final class ComingSoonTabViewController: UIViewController {
    private let titleText: String
    private let systemImage: String
    private let detailText: String
    private let empty = V2NEmptyStateView()

    init(titleText: String, systemImage: String, detailText: String = String(localized: "Em breve nativo.")) {
        self.titleText = titleText
        self.systemImage = systemImage
        self.detailText = detailText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = titleText
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true

        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            empty.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let parts = detailText.components(separatedBy: "\n")
        let titleLine = parts.first ?? detailText
        let message = parts.dropFirst().joined(separator: "\n")
        empty.show(symbol: systemImage, title: titleLine, message: message)
        empty.isHidden = false
    }
}
