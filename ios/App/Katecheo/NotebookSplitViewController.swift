import UIKit

/// Apple Notes–style Caderno: list + detail columns on regular width; push on compact.
/// Used as the Caderno tab root and when opening a group's notebook from Grupos.
final class NotebookSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    let listViewController: NotebookListViewController
    private let primaryNav: UINavigationController
    private var secondaryNav: UINavigationController
    private(set) var selectedNoteId: String?

    /// Personal Caderno (tab root).
    convenience init() {
        self.init(group: nil)
    }

    /// Group notebook (pushed from Grupos) or personal Caderno.
    init(group: NativeAPIClient.GroupDTO?) {
        if let group {
            listViewController = NotebookListViewController(group: group)
        } else {
            listViewController = NotebookListViewController()
        }
        primaryNav = UINavigationController(rootViewController: listViewController)
        KCChrome.style(navigationController: primaryNav)
        let empty = NotebookEmptyDetailViewController()
        secondaryNav = UINavigationController(rootViewController: empty)
        KCChrome.style(navigationController: secondaryNav)
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        presentsWithGesture = true
        if #available(iOS 14.5, *) {
            displayModeButtonVisibility = .automatic
        }
        if #available(iOS 16.0, *) {
            preferredSplitBehavior = .tile
        }
        setViewController(primaryNav, for: .primary)
        setViewController(secondaryNav, for: .secondary)
        // Same stack for compact — `show(.secondary)` pushes detail when collapsed.
        setViewController(primaryNav, for: .compact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        showEmptyDetail(animated: false)
    }

    // MARK: - Public routing

    /// Opens a note in the detail column (regular) or pushes via `show(.secondary)` (compact).
    func showNote(_ detail: NoteDetailViewController, animated: Bool) {
        let noteId = detail.openedNoteId
        selectedNoteId = noteId
        listViewController.highlightSelectedNote(id: noteId)
        detail.applyTabBarHidingForSplit(isCollapsed: isCollapsed)

        // Avoid stacking duplicate details for the same note on compact.
        if isCollapsed,
           let existing = primaryNav.viewControllers.compactMap({ $0 as? NoteDetailViewController }).last,
           existing.openedNoteId == noteId
        {
            return
        }

        let nav = UINavigationController(rootViewController: detail)
        KCChrome.style(navigationController: nav)
        secondaryNav = nav
        setViewController(nav, for: .secondary)
        // Collapsed: pushes secondary onto the compact (primary) nav. Expanded: shows column.
        show(.secondary)
        if !animated {
            // `show` is always animated by the system; no public non-animated API —
            // callers that need an immediate paint already forced layout via `view`.
        }
    }

    /// Clears the detail column back to the empty state (after delete / deselect).
    func showEmptyDetail(animated: Bool) {
        selectedNoteId = nil
        listViewController.highlightSelectedNote(id: nil)
        let empty = NotebookEmptyDetailViewController()
        let nav = UINavigationController(rootViewController: empty)
        KCChrome.style(navigationController: nav)
        secondaryNav = nav
        setViewController(nav, for: .secondary)

        if isCollapsed {
            primaryNav.popToRootViewController(animated: animated)
        }
    }

    /// After deleting the open note — empty secondary on regular; pop on compact.
    func clearDetailAfterDeletingNote(id: String) {
        if selectedNoteId == id || openDetailNoteId == id || selectedNoteId == nil {
            showEmptyDetail(animated: true)
            return
        }
        if isCollapsed {
            primaryNav.popViewController(animated: true)
        }
    }

    /// Reset to list root (deep links).
    func popToListRoot(animated: Bool) {
        primaryNav.popToRootViewController(animated: animated)
        showEmptyDetail(animated: false)
    }

    var openDetailNoteId: String? {
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            return detail.openedNoteId
        }
        if let detail = primaryNav.topViewController as? NoteDetailViewController {
            return detail.openedNoteId
        }
        return selectedNoteId
    }

    // MARK: - UISplitViewControllerDelegate

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingSecondary secondaryVC: UIViewController
    ) -> UISplitViewController.Column {
        if let nav = secondaryVC as? UINavigationController,
           nav.topViewController is NoteDetailViewController
        {
            return .secondary
        }
        return .primary
    }

    func splitViewController(
        _ svc: UISplitViewController,
        displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode
    ) -> UISplitViewController.DisplayMode {
        .oneBesideSecondary
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        if let detail = primaryNav.viewControllers.compactMap({ $0 as? NoteDetailViewController }).last {
            // Detail was pushed on the compact stack — move the same VC into secondary.
            primaryNav.popToRootViewController(animated: false)
            selectedNoteId = detail.openedNoteId
            listViewController.highlightSelectedNote(id: detail.openedNoteId)
            detail.applyTabBarHidingForSplit(isCollapsed: false)
            let nav = UINavigationController(rootViewController: detail)
            KCChrome.style(navigationController: nav)
            secondaryNav = nav
            setViewController(nav, for: .secondary)
            return
        }
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            selectedNoteId = detail.openedNoteId
            listViewController.highlightSelectedNote(id: detail.openedNoteId)
            detail.applyTabBarHidingForSplit(isCollapsed: false)
            return
        }
        if let id = selectedNoteId {
            listViewController.highlightSelectedNote(id: id)
            let cached = LocalNoteCache.loadNotes().first { $0.id == id }
            showNote(NoteDetailViewController(noteId: id, initial: cached), animated: false)
        } else {
            showEmptyDetail(animated: false)
        }
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            detail.applyTabBarHidingForSplit(isCollapsed: true)
        }
    }
}

// MARK: - Empty detail (regular width)

/// Polished empty state for the Caderno secondary column when no note is selected.
final class NotebookEmptyDetailViewController: UIViewController {
    private let empty = KCEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleCanvas(view)
        title = nil
        navigationItem.largeTitleDisplayMode = .never

        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            empty.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        empty.show(
            symbol: "note.text",
            title: String(localized: "Selecione uma nota"),
            message: String(localized: "Escolha uma nota na lista ao lado para abrir e editar.")
        )
        empty.isHidden = false
        empty.alpha = 1
        empty.transform = .identity
    }
}

extension NoteDetailViewController {
    /// Compact push hides the tab bar; regular secondary column keeps it visible.
    func applyTabBarHidingForSplit(isCollapsed: Bool) {
        hidesBottomBarWhenPushed = isCollapsed
    }
}
