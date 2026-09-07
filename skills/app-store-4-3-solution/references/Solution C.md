# 方案C - VIPER + SwiftData 模块化架构

## 一、架构概述

采用 VIPER（View-Interactor-Presenter-Entity-Router）架构，使用 iOS 17+ 的 SwiftData 框架进行数据持久化。强调模块化和单一职责原则。

## 二、项目结构

```
ProjectC/
├── App/
│   ├── ProjectCApp.swift              # @main 入口
│   ├── DIContainer.swift              # 依赖注入容器
│   └── Router/
│       └── AppRouter.swift            # 全局路由
├── Modules/
│   ├── Home/
│   │   ├── HomeModule.swift           # 模块组装
│   │   ├── HomeView.swift             # V - 视图
│   │   ├── HomeInteractor.swift       # I - 交互器
│   │   ├── HomePresenter.swift        # P - 展示器
│   │   ├── HomeEntity.swift           # E - 实体
│   │   └── HomeRouter.swift           # R - 路由
│   ├── Detail/
│   │   ├── DetailModule.swift
│   │   ├── DetailView.swift
│   │   ├── DetailInteractor.swift
│   │   ├── DetailPresenter.swift
│   │   ├── DetailEntity.swift
│   │   └── DetailRouter.swift
│   └── Setting/
│       └── ...
├── Domain/
│   ├── Entities/
│   │   ├── Item.swift                 # 业务实体
│   │   └── User.swift
│   ├── UseCases/
│   │   ├── FetchItemsUseCase.swift
│   │   ├── SaveItemUseCase.swift
│   │   └── DeleteItemUseCase.swift
│   └── Protocols/
│       ├── ItemRepositoryProtocol.swift
│       └── UserRepositoryProtocol.swift
├── Data/
│   ├── SwiftData/
│   │   ├── SDItem.swift               # SwiftData模型
│   │   ├── SDUser.swift
│   │   └── ModelContainer+Ext.swift
│   ├── Repositories/
│   │   ├── ItemRepository.swift
│   │   └── UserRepository.swift
│   └── Network/
│       ├── NetworkClient.swift
│       ├── Endpoint.swift
│       └── NetworkResponse.swift
├── Presentation/
│   ├── Components/
│   │   ├── PrimaryBtn.swift
│   │   ├── SecondaryBtn.swift
│   │   └── CardContainer.swift
│   ├── Theme/
│   │   ├── AppColors.swift
│   │   ├── AppFonts.swift
│   │   └── AppSpacing.swift
│   └── Modifiers/
│       ├── CardModifier.swift
│       └── LoadingModifier.swift
├── Infrastructure/
│   ├── Extensions/
│   │   ├── Date+Format.swift
│   │   └── String+Util.swift
│   └── Helpers/
│       ├── Logger.swift
│       └── Validator.swift
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings
```

## 三、VIPER 设计模式

### 3.1 模块协议定义

```swift
// MARK: - VIPER Protocols

// View Protocol
protocol HomeViewProtocol: AnyObject {
    var presenter: HomePresenterProtocol? { get set }
    func displayItems(_ items: [ItemViewData])
    func displayLoading(_ isLoading: Bool)
    func displayError(_ message: String)
}

// Interactor Protocol
protocol HomeInteractorProtocol: AnyObject {
    var presenter: HomePresenterOutputProtocol? { get set }
    func fetchItems()
    func deleteItem(id: String)
}

// Presenter Protocol
protocol HomePresenterProtocol: AnyObject {
    var view: HomeViewProtocol? { get set }
    var interactor: HomeInteractorProtocol? { get set }
    var router: HomeRouterProtocol? { get set }
    func viewDidLoad()
    func didSelectItem(_ item: ItemViewData)
    func didTapDelete(id: String)
}

protocol HomePresenterOutputProtocol: AnyObject {
    func didFetchItems(_ items: [Item])
    func didFailFetchItems(_ error: Error)
    func didDeleteItem()
    func didFailDeleteItem(_ error: Error)
}

// Router Protocol
protocol HomeRouterProtocol: AnyObject {
    func navigateToDetail(item: Item)
    func navigateToCreate()
}
```

### 3.2 View 实现

```swift
struct HomeView: View, HomeViewProtocol {
    @StateObject private var viewModel = HomeViewModel()

    var presenter: HomePresenterProtocol? {
        get { viewModel.presenter }
        set { viewModel.presenter = newValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    itemListView
                }
            }
            .navigationTitle("首页")
            .toolbar { toolbarItems }
        }
        .onAppear { presenter?.viewDidLoad() }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var itemListView: some View {
        List(viewModel.items) { item in
            ItemRow(data: item)
                .onTapGesture { presenter?.didSelectItem(item) }
                .swipeActions {
                    Button(role: .destructive) {
                        presenter?.didTapDelete(id: item.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
        }
        .listStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // 添加
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - HomeViewProtocol

    func displayItems(_ items: [ItemViewData]) {
        viewModel.items = items
    }

    func displayLoading(_ isLoading: Bool) {
        viewModel.isLoading = isLoading
    }

    func displayError(_ message: String) {
        viewModel.errorMessage = message
        viewModel.showError = true
    }
}

// ViewModel for SwiftUI state management
class HomeViewModel: ObservableObject {
    @Published var items: [ItemViewData] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    weak var presenter: HomePresenterProtocol?
}
```

