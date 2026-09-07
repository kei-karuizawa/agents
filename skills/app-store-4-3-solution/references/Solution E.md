# 方案E - TCA + UserDefaults 响应式架构

## 一、架构概述

采用 TCA（The Composable Architecture）单向数据流架构，使用 UserDefaults 进行轻量级数据持久化。强调状态管理的可预测性和可测试性。

## 二、项目结构

```
ProjectE/
├── App/
│   ├── ProjectEApp.swift              # @main 入口
│   ├── AppFeature.swift               # 根Feature
│   └── AppDependencies.swift          # 依赖注册
├── Features/
│   ├── Home/
│   │   ├── HomeFeature.swift          # Feature定义
│   │   ├── HomeView.swift             # 视图
│   │   └── HomeEnvironment.swift      # 环境依赖
│   ├── Detail/
│   │   ├── DetailFeature.swift
│   │   ├── DetailView.swift
│   │   └── DetailEnvironment.swift
│   ├── Settings/
│   │   └── ...
│   └── Shared/
│       └── SharedFeature.swift
├── Storage/
│   ├── UserDefaultsClient.swift       # UserDefaults封装
│   ├── StorageKeys.swift              # 存储键定义
│   └── Codable/
│       ├── ItemStorage.swift          # Item存储模型
│       └── UserStorage.swift
├── Services/
│   ├── ItemService.swift              # 业务服务
│   ├── UserService.swift
│   └── NetworkService.swift
├── Models/
│   ├── Item.swift                     # 领域模型
│   └── User.swift
├── UIKit/
│   ├── Components/
│   │   ├── TCAButton.swift
│   │   ├── TCATextField.swift
│   │   └── TCACard.swift
│   ├── Styles/
│   │   ├── ButtonStyles.swift
│   │   └── TextStyles.swift
│   └── Theme/
│       ├── ColorPalette.swift
│       └── Typography.swift
├── Utilities/
│   ├── Extensions/
│   │   ├── Publisher+Ext.swift
│   │   └── Effect+Ext.swift
│   └── Helpers/
│       └── IDGenerator.swift
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings
```

## 三、TCA 架构实现

### 3.1 Feature 定义

```swift
import ComposableArchitecture

@Reducer
struct HomeFeature {
    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var items: IdentifiedArrayOf<Item> = []
        var isLoading = false
        var alertState: AlertState<Action>?
        @Presents var destination: Destination.State?
    }

    // MARK: - Action

    enum Action: ViewAction {
        case view(View)
        case delegate(Delegate)
        case `internal`(Internal)
        case destination(PresentationAction<Destination.Action>)

        enum View {
            case onAppear
            case onRefresh
            case itemTapped(Item.ID)
            case deleteItem(IndexSet)
            case addButtonTapped
            case alertDismissed
        }

        enum Delegate {
            case itemSelected(Item)
        }

        enum Internal {
            case itemsLoaded(Result<[Item], Error>)
            case itemDeleted(Result<Void, Error>)
        }
    }

    // MARK: - Destination

    @Reducer
    enum Destination {
        case detail(DetailFeature)
        case addItem(AddItemFeature)
    }

    // MARK: - Dependencies

    @Dependency(\.itemService) var itemService

    // MARK: - Reducer

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                return loadItems(&state)

            case .view(.onRefresh):
                return loadItems(&state)

            case .view(.itemTapped(let id)):
                guard let item = state.items[id: id] else { return .none }
                state.destination = .detail(DetailFeature.State(item: item))
                return .none

            case .view(.deleteItem(let indexSet)):
                guard let index = indexSet.first else { return .none }
                let item = state.items[index]
                return .run { send in
                    let result = await Result { try await itemService.delete(item.id) }
                    await send(.internal(.itemDeleted(result)))
                }

            case .view(.addButtonTapped):
                state.destination = .addItem(AddItemFeature.State())
                return .none

            case .view(.alertDismissed):
                state.alertState = nil
                return .none

            case .internal(.itemsLoaded(.success(let items))):
                state.items = IdentifiedArray(uniqueElements: items)
                state.isLoading = false
                return .none

            case .internal(.itemsLoaded(.failure(let error))):
                state.isLoading = false
                state.alertState = AlertState {
                    TextState("错误")
                } actions: {
                    ButtonState(action: .view(.alertDismissed)) {
                        TextState("确定")
                    }
                } message: {
                    TextState(error.localizedDescription)
                }
                return .none

            case .internal(.itemDeleted(.success)):
                return loadItems(&state)

            case .internal(.itemDeleted(.failure(let error))):
                state.alertState = AlertState {
                    TextState("删除失败")
                } message: {
                    TextState(error.localizedDescription)
                }
                return .none

            case .delegate:
                return .none

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func loadItems(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        return .run { send in
            let result = await Result { try await itemService.fetchAll() }
            await send(.internal(.itemsLoaded(result)))
        }
    }
}
```

