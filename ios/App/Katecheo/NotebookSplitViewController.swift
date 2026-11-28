import UIKit

/// Chooses Caderno chrome: pre-#131 nav stack on iPhone; Notes-style split on iPad.
/// Using `UIDevice` idiom (not size class) so iPhone never mounts a split — TF 460
/// proved double-column `show(.secondary)` fails to open notes on phone.
enum NotebookChrome {
    /// iPad only. iPhone keeps the exact pre-#131 hierarchy.
    static var prefersSplit: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Caderno tab root.
    static func makeTabRoot() -> UIViewController {
        if prefersSplit {
            return NotebookSplitViewController()
        }
        let list = NotebookListViewController()
        let nav = UINavigationController(rootViewController: list)
        KCChrome.style(navigationController: nav)
        return nav
    }

    /// Group Caderno pushed from Grupos / deep links / invites.
    static func makeGroupCaderno(group: NativeAPIClient.GroupDTO) -> UIViewController {
        if prefersSplit {
            return NotebookSplitViewController(group: group)
        }
        return NotebookListViewController(group: group)
    }
}

/// Apple Notes–style Caderno on iPad: list + detail columns on regular width;
/// compact (narrow Split View / Stage Manager) pushes onto the primary nav.
final class NotebookSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    let listViewController: NotebookListViewController
    private let primaryNav: UINavigationController
    private var secondaryNav: UINavigationController
    private(set) var selectedNoteId: String?

    /// Personal Caderno (tab root on iPad).
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
        // Tile beside — never overlay the note detail under the list (TF 499).
        PadChrome.applyNotesFolderSplitChrome(to: self)
        setViewController(primaryNav, for: .primary)
        setViewController(secondaryNav, for: .secondary)
        // Compact column is the same primary nav so collapse can push detail there.
        setViewController(primaryNav, for: .compact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        view.accessibilityIdentifier = "caderno.split"
        primaryNav.view.accessibilityIdentifier = "caderno.split.primary"
        secondaryNav.view.accessibilityIdentifier = "caderno.split.secondary"
        showEmptyDetail(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        PadChrome.enforceBesideDisplayMode(on: self)
    }

    // MARK: - Public routing

    /// Regular: show in secondary column. Compact: push onto primary nav (tab bar hides).
    func showNote(_ detail: NoteDetailViewController, animated: Bool) {
        let noteId = detail.openedNoteId
        selectedNoteId = noteId
        listViewController.highlightSelectedNote(id: noteId)

        if isCollapsed {
            detail.applyTabBarHidingForSplit(isCollapsed: true)
            // Explicit push — do not rely on `show(.secondary)` (broken on some compact paths).
            if let existing = primaryNav.viewControllers.compactMap({ $0 as? NoteDetailViewController }).last,
               existing.openedNoteId == noteId
            {
                return
            }
            if primaryNav.topViewController is NoteDetailViewController {
                primaryNav.popViewController(animated: false)
            }
            // Keep secondary as empty placeholder so expand has a clean column.
            let placeholder = UINavigationController(rootViewController: NotebookEmptyDetailViewController())
            KCChrome.style(navigationController: placeholder)
            secondaryNav = placeholder
            setViewController(placeholder, for: .secondary)
            primaryNav.pushViewController(detail, animated: animated)
            return
        }

        detail.applyTabBarHidingForSplit(isCollapsed: false)
        let nav = UINavigationController(rootViewController: detail)
        KCChrome.style(navigationController: nav)
        nav.view.accessibilityIdentifier = "caderno.split.secondary"
        // Do not assign displayModeButtonItem — primary already has the sidebar control.
        detail.navigationItem.leftBarButtonItem = nil
        secondaryNav = nav
        setViewController(nav, for: .secondary)
        // Do not call `show(.secondary)` — on recent iPadOS it flips preferredDisplayMode
        // to `.secondaryOnly` and the list overlays / hides under the detail (TF 499).
        PadChrome.applyNotesFolderSplitChrome(to: self)
        detail.ensureEditorContentVisible()
    }

    /// Clears the detail column back to the empty state (after delete / deselect).
    func showEmptyDetail(animated: Bool) {
        selectedNoteId = nil
        listViewController.highlightSelectedNote(id: nil)
        let empty = NotebookEmptyDetailViewController()
        let nav = UINavigationController(rootViewController: empty)
        KCChrome.style(navigationController: nav)
        nav.view.accessibilityIdentifier = "caderno.split.secondary"
        empty.navigationItem.leftBarButtonItem = nil
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

    /// Classic collapse path: fold an open note into the primary nav stack.
    func splitViewController(
        _ splitViewController: UISplitViewController,
        collapseSecondary secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        guard let secondary = secondaryViewController as? UINavigationController,
              let detail = secondary.topViewController as? NoteDetailViewController
        else {
            // Empty secondary — stay on list.
            return true
        }
        detail.applyTabBarHidingForSplit(isCollapsed: true)
        if let primary = primaryViewController as? UINavigationController {
            primary.pushViewController(detail, animated: false)
        }
        selectedNoteId = detail.openedNoteId
        return true
    }

    func splitViewController(
        _ svc: UISplitViewController,
        displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode
    ) -> UISplitViewController.DisplayMode {
        .oneBesideSecondary
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        if let detail = primaryNav.viewControllers.compactMap({ $0 as? NoteDetailViewController }).last {
            primaryNav.popToRootViewController(animated: false)
            selectedNoteId = detail.openedNoteId
            listViewController.highlightSelectedNote(id: detail.openedNoteId)
            detail.applyTabBarHidingForSplit(isCollapsed: false)
            let nav = UINavigationController(rootViewController: detail)
            KCChrome.style(navigationController: nav)
            nav.view.accessibilityIdentifier = "caderno.split.secondary"
            detail.navigationItem.leftBarButtonItem = nil
            secondaryNav = nav
            setViewController(nav, for: .secondary)
            PadChrome.applyNotesFolderSplitChrome(to: self)
            detail.ensureEditorContentVisible()
            return
        }
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            selectedNoteId = detail.openedNoteId
            listViewController.highlightSelectedNote(id: detail.openedNoteId)
            detail.applyTabBarHidingForSplit(isCollapsed: false)
            detail.navigationItem.leftBarButtonItem = nil
            detail.ensureEditorContentVisible()
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
            // Move note onto primary if still sitting in secondary.
            detail.applyTabBarHidingForSplit(isCollapsed: true)
            if !(primaryNav.topViewController is NoteDetailViewController) {
                let placeholder = UINavigationController(rootViewController: NotebookEmptyDetailViewController())
                KCChrome.style(navigationController: placeholder)
                secondaryNav = placeholder
                setViewController(placeholder, for: .secondary)
                primaryNav.pushViewController(detail, animated: false)
            }
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
