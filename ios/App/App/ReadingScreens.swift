import UIKit

/// Native Leitura: browse plans, track days, share invites.
/// Opened from Ferramentas (Tools); `embedded` kept for compatibility / deep-link pushes.
/// Layout mirrors the original web reading page — category card grid + plan rows.
final class ReadingHomeViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UISearchResultsUpdating, UISearchBarDelegate {
    private let refresh = UIRefreshControl()
    private let emptyState = V2NEmptyStateView()
    private let search = UISearchController(searchResultsController: nil)
    private let embeddedSearch = UISearchBar()
    private var collectionView: UICollectionView!
    private let embedded: Bool

    private var categories: [NativeAPIClient.PlanCategoryDTO] = []
    private var plans: [NativeAPIClient.PlanCardDTO] = []
    private var myPlans: [NativeAPIClient.PlanCardDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var planTotal = 0
    private var searching = false

    private enum Section: Int {
        case mine, browse, all, searchCategories, searchPlans
    }

    init(embedded: Bool = false) {
        self.embedded = embedded
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        if !embedded {
            title = String(localized: "Leitura")
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .always
        } else {
            // Parent Versículos owns the large title + chips.
            navigationItem.largeTitleDisplayMode = .never
        }

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar planos")
        if embedded {
            embeddedSearch.placeholder = String(localized: "Buscar planos")
            embeddedSearch.delegate = self
            embeddedSearch.searchBarStyle = .minimal
            embeddedSearch.translatesAutoresizingMaskIntoConstraints = false
            embeddedSearch.autocapitalizationType = .none
            embeddedSearch.returnKeyType = .search
        } else {
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = true
            definesPresentationContext = true
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(V2NPlanCategoryCardCell.self, forCellWithReuseIdentifier: V2NPlanCategoryCardCell.reuseId)
        collectionView.register(V2NPlanRowCardCell.self, forCellWithReuseIdentifier: V2NPlanRowCardCell.reuseId)
        collectionView.register(V2NPlanLinkCardCell.self, forCellWithReuseIdentifier: V2NPlanLinkCardCell.reuseId)
        collectionView.register(
            V2NReadingSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: V2NReadingSectionHeader.reuseId
        )
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        collectionView.refreshControl = refresh
        view.addSubview(collectionView)
        view.addSubview(emptyState)

        if embedded {
            view.addSubview(embeddedSearch)
            NSLayoutConstraint.activate([
                embeddedSearch.topAnchor.constraint(equalTo: view.topAnchor, constant: V2NDesign.Space.xxs),
                embeddedSearch.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                embeddedSearch.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

                collectionView.topAnchor.constraint(equalTo: embeddedSearch.bottomAnchor, constant: V2NDesign.Space.xxs),
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                emptyState.topAnchor.constraint(equalTo: embeddedSearch.bottomAnchor),
                emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !embedded {
            reload()
        }
    }

    func reloadFromParent() {
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            let rawQuery: String
            if embedded {
                rawQuery = embeddedSearch.text ?? ""
            } else {
                rawQuery = search.searchBar.text ?? ""
            }
            let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            searching = !q.isEmpty
            do {
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                } else {
                    prefs = nil
                }
                let index = try await NativeAPIClient.fetchReadingPlans(query: searching ? q : nil)
                planTotal = index.planTotal ?? index.plans.count
                categories = index.categories
                plans = index.plans
                let active = prefs?.activePlans ?? []
                if searching {
                    myPlans = []
                } else if !active.isEmpty {
                    var mine: [NativeAPIClient.PlanCardDTO] = []
                    for id in active.prefix(20) {
                        if let cached = plans.first(where: { $0.id == id }) {
                            mine.append(cached)
                        } else if let detail = try? await NativeAPIClient.fetchReadingPlans(planId: id), let plan = detail.plan {
                            mine.append(plan)
                        }
                    }
                    myPlans = mine
                    let browse = try await NativeAPIClient.fetchReadingPlans()
                    categories = browse.categories
                    plans = browse.plans
                    planTotal = browse.planTotal ?? browse.plans.count
                } else {
                    myPlans = []
                }
                emptyState.hide()
                collectionView.isHidden = false
                collectionView.reloadData()
            } catch {
                collectionView.isHidden = true
                emptyState.show(
                    symbol: "calendar",
                    title: String(localized: "Não foi possível carregar"),
                    message: error.localizedDescription,
                    actionTitle: String(localized: "Tentar de novo"),
                    action: { [weak self] in self?.reload() }
                )
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        reload()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        reload()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        reload()
    }

    private func sectionKind(_ section: Int) -> Section? {
        if searching {
            var i = 0
            if !categories.isEmpty {
                if section == i { return .searchCategories }
                i += 1
            }
            if section == i { return .searchPlans }
            return nil
        }
        var i = 0
        if !myPlans.isEmpty {
            if section == i { return .mine }
            i += 1
        }
        if section == i { return .browse }
        i += 1
        if section == i { return .all }
        return nil
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, env in
            guard let self, let kind = self.sectionKind(sectionIndex) else {
                return Self.listSection(height: 56)
            }
            switch kind {
            case .browse, .searchCategories:
                return Self.categoryGridSection(env: env)
            case .mine, .searchPlans, .all:
                return Self.listSection(height: kind == .all ? 64 : 60)
            }
        }
    }

    private static func categoryGridSection(env: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let columns: CGFloat = env.container.effectiveContentSize.width > 700 ? 3 : 2
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1 / columns), heightDimension: .absolute(132))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(132)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 8, trailing: 10)
        section.boundarySupplementaryItems = [Self.sectionHeader()]
        return section
    }

    private static func listSection(height: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height + 8)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0)
        section.boundarySupplementaryItems = [Self.sectionHeader()]
        return section
    }

    private static func sectionHeader() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(28)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if searching {
            return (categories.isEmpty ? 0 : 1) + 1
        }
        return (myPlans.isEmpty ? 0 : 1) + 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch sectionKind(section) {
        case .mine: return myPlans.count
        case .browse, .searchCategories: return categories.count
        case .all: return 1
        case .searchPlans: return max(plans.count, 1)
        case .none: return 0
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: V2NReadingSectionHeader.reuseId,
            for: indexPath
        ) as! V2NReadingSectionHeader
        switch sectionKind(indexPath.section) {
        case .mine: header.configure(String(localized: "Meus planos"))
        case .browse: header.configure(String(localized: "Explorar"))
        case .searchCategories: header.configure(String(localized: "Categorias"))
        case .searchPlans: header.configure(String(localized: "Planos"))
        case .all, .none: header.configure(nil)
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch sectionKind(indexPath.section) {
        case .mine:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NPlanRowCardCell.reuseId, for: indexPath) as! V2NPlanRowCardCell
            let plan = myPlans[indexPath.item]
            cell.configure(plan: plan, progress: prefs?.planProgress?[plan.id] ?? [])
            return cell
        case .browse, .searchCategories:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NPlanCategoryCardCell.reuseId, for: indexPath) as! V2NPlanCategoryCardCell
            cell.configure(categories[indexPath.item])
            return cell
        case .all:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NPlanLinkCardCell.reuseId, for: indexPath) as! V2NPlanLinkCardCell
            cell.configure(
                title: String(localized: "Todos os planos"),
                subtitle: String(localized: "\(planTotal) planos"),
                symbol: "calendar"
            )
            return cell
        case .searchPlans:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NPlanRowCardCell.reuseId, for: indexPath) as! V2NPlanRowCardCell
            if plans.isEmpty {
                cell.configureEmpty(String(localized: "Nenhum plano encontrado"))
            } else {
                let plan = plans[indexPath.item]
                cell.configure(plan: plan, progress: prefs?.planProgress?[plan.id] ?? [])
            }
            return cell
        case .none:
            return collectionView.dequeueReusableCell(withReuseIdentifier: V2NPlanRowCardCell.reuseId, for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        V2NHaptics.selection()
        switch sectionKind(indexPath.section) {
        case .mine:
            openPlan(myPlans[indexPath.item].id)
        case .browse, .searchCategories:
            let category = categories[indexPath.item]
            navigationController?.pushViewController(
                ReadingPlanListViewController(mode: .category(category)),
                animated: true
            )
        case .all:
            navigationController?.pushViewController(
                ReadingPlanListViewController(mode: .all(total: planTotal)),
                animated: true
            )
        case .searchPlans:
            guard !plans.isEmpty else { return }
            openPlan(plans[indexPath.item].id)
        case .none:
            break
        }
    }

    private func openPlan(_ id: String) {
        navigationController?.pushViewController(ReadingPlanDetailViewController(planId: id), animated: true)
    }
}