### 3.2 View 实现

```swift
import ComposableArchitecture

@ViewAction(for: HomeFeature.self)
struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>

    var body: some View {
        NavigationStack {
            ZStack {
                if store.isLoading && store.items.isEmpty {
                    loadingView
                } else {
                    contentView
                }
            }
            .navigationTitle("首页")
            .toolbar { toolbarItems }
            .refreshable { await send(.onRefresh).finish() }
        }
        .onAppear { send(.onAppear) }
        .alert($store.scope(state: \.alertState, action: \.view))
        .sheet(item: $store.scope(state: \.destination?.addItem, action: \.destination.addItem)) { store in
            AddItemView(store: store)
        }
        .navigationDestination(item: $store.scope(state: \.destination?.detail, action: \.destination.detail)) { store in
            DetailView(store: store)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("加载中...")
                .foregroundStyle(.secondary)
        }
    }

    private var contentView: some View {
        Group {
            if store.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无内容", systemImage: "doc.text")
        } description: {
            Text("点击右上角添加新内容")
        }
    }

    private var listView: some View {
        List {
            ForEach(store.items) { item in
                ItemRowView(item: item)
                    .onTapGesture { send(.itemTapped(item.id)) }
            }
            .onDelete { indexSet in
                send(.deleteItem(indexSet))
            }
        }
        .listStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                send(.addButtonTapped)
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

// Item Row
struct ItemRowView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
            Text(item.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
```

### 3.3 Service 依赖

```swift
import ComposableArchitecture

// Item Service Protocol
struct ItemService {
    var fetchAll: @Sendable () async throws -> [Item]
    var fetchById: @Sendable (String) async throws -> Item?
    var save: @Sendable (Item) async throws -> Void
    var update: @Sendable (Item) async throws -> Void
    var delete: @Sendable (String) async throws -> Void
}

// Dependency Key
extension ItemService: DependencyKey {
    static var liveValue: ItemService {
        @Dependency(\.userDefaultsClient) var storage

        return ItemService(
            fetchAll: {
                try await storage.loadItems()
            },
            fetchById: { id in
                let items = try await storage.loadItems()
                return items.first { $0.id == id }
            },
            save: { item in
                var items = (try? await storage.loadItems()) ?? []
                items.append(item)
                try await storage.saveItems(items)
            },
            update: { item in
                var items = (try? await storage.loadItems()) ?? []
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = item
                    try await storage.saveItems(items)
                }
            },
            delete: { id in
                var items = (try? await storage.loadItems()) ?? []
                items.removeAll { $0.id == id }
                try await storage.saveItems(items)
            }
        )
    }

    static var testValue: ItemService {
        ItemService(
            fetchAll: { [] },
            fetchById: { _ in nil },
            save: { _ in },
            update: { _ in },
            delete: { _ in }
        )
    }
}

extension DependencyValues {
    var itemService: ItemService {
        get { self[ItemService.self] }
        set { self[ItemService.self] = newValue }
    }
}
```