### 3.3 Interactor 实现

```swift
final class HomeInteractor: HomeInteractorProtocol {
    weak var presenter: HomePresenterOutputProtocol?

    private let fetchItemsUseCase: FetchItemsUseCase
    private let deleteItemUseCase: DeleteItemUseCase

    init(fetchItemsUseCase: FetchItemsUseCase,
         deleteItemUseCase: DeleteItemUseCase) {
        self.fetchItemsUseCase = fetchItemsUseCase
        self.deleteItemUseCase = deleteItemUseCase
    }

    func fetchItems() {
        Task { @MainActor in
            do {
                let items = try await fetchItemsUseCase.execute()
                presenter?.didFetchItems(items)
            } catch {
                presenter?.didFailFetchItems(error)
            }
        }
    }

    func deleteItem(id: String) {
        Task { @MainActor in
            do {
                try await deleteItemUseCase.execute(id: id)
                presenter?.didDeleteItem()
            } catch {
                presenter?.didFailDeleteItem(error)
            }
        }
    }
}
```

### 3.4 Presenter 实现

```swift
final class HomePresenter: HomePresenterProtocol, HomePresenterOutputProtocol {
    weak var view: HomeViewProtocol?
    var interactor: HomeInteractorProtocol?
    var router: HomeRouterProtocol?

    func viewDidLoad() {
        view?.displayLoading(true)
        interactor?.fetchItems()
    }

    func didSelectItem(_ item: ItemViewData) {
        let entity = Item(id: item.id, title: item.title, content: item.content)
        router?.navigateToDetail(item: entity)
    }

    func didTapDelete(id: String) {
        view?.displayLoading(true)
        interactor?.deleteItem(id: id)
    }

    // MARK: - HomePresenterOutputProtocol

    func didFetchItems(_ items: [Item]) {
        view?.displayLoading(false)
        let viewData = items.map { ItemViewData(from: $0) }
        view?.displayItems(viewData)
    }

    func didFailFetchItems(_ error: Error) {
        view?.displayLoading(false)
        view?.displayError(error.localizedDescription)
    }

    func didDeleteItem() {
        interactor?.fetchItems()
    }

    func didFailDeleteItem(_ error: Error) {
        view?.displayLoading(false)
        view?.displayError("删除失败: \(error.localizedDescription)")
    }
}
```

### 3.5 Router 实现

```swift
final class HomeRouter: HomeRouterProtocol {
    weak var viewController: UIViewController?
    var navigationPath: Binding<NavigationPath>?

    func navigateToDetail(item: Item) {
        // SwiftUI navigation
        navigationPath?.wrappedValue.append(item)
    }

    func navigateToCreate() {
        // Navigate to create screen
    }
}
```

### 3.6 Module 组装

```swift
enum HomeModule {
    static func build() -> some View {
        let interactor = HomeInteractor(
            fetchItemsUseCase: DIContainer.shared.fetchItemsUseCase,
            deleteItemUseCase: DIContainer.shared.deleteItemUseCase
        )
        let presenter = HomePresenter()
        let router = HomeRouter()

        var view = HomeView()

        presenter.view = view
        presenter.interactor = interactor
        presenter.router = router
        interactor.presenter = presenter
        view.presenter = presenter

        return view
    }
}
```

## 四、数据存储 - SwiftData

### 4.1 SwiftData 模型定义

```swift
import SwiftData

@Model
final class SDItem {
    @Attribute(.unique) var id: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    init(id: String = UUID().uuidString,
         title: String,
         content: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    func toDomain() -> Item {
        Item(id: id, title: title, content: content, createdAt: createdAt)
    }
}

@Model
final class SDUser {
    @Attribute(.unique) var id: String
    var name: String
    var email: String

    @Relationship(deleteRule: .cascade)
    var items: [SDItem]?

    init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

### 4.2 ModelContainer 配置

```swift
import SwiftData