// MARK: - Plan list (all / category)

final class ReadingPlanListViewController: UITableViewController {
    enum Mode {
        case all(total: Int)
        case category(NativeAPIClient.PlanCategoryDTO)
    }

    private let mode: Mode
    private var plans: [NativeAPIClient.PlanCardDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?

    init(mode: Mode) {
        self.mode = mode
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        switch mode {
        case .all:
            title = String(localized: "Todos os planos")
        case .category(let category):
            title = category.name
        }
        tableView.register(V2NPlanRowTableCell.self, forCellReuseIdentifier: V2NPlanRowTableCell.reuseId)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refreshControl?.endRefreshing() }
            prefs = NativeAPIClient.hasBearer ? try? await NativeAPIClient.getPrefs() : nil
            do {
                let result: NativeAPIClient.PlansIndexProxy
                switch mode {
                case .all:
                    result = try await NativeAPIClient.fetchReadingPlans()
                    plans = result.plans
                    if plans.isEmpty {
                        var seen = Set<String>()
                        var all: [NativeAPIClient.PlanCardDTO] = []
                        for category in result.categories {
                            let page = try await NativeAPIClient.fetchReadingPlans(categoryId: category.id)
                            for plan in page.plans where seen.insert(plan.id).inserted {
                                all.append(plan)
                            }
                        }
                        plans = all
                    }
                case .category(let category):
                    result = try await NativeAPIClient.fetchReadingPlans(categoryId: category.id)
                    plans = result.plans
                }
                tableView.reloadData()
            } catch {
                let alert = UIAlertController(title: String(localized: "Planos"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(plans.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: V2NPlanRowTableCell.reuseId, for: indexPath) as! V2NPlanRowTableCell
        if plans.isEmpty {
            cell.configureEmpty(String(localized: "Nenhum plano nesta categoria"))
        } else {
            let plan = plans[indexPath.row]
            cell.configure(plan: plan, progress: prefs?.planProgress?[plan.id] ?? [])
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !plans.isEmpty else { return }
        navigationController?.pushViewController(
            ReadingPlanDetailViewController(planId: plans[indexPath.row].id),
            animated: true
        )
    }
}

// MARK: - Plan detail / tracker

final class ReadingPlanDetailViewController: UITableViewController {
    private let planId: String
    private var plan: NativeAPIClient.PlanCardDTO?
    private var days: [NativeAPIClient.PlanDayDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var marked = Set<Int>()
    private var isActive = false

    init(planId: String) {
        self.planId = planId
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = String(localized: "Plano")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(sharePlan)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Compartilhar")
        reload()
    }

    private func reload() {
        Task { @MainActor in
            do {
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                }
                let detail = try await NativeAPIClient.fetchReadingPlans(planId: planId)
                plan = detail.plan
                title = detail.plan?.name ?? String(localized: "Plano")
                days = detail.days
                isActive = (prefs?.activePlans ?? []).contains(planId)
                marked = Set(prefs?.planProgress?[planId] ?? [])
                tableView.reloadData()
            } catch {
                let alert = UIAlertController(title: String(localized: "Plano"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private var sections: Int {
        // 0: header/stats/cta, 1: days (if active), 2: footer actions
        isActive ? 3 : 1
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return isActive ? 2 : 3 } // desc + progress|stats + CTA
        if section == 1, isActive { return days.count }
        if section == 2, isActive { return marked.isEmpty ? 1 : 2 }
        return 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1, isActive { return String(localized: "Dias") }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.backgroundColor = V2NDesign.surface

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                config.text = plan?.description ?? String(localized: "Plano de leitura")
                config.secondaryText = nil
                cell.selectionStyle = .none
            } else if indexPath.row == 1 {
                let done = marked.count
                let total = plan?.days ?? days.count
                let chapters = plan?.chapters ?? 0
                if isActive {
                    config.text = String(localized: "Progresso")
                    config.secondaryText = String(localized: "\(done) / \(total) dias")
                } else {
                    config.text = String(localized: "\(total) dias")
                    config.secondaryText = chapters > 0
                        ? String(localized: "\(chapters) capítulos")
                        : nil
                }
                cell.selectionStyle = .none
            } else {
                config.text = NativeAPIClient.hasBearer
                    ? String(localized: "Escolher este plano")
                    : String(localized: "Entrar para começar")
                config.image = UIImage(systemName: "checkmark.circle")
                config.textProperties.color = V2NDesign.accent
            }
        } else if indexPath.section == 1 {
            let day = days[indexPath.row]
            let done = marked.contains(day.day)
            config.text = String(localized: "DIA \(day.day)")
            config.secondaryText = day.labels.isEmpty ? String(localized: "Toque para marcar") : day.labels.joined(separator: " · ")
            config.image = UIImage(systemName: done ? "checkmark.circle.fill" : "circle")
            config.imageProperties.tintColor = done ? V2NDesign.accent : .secondaryLabel
            cell.accessoryType = .detailButton
        } else {
            if indexPath.row == 0, !marked.isEmpty {
                config.text = String(localized: "Recomeçar plano")
                config.textProperties.color = .systemOrange
            } else {
                config.text = String(localized: "Tirar dos meus planos")
                config.textProperties.color = V2NDesign.danger
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if !isActive, indexPath.row == 2 {
                startPlan()
            }
            return
        }
        if indexPath.section == 1 {
            toggleDay(days[indexPath.row].day)
            return
        }
        if indexPath.section == 2 {
            if indexPath.row == 0, !marked.isEmpty {
                resetPlan()
            } else {
                stopPlan()
            }
        }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        openDay(days[indexPath.row].day)
    }

    private func startPlan() {
        guard NativeAPIClient.hasBearer else {
            presentAlert(title: String(localized: "Entrar"), message: String(localized: "Inicie sessão para acompanhar o plano."))
            return
        }
        Task { @MainActor in
            do {
                prefs = try await NativeAPIClient.startReadingPlan(planId)
                isActive = true
                marked = Set(prefs?.planProgress?[planId] ?? [])
                V2NHaptics.success()
                tableView.reloadData()
            } catch {
                presentAlert(title: String(localized: "Plano"), message: error.localizedDescription)
            }
        }
    }

    private func stopPlan() {
        Task { @MainActor in
            do {
                prefs = try await NativeAPIClient.stopReadingPlan(planId)
                isActive = false
                tableView.reloadData()
            } catch {
                presentAlert(title: String(localized: "Plano"), message: error.localizedDescription)
            }
        }
    }

    private func resetPlan() {
        Task { @MainActor in
            do {
                try await NativeAPIClient.resetReadingPlanMarks(planId: planId)
                marked = []
                prefs = try? await NativeAPIClient.getPrefs()
                tableView.reloadData()
            } catch {
                presentAlert(title: String(localized: "Plano"), message: error.localizedDescription)
            }
        }
    }

    private func toggleDay(_ day: Int) {
        let on = !marked.contains(day)
        Task { @MainActor in
            do {
                try await NativeAPIClient.markReadingPlanDay(planId: planId, day: day, on: on)
                if on { marked.insert(day) } else { marked.remove(day) }
                V2NHaptics.selection()
                tableView.reloadData()
            } catch {
                presentAlert(title: String(localized: "Marcação"), message: error.localizedDescription)
            }
        }
    }

    private func openDay(_ day: Int) {
        Task { @MainActor in
            do {
                let page = try await NativeAPIClient.fetchReadingPlans(planId: planId, day: day)
                let labels = page.labels
                let sheet = UIAlertController(
                    title: String(localized: "DIA \(day)"),
                    message: labels.isEmpty ? nil : labels.joined(separator: "\n"),
                    preferredStyle: .actionSheet
                )
                if let first = page.items.first, let url = URL(string: first.url) {
                    sheet.addAction(UIAlertAction(title: String(localized: "Abrir na Bíblia"), style: .default) { _ in
                        UIApplication.shared.open(url)
                    })
                }
                sheet.addAction(UIAlertAction(title: String(localized: "Copiar"), style: .default) { _ in
                    UIPasteboard.general.string = labels.joined(separator: ", ")
                })
                sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = tableView
                }
                present(sheet, animated: true)
            } catch {
                presentAlert(title: String(localized: "Dia"), message: error.localizedDescription)
            }
        }
    }

    @objc private func sharePlan() {
        guard NativeAPIClient.hasBearer else {
            presentAlert(title: String(localized: "Entrar"), message: String(localized: "Inicie sessão para compartilhar o plano."))
            return
        }
        Task { @MainActor in
            do {
                let id = try await NativeAPIClient.createReadingPlanInvite(planId: planId)
                let url = NativeAPIClient.baseURL.appendingPathComponent("g/\(id)")
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let pop = vc.popoverPresentationController {
                    pop.barButtonItem = navigationItem.rightBarButtonItem
                }
                present(vc, animated: true)
            } catch {
                presentAlert(title: String(localized: "Compartilhar"), message: error.localizedDescription)
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Reading card cells (match original web category grid + plan rows)

enum V2NReadingSymbols {
    static func category(_ id: String) -> String {
        switch id {
        case "duration": return "clock"
        case "gospels": return "book"
        case "new-testament", "old-testament": return "book.closed"
        case "books": return "books.vertical"
        case "themes": return "tag"
        case "chronological": return "calendar"
        default: return "calendar"
        }
    }
}

final class V2NReadingSectionHeader: UICollectionReusableView {
    static let reuseId = "V2NReadingSectionHeader"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = V2NDesign.sectionHeader()
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ title: String?) {
        label.text = title?.uppercased()
        isHidden = title == nil
    }
}

/// Tall category card — 2-column grid like the web `CategoryGrid`.
final class V2NPlanCategoryCardCell: UICollectionViewCell {
    static let reuseId = "V2NPlanCategoryCardCell"
    private let card = UIView()
    private let iconWrap = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = V2NDesign.surface
        card.layer.cornerRadius = V2NDesign.Radius.lg
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.groupedBackground
        iconWrap.layer.cornerRadius = V2NDesign.Radius.sm
        iconWrap.layer.cornerCurve = .continuous
        card.addSubview(iconWrap)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel
        iconWrap.addSubview(iconView)

        titleLabel.font = V2NDesign.preferred(.subheadline, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = V2NDesign.caption()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconWrap.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconWrap.widthAnchor.constraint(equalToConstant: 40),
            iconWrap.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -4),

            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ category: NativeAPIClient.PlanCategoryDTO) {
        titleLabel.text = category.name
        let count = category.count ?? 0
        subtitleLabel.text = String(localized: "\(count) planos")
        iconView.image = UIImage(systemName: V2NReadingSymbols.category(category.id))
        accessibilityLabel = "\(category.name). \(subtitleLabel.text ?? "")"
    }
}

/// Single plan row card (name + days / progress).
final class V2NPlanRowCardCell: UICollectionViewCell {
    static let reuseId = "V2NPlanRowCardCell"
    private let card = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        Self.style(card: card, title: titleLabel, subtitle: subtitleLabel, chevron: chevron, in: contentView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(plan: NativeAPIClient.PlanCardDTO, progress: [Int]) {
        titleLabel.text = plan.name
        if progress.isEmpty {
            subtitleLabel.text = String(localized: "\(plan.days) dias")
        } else {
            subtitleLabel.text = String(localized: "\(progress.count) / \(plan.days) dias")
        }
        chevron.isHidden = false
        accessibilityLabel = "\(plan.name). \(subtitleLabel.text ?? "")"
    }

    func configureEmpty(_ message: String) {
        titleLabel.text = message
        subtitleLabel.text = nil
        chevron.isHidden = true
        accessibilityLabel = message
    }

    static func style(card: UIView, title: UILabel, subtitle: UILabel, chevron: UIImageView, in contentView: UIView) {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = V2NDesign.surface
        card.layer.cornerRadius = V2NDesign.Radius.lg
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)

        title.font = V2NDesign.preferred(.body, weight: .regular)
        title.textColor = .label
        title.numberOfLines = 2
        title.adjustsFontForContentSizeCategory = true
        title.translatesAutoresizingMaskIntoConstraints = false

        subtitle.font = V2NDesign.caption()
        subtitle.textColor = .secondaryLabel
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
}

/// “Todos os planos” link card with accent icon well.
final class V2NPlanLinkCardCell: UICollectionViewCell {
    static let reuseId = "V2NPlanLinkCardCell"
    private let card = UIView()
    private let iconWrap = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = V2NDesign.surface
        card.layer.cornerRadius = V2NDesign.Radius.lg
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.accent
        iconWrap.layer.cornerRadius = V2NDesign.Radius.sm
        iconWrap.layer.cornerCurve = .continuous
        card.addSubview(iconWrap)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconWrap.addSubview(iconView)

        titleLabel.font = V2NDesign.preferred(.body, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = V2NDesign.caption()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconWrap.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 28),
            iconWrap.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: card.centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: card.centerYAnchor, constant: 1),

            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String, symbol: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        iconView.image = UIImage(systemName: symbol)
        accessibilityLabel = "\(title). \(subtitle)"
    }
}

/// Table-row twin of `V2NPlanRowCardCell` for category / all-plans lists.
final class V2NPlanRowTableCell: UITableViewCell {
    static let reuseId = "V2NPlanRowTableCell"
    private let card = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = V2NDesign.surface
        card.layer.cornerRadius = V2NDesign.Radius.lg
        card.layer.cornerCurve = .continuous
        contentView.addSubview(card)

        titleLabel.font = V2NDesign.preferred(.body, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = V2NDesign.caption()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(plan: NativeAPIClient.PlanCardDTO, progress: [Int]) {
        titleLabel.text = plan.name
        if progress.isEmpty {
            subtitleLabel.text = String(localized: "\(plan.days) dias")
        } else {
            subtitleLabel.text = String(localized: "\(progress.count) / \(plan.days) dias")
        }
        chevron.isHidden = false
        accessibilityLabel = "\(plan.name). \(subtitleLabel.text ?? "")"
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func configureEmpty(_ message: String) {
        titleLabel.text = message
        subtitleLabel.text = nil
        chevron.isHidden = true
        accessibilityLabel = message
    }
}