## 四、数据存储 - UserDefaults

### 4.1 UserDefaults Client

```swift
import ComposableArchitecture

struct UserDefaultsClient {
    var loadItems: @Sendable () async throws -> [Item]
    var saveItems: @Sendable ([Item]) async throws -> Void
    var loadUser: @Sendable () async throws -> User?
    var saveUser: @Sendable (User) async throws -> Void
    var getValue: @Sendable (String) async -> Any?
    var setValue: @Sendable (String, Any?) async -> Void
    var clearAll: @Sendable () async -> Void
}

extension UserDefaultsClient: DependencyKey {
    static var liveValue: UserDefaultsClient {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        return UserDefaultsClient(
            loadItems: {
                guard let data = defaults.data(forKey: StorageKeys.items) else {
                    return []
                }
                let storageItems = try decoder.decode([ItemStorage].self, from: data)
                return storageItems.map { $0.toDomain() }
            },
            saveItems: { items in
                let storageItems = items.map { ItemStorage(from: $0) }
                let data = try encoder.encode(storageItems)
                defaults.set(data, forKey: StorageKeys.items)
            },
            loadUser: {
                guard let data = defaults.data(forKey: StorageKeys.user) else {
                    return nil
                }
                let storageUser = try decoder.decode(UserStorage.self, from: data)
                return storageUser.toDomain()
            },
            saveUser: { user in
                let storageUser = UserStorage(from: user)
                let data = try encoder.encode(storageUser)
                defaults.set(data, forKey: StorageKeys.user)
            },
            getValue: { key in
                defaults.object(forKey: key)
            },
            setValue: { key, value in
                if let value = value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            },
            clearAll: {
                let domain = Bundle.main.bundleIdentifier!
                defaults.removePersistentDomain(forName: domain)
            }
        )
    }

    static var testValue: UserDefaultsClient {
        UserDefaultsClient(
            loadItems: { [] },
            saveItems: { _ in },
            loadUser: { nil },
            saveUser: { _ in },
            getValue: { _ in nil },
            setValue: { _, _ in },
            clearAll: { }
        )
    }
}

extension DependencyValues {
    var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}
```

### 4.2 存储键定义

```swift
enum StorageKeys {
    static let items = "com.projecte.storage.items"
    static let user = "com.projecte.storage.user"
    static let settings = "com.projecte.storage.settings"
    static let lastSync = "com.projecte.storage.lastSync"
    static let isFirstLaunch = "com.projecte.storage.isFirstLaunch"
    static let themeMode = "com.projecte.storage.themeMode"
}
```

### 4.3 存储模型

```swift
// Item 存储模型
struct ItemStorage: Codable {
    let id: String
    var title: String
    var content: String
    var createdTimestamp: TimeInterval
    var updatedTimestamp: TimeInterval

    init(from item: Item) {
        self.id = item.id
        self.title = item.title
        self.content = item.content
        self.createdTimestamp = item.createdAt.timeIntervalSince1970
        self.updatedTimestamp = item.updatedAt.timeIntervalSince1970
    }

    func toDomain() -> Item {
        Item(
            id: id,
            title: title,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdTimestamp),
            updatedAt: Date(timeIntervalSince1970: updatedTimestamp)
        )
    }
}

// User 存储模型
struct UserStorage: Codable {
    let id: String
    var name: String
    var email: String

    init(from user: User) {
        self.id = user.id
        self.name = user.name
        self.email = user.email
    }

    func toDomain() -> User {
        User(id: id, name: name, email: email)
    }
}
```

### 4.4 领域模型

```swift
struct Item: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         content: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct User: Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var email: String

    init(id: String = UUID().uuidString, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
```

### 4.5 扩展功能