extension ModelContainer {
    static var appContainer: ModelContainer = {
        let schema = Schema([SDItem.self, SDUser.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

// App Entry
@main
struct ProjectCApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ModelContainer.appContainer)
    }
}
```

### 4.3 Repository 实现

```swift
final class ItemRepository: ItemRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Item] {
        let descriptor = FetchDescriptor<SDItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let sdItems = try modelContext.fetch(descriptor)
        return sdItems.map { $0.toDomain() }
    }

    func fetchById(_ id: String) async throws -> Item? {
        let predicate = #Predicate<SDItem> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = try modelContext.fetch(descriptor)
        return results.first?.toDomain()
    }

    func save(_ item: Item) async throws {
        let sdItem = SDItem(
            id: item.id,
            title: item.title,
            content: item.content,
            createdAt: item.createdAt
        )
        modelContext.insert(sdItem)
        try modelContext.save()
    }

    func update(_ item: Item) async throws {
        let predicate = #Predicate<SDItem> { $0.id == item.id }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let sdItem = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        sdItem.title = item.title
        sdItem.content = item.content
        sdItem.updatedAt = Date()
        try modelContext.save()
    }

    func delete(id: String) async throws {
        let predicate = #Predicate<SDItem> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let sdItem = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        modelContext.delete(sdItem)
        try modelContext.save()
    }
}

enum RepositoryError: Error {
    case notFound
    case saveFailed
}
```

### 4.4 UseCase 实现

```swift
protocol FetchItemsUseCaseProtocol {
    func execute() async throws -> [Item]
}

final class FetchItemsUseCase: FetchItemsUseCaseProtocol {
    private let repository: ItemRepositoryProtocol

    init(repository: ItemRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [Item] {
        try await repository.fetchAll()
    }
}

protocol DeleteItemUseCaseProtocol {
    func execute(id: String) async throws
}

final class DeleteItemUseCase: DeleteItemUseCaseProtocol {
    private let repository: ItemRepositoryProtocol

    init(repository: ItemRepositoryProtocol) {
        self.repository = repository
    }

    func execute(id: String) async throws {
        try await repository.delete(id: id)
    }
}
```

## 五、依赖注入

```swift
final class DIContainer {
    static let shared = DIContainer()

    private let modelContext: ModelContext

    private init() {
        self.modelContext = ModelContainer.appContainer.mainContext
    }

    // Repositories
    lazy var itemRepository: ItemRepositoryProtocol = {
        ItemRepository(modelContext: modelContext)
    }()

    // UseCases
    lazy var fetchItemsUseCase: FetchItemsUseCase = {
        FetchItemsUseCase(repository: itemRepository)
    }()

    lazy var deleteItemUseCase: DeleteItemUseCase = {
        DeleteItemUseCase(repository: itemRepository)
    }()

    lazy var saveItemUseCase: SaveItemUseCase = {
        SaveItemUseCase(repository: itemRepository)
    }()
}
```

## 六、网络层

```swift
enum Endpoint {
    case getItems
    case getItem(id: String)
    case createItem
    case deleteItem(id: String)

    var path: String {
        switch self {
        case .getItems: return "/items"
        case .getItem(let id): return "/items/\(id)"
        case .createItem: return "/items"
        case .deleteItem(let id): return "/items/\(id)"
        }
    }

    var method: String {
        switch self {
        case .getItems, .getItem: return "GET"
        case .createItem: return "POST"
        case .deleteItem: return "DELETE"
        }
    }
}

actor NetworkClient {
    private let baseURL = "https://api.example.com"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        guard let url = URL(string: baseURL + endpoint.path) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum NetworkError: Error {
    case invalidURL
    case requestFailed
    case decodingFailed
}
```

## 七、命名规范

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| Module文件 | XxxModule | `HomeModule.swift` |
| View | XxxView | `HomeView` |
| Interactor | XxxInteractor | `HomeInteractor` |
| Presenter | XxxPresenter | `HomePresenter` |
| Router | XxxRouter | `HomeRouter` |
| SwiftData模型 | SD前缀 | `SDItem` |
| UseCase | XxxUseCase | `FetchItemsUseCase` |
| Protocol | Xxx + Protocol后缀 | `HomeViewProtocol` |

## 八、代码风格

### 8.1 文件头注释
```swift
//
//  FileName.swift
//  ProjectC
//
//  VIPER Module: Home
//  Storage: SwiftData
//
```

### 8.2 MARK 使用
```swift
// MARK: - VIPER Protocol
// MARK: - Properties
// MARK: - Lifecycle
// MARK: - Protocol Implementation
```

### 8.3 协议分离
每个 VIPER 组件的协议放在独立的 Protocols 文件或模块文件顶部

## 九、特色标识

- 架构标识: `// VIPER Module`
- 存储标识: `// Storage: SwiftData`
- 模块使用 `enum` 作为命名空间
- 所有 class 使用 `final` 修饰

## 十、系统要求

- iOS 17.0+ (SwiftData 要求)
- Xcode 15.0+
- Swift 5.9+

## 十一、第三方依赖

仅使用 Apple 原生框架：
- SwiftUI
- SwiftData
- Foundation
