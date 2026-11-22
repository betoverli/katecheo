import UIKit

/// Chooses Grupos chrome: nav stack on iPhone; Notes-like triple column on iPad.
enum GroupsChrome {
    static func makeTabRoot() -> UIViewController {
        if PadChrome.isPad {
            return GroupsSplitViewController()
        }
        let list = GroupsListViewController()
        let nav = UINavigationController(rootViewController: list)
        KCChrome.style(navigationController: nav)
        return nav
    }
}

/// iPad Grupos: primary = groups list, supplementary = that group's Caderno notes,
/// secondary = note editor (empty until a note is opened). Compact collapses to push.
final class GroupsSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    let groupsListViewController = GroupsListViewController()
    private let primaryNav: UINavigationController
    private var supplementaryNav: UINavigationController
    private var secondaryNav: UINavigationController
    private(set) var selectedGroupId: String?
    private(set) var selectedNoteId: String?
    private weak var openGroupList: NotebookListViewController?

    init() {
        primaryNav = UINavigationController(rootViewController: groupsListViewController)
        KCChrome.style(navigationController: primaryNav)
        let emptyNotes = GroupsEmptyNotesViewController()
        supplementaryNav = UINavigationController(rootViewController: emptyNotes)
        KCChrome.style(navigationController: supplementaryNav)
        let emptyDetail = NotebookEmptyDetailViewController()
        secondaryNav = UINavigationController(rootViewController: emptyDetail)
        KCChrome.style(navigationController: secondaryNav)
        super.init(style: .tripleColumn)
        delegate = self
        preferredDisplayMode = .twoBesideSecondary
        presentsWithGesture = true
        if #available(iOS 14.5, *) {
            displayModeButtonVisibility = .automatic
        }
        if #available(iOS 16.0, *) {
            preferredSplitBehavior = .tile
        }
        preferredPrimaryColumnWidthFraction = PadChrome.groupsPrimaryFraction
        preferredSupplementaryColumnWidthFraction = PadChrome.groupsSupplementaryFraction
        minimumPrimaryColumnWidth = PadChrome.groupsColumnMin
        maximumPrimaryColumnWidth = PadChrome.groupsColumnMax
        minimumSupplementaryColumnWidth = PadChrome.groupsColumnMin
        maximumSupplementaryColumnWidth = PadChrome.groupsColumnMax

        setViewController(primaryNav, for: .primary)
        setViewController(supplementaryNav, for: .supplementary)
        setViewController(secondaryNav, for: .secondary)
        setViewController(primaryNav, for: .compact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        showEmptyGroupNotes(animated: false)
    }

    // MARK: - Routing

    /// Open a group's notes in the supplementary column (or push on compact).
    func showGroup(_ group: NativeAPIClient.GroupDTO, animated: Bool) {
        selectedGroupId = group.id
        selectedNoteId = nil
        groupsListViewController.highlightSelectedGroup(id: group.id)

        let list = NotebookListViewController(group: group)
        openGroupList = list

        if isCollapsed {
            // Compact: push group Caderno list onto primary (pre-triple push path).
            if let existing = primaryNav.viewControllers.compactMap({ $0 as? NotebookListViewController }).last,
               existing.title == group.name
            {
                return
            }
            // Pop any prior group list / note.
            primaryNav.popToRootViewController(animated: false)
            primaryNav.pushViewController(list, animated: animated)
            return
        }

        let nav = UINavigationController(rootViewController: list)
        KCChrome.style(navigationController: nav)
        supplementaryNav = nav
        setViewController(nav, for: .supplementary)
        showEmptyDetail(animated: false)
        show(.supplementary)
    }

    func showNote(_ detail: NoteDetailViewController, animated: Bool) {
        let noteId = detail.openedNoteId
        selectedNoteId = noteId
        openGroupList?.highlightSelectedNote(id: noteId)

        if isCollapsed {
            detail.applyTabBarHidingForSplit(isCollapsed: true)
            if let existing = primaryNav.viewControllers.compactMap({ $0 as? NoteDetailViewController }).last,
               existing.openedNoteId == noteId
            {
                return
            }
            if primaryNav.topViewController is NoteDetailViewController {
                primaryNav.popViewController(animated: false)
            }
            primaryNav.pushViewController(detail, animated: animated)
            return
        }

        detail.applyTabBarHidingForSplit(isCollapsed: false)
        let nav = UINavigationController(rootViewController: detail)
        KCChrome.style(navigationController: nav)
        detail.navigationItem.leftBarButtonItem = displayModeButtonItem
        secondaryNav = nav
        setViewController(nav, for: .secondary)
        show(.secondary)
    }

    func showEmptyDetail(animated: Bool) {
        selectedNoteId = nil
        openGroupList?.highlightSelectedNote(id: nil)
        let empty = NotebookEmptyDetailViewController()
        let nav = UINavigationController(rootViewController: empty)
        KCChrome.style(navigationController: nav)
        empty.navigationItem.leftBarButtonItem = displayModeButtonItem
        secondaryNav = nav
        setViewController(nav, for: .secondary)
        if isCollapsed {
            while primaryNav.topViewController is NoteDetailViewController {
                primaryNav.popViewController(animated: animated)
            }
        }
    }

    func showEmptyGroupNotes(animated: Bool) {
        selectedGroupId = nil
        selectedNoteId = nil
        openGroupList = nil
        groupsListViewController.highlightSelectedGroup(id: nil)
        let empty = GroupsEmptyNotesViewController()
        let nav = UINavigationController(rootViewController: empty)
        KCChrome.style(navigationController: nav)
        supplementaryNav = nav
        setViewController(nav, for: .supplementary)
        showEmptyDetail(animated: animated)
        if isCollapsed {
            primaryNav.popToRootViewController(animated: animated)
        }
    }

    func clearDetailAfterDeletingNote(id: String) {
        if selectedNoteId == id || selectedNoteId == nil {
            showEmptyDetail(animated: true)
        }
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
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        if secondaryNav.topViewController is NoteDetailViewController {
            return .secondary
        }
        if openGroupList != nil || supplementaryNav.topViewController is NotebookListViewController {
            return .supplementary
        }
        return .primary
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        // Rebuild supplementary / secondary from primary stack if we collapsed with content.
        var groupList: NotebookListViewController?
        var detail: NoteDetailViewController?
        for vc in primaryNav.viewControllers {
            if let list = vc as? NotebookListViewController { groupList = list }
            if let note = vc as? NoteDetailViewController { detail = note }
        }
        primaryNav.popToRootViewController(animated: false)
        if let groupList, let groupId = selectedGroupId {
            openGroupList = groupList
            let nav = UINavigationController(rootViewController: groupList)
            KCChrome.style(navigationController: nav)
            supplementaryNav = nav
            setViewController(nav, for: .supplementary)
            groupsListViewController.highlightSelectedGroup(id: groupId)
        }
        if let detail {
            showNote(detail, animated: false)
        } else {
            showEmptyDetail(animated: false)
        }
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // Fold supplementary list + secondary note onto primary.
        if let list = supplementaryNav.topViewController as? NotebookListViewController {
            openGroupList = list
            if !(primaryNav.viewControllers.contains(where: { $0 === list })) {
                primaryNav.pushViewController(list, animated: false)
            }
        }
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            detail.applyTabBarHidingForSplit(isCollapsed: true)
            let placeholder = UINavigationController(rootViewController: NotebookEmptyDetailViewController())
            KCChrome.style(navigationController: placeholder)
            secondaryNav = placeholder
            setViewController(placeholder, for: .secondary)
            if !(primaryNav.topViewController is NoteDetailViewController) {
                primaryNav.pushViewController(detail, animated: false)
            }
        }
    }
}

// MARK: - Empty supplementary (no group selected)

final class GroupsEmptyNotesViewController: UIViewController {
    private let empty = KCEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Notas do grupo")
        navigationItem.largeTitleDisplayMode = .always

        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            empty.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        empty.show(
            symbol: "person.2",
            title: String(localized: "Selecione um grupo"),
            message: String(localized: "Escolha um grupo na lista ao lado para ver as notas publicadas.")
        )
        empty.isHidden = false
        empty.alpha = 1
        empty.transform = .identity
    }
}