```swift
extension UserDefaultsClient {
    // 便捷方法 - 布尔值
    func getBool(forKey key: String) async -> Bool {
        await getValue(key) as? Bool ?? false
    }

    func setBool(_ value: Bool, forKey key: String) async {
        await setValue(key, value)
    }

    // 便捷方法 - 整数
    func getInt(forKey key: String) async -> Int {
        await getValue(key) as? Int ?? 0
    }

    func setInt(_ value: Int, forKey key: String) async {
        await setValue(key, value)
    }

    // 便捷方法 - 字符串
    func getString(forKey key: String) async -> String? {
        await getValue(key) as? String
    }

    func setString(_ value: String?, forKey key: String) async {
        await setValue(key, value)
    }
}
```

## 五、网络层

```swift
import ComposableArchitecture

struct NetworkService {
    var get: @Sendable (String) async throws -> Data
    var post: @Sendable (String, Data) async throws -> Data
    var put: @Sendable (String, Data) async throws -> Data
    var delete: @Sendable (String) async throws -> Void
}

extension NetworkService: DependencyKey {
    static var liveValue: NetworkService {
        let baseURL = "https://api.example.com"
        let session = URLSession.shared

        return NetworkService(
            get: { path in
                guard let url = URL(string: baseURL + path) else {
                    throw NetworkError.invalidURL
                }
                let (data, _) = try await session.data(from: url)
                return data
            },
            post: { path, body in
                guard let url = URL(string: baseURL + path) else {
                    throw NetworkError.invalidURL
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (data, _) = try await session.data(for: request)
                return data
            },
            put: { path, body in
                guard let url = URL(string: baseURL + path) else {
                    throw NetworkError.invalidURL
                }
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.httpBody = body
                let (data, _) = try await session.data(for: request)
                return data
            },
            delete: { path in
                guard let url = URL(string: baseURL + path) else {
                    throw NetworkError.invalidURL
                }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                _ = try await session.data(for: request)
            }
        )
    }
}

enum NetworkError: Error {
    case invalidURL
    case requestFailed
}

extension DependencyValues {
    var networkService: NetworkService {
        get { self[NetworkService.self] }
        set { self[NetworkService.self] = newValue }
    }
}
```

## 六、命名规范

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| Feature | XxxFeature | `HomeFeature` |
| View | XxxView | `HomeView` |
| State | 嵌套在Feature内 | `HomeFeature.State` |
| Action | 嵌套在Feature内 | `HomeFeature.Action` |
| Storage模型 | XxxStorage | `ItemStorage` |
| Service | XxxService | `ItemService` |
| Client | XxxClient | `UserDefaultsClient` |
| 领域模型 | 简洁名词 | `Item`, `User` |

## 七、代码风格

### 7.1 文件头注释
```swift
//
//  FileName.swift
//  ProjectE
//
//  Feature: Home
//  Pattern: TCA + UserDefaults
//
```

### 7.2 Feature 结构
```swift
@Reducer
struct XxxFeature {
    // 1. State
    @ObservableState
    struct State: Equatable { }

    // 2. Action
    enum Action: ViewAction { }

    // 3. Destination (if needed)
    @Reducer
    enum Destination { }

    // 4. Dependencies
    @Dependency(\.xxx) var xxx

    // 5. Reducer Body
    var body: some ReducerOf<Self> { }

    // 6. Private Methods
    private func xxx() { }
}
```

### 7.3 Action 分类
- `view`: 视图触发的操作
- `delegate`: 对外委托的操作
- `internal`: 内部处理的操作

## 八、特色标识

- 架构标识: `// TCA Pattern`
- 存储标识: `// Storage: UserDefaults`
- Feature 使用 `@Reducer` 宏
- State 使用 `@ObservableState` 宏
- 依赖使用 `@Dependency` 属性包装器
- Client 模式封装外部依赖

## 九、系统要求

- iOS 15.0+
- Xcode 15.0+
- Swift 5.9+

## 十、第三方依赖

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
]
```

主要依赖：
- ComposableArchitecture (TCA) - 状态管理架构
- SwiftUI - 界面框架
- Foundation - 基础框架
