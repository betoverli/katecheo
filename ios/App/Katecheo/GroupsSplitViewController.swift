import UIKit

/// Chooses Grupos chrome: nav stack on iPhone; Notes-folder 2-column split on iPad.
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

/// iPad Grupos: double-column like Caderno / Apple Notes folders.
/// Primary sidebar: groups list; tapping a group **pushes** that group's notes onto the
/// same sidebar (back → groups). Secondary: note editor (empty until a note is opened).
/// Compact collapses to the classic push stack.
final class GroupsSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    let groupsListViewController = GroupsListViewController()
    private let primaryNav: UINavigationController
    private var secondaryNav: UINavigationController
    private(set) var selectedGroupId: String?
    private(set) var selectedNoteId: String?
    private weak var openGroupList: NotebookListViewController?

    init() {
        primaryNav = UINavigationController(rootViewController: groupsListViewController)
        KCChrome.style(navigationController: primaryNav)
        let emptyDetail = NotebookEmptyDetailViewController()
        secondaryNav = UINavigationController(rootViewController: emptyDetail)
        KCChrome.style(navigationController: secondaryNav)
        super.init(style: .doubleColumn)
        delegate = self
        // Tile beside — never overlay the note detail under the list (TF 499).
        PadChrome.applyNotesFolderSplitChrome(to: self)

        setViewController(primaryNav, for: .primary)
        setViewController(secondaryNav, for: .secondary)
        setViewController(primaryNav, for: .compact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        view.accessibilityIdentifier = "grupos.split"
        stampColumnAccessibilityIds()
        showEmptyDetail(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        PadChrome.enforceBesideDisplayMode(on: self)
        PadChrome.syncColumnAccessibilityFrames(on: self)
    }

    // MARK: - Routing

    /// Push the group's notes list onto the **primary** sidebar (Notes-folder pattern).
    func showGroup(_ group: NativeAPIClient.GroupDTO, animated: Bool) {
        selectedGroupId = group.id
        selectedNoteId = nil
        groupsListViewController.highlightSelectedGroup(id: nil)

        // Already showing this group's notes — keep stack, just clear detail.
        if let existing = openGroupList, existing.testing_groupId == group.id,
           primaryNav.viewControllers.contains(where: { $0 === existing })
        {
            showEmptyDetail(animated: false)
            return
        }

        let list = NotebookListViewController(group: group)
        openGroupList = list

        if isCollapsed {
            primaryNav.popToRootViewController(animated: false)
            primaryNav.pushViewController(list, animated: animated)
            return
        }

        // Regular: replace any prior group notes VC, push onto primary (back → Grupos).
        if primaryNav.viewControllers.count > 1 {
            primaryNav.popToRootViewController(animated: false)
        }
        primaryNav.pushViewController(list, animated: animated)
        showEmptyDetail(animated: false)
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
        // Reuse the secondary column nav — replacing it resets panel frames (TF 499).
        installSecondaryRoot(detail, animated: animated)
        detail.ensureEditorContentVisible()
    }

    func showEmptyDetail(animated: Bool) {
        selectedNoteId = nil
        openGroupList?.highlightSelectedNote(id: nil)
        installSecondaryRoot(NotebookEmptyDetailViewController(), animated: animated)
        if isCollapsed {
            while primaryNav.topViewController is NoteDetailViewController {
                primaryNav.popViewController(animated: animated)
            }
        }
    }

    /// Swap the secondary column's root without recreating the column host VC.
    private func installSecondaryRoot(_ root: UIViewController, animated: Bool) {
        root.navigationItem.leftBarButtonItem = nil
        if viewController(for: .secondary) !== secondaryNav {
            setViewController(secondaryNav, for: .secondary)
        }
        secondaryNav.setViewControllers([root], animated: animated)
        stampColumnAccessibilityIds()
        // Avoid `show(.secondary)` — it can force `.secondaryOnly` and break tile (TF 499).
        PadChrome.applyNotesFolderSplitChrome(to: self)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        PadChrome.syncColumnAccessibilityFrames(on: self)
    }

    private func stampColumnAccessibilityIds() {
        primaryNav.view.accessibilityIdentifier = "grupos.split.primary"
        secondaryNav.view.accessibilityIdentifier = "grupos.split.secondary"
        primaryNav.view.isAccessibilityElement = true
        secondaryNav.view.isAccessibilityElement = true
    }

    func clearDetailAfterDeletingNote(id: String) {
        if selectedNoteId == id || selectedNoteId == nil {
            showEmptyDetail(animated: true)
        }
    }

    /// Pop group notes back to the groups list (sidebar root).
    func popToGroupsList(animated: Bool) {
        selectedGroupId = nil
        selectedNoteId = nil
        openGroupList = nil
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

    var openGroupNotesList: NotebookListViewController? { openGroupList }

    // MARK: - UISplitViewControllerDelegate

    func splitViewController(
        _ splitViewController: UISplitViewController,
        collapseSecondary secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        guard let secondary = secondaryViewController as? UINavigationController,
              let detail = secondary.topViewController as? NoteDetailViewController
        else {
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
        // Rebuild secondary from a note that was pushed onto primary while collapsed.
        var detail: NoteDetailViewController?
        var groupList: NotebookListViewController?
        for vc in primaryNav.viewControllers {
            if let list = vc as? NotebookListViewController { groupList = list }
            if let note = vc as? NoteDetailViewController { detail = note }
        }
        // Keep groups root + optional group notes; strip note from primary.
        var keep: [UIViewController] = [groupsListViewController]
        if let groupList {
            openGroupList = groupList
            keep.append(groupList)
        }
        primaryNav.setViewControllers(keep, animated: false)
        if let detail {
            showNote(detail, animated: false)
        } else {
            showEmptyDetail(animated: false)
        }
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        if let detail = secondaryNav.topViewController as? NoteDetailViewController {
            detail.applyTabBarHidingForSplit(isCollapsed: true)
            if !(primaryNav.topViewController is NoteDetailViewController) {
                installSecondaryRoot(NotebookEmptyDetailViewController(), animated: false)
                primaryNav.pushViewController(detail, animated: false)
            }
        }
    }
}
