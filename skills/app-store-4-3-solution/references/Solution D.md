# 方案D - Clean Architecture + JSON文件存储

## 一、架构概述

采用 Clean Architecture（整洁架构）设计，使用 JSON 文件进行本地数据持久化。严格分层，内层不依赖外层，通过协议实现依赖反转。

## 二、项目结构

```
ProjectD/
├── Entry/
│   ├── ProjectDApp.swift              # @main 入口
│   └── Bootstrapper.swift             # 应用启动配置
├── Presentation/
│   ├── Scenes/
│   │   ├── Home/
│   │   │   ├── HomeScene.swift        # 场景视图
│   │   │   └── HomeSceneModel.swift   # 场景模型
│   │   ├── Detail/
│   │   │   ├── DetailScene.swift
│   │   │   └── DetailSceneModel.swift
│   │   └── Settings/
│   │       └── ...
│   ├── Widgets/
│   │   ├── Buttons/
│   │   │   ├── FilledButton.swift
│   │   │   └── OutlineButton.swift
│   │   ├── Inputs/
│   │   │   ├── TextInput.swift
│   │   │   └── SearchInput.swift
│   │   └── Containers/
│   │       ├── ShadowCard.swift
│   │       └── RoundedContainer.swift
│   ├── Navigation/
│   │   ├── AppCoordinator.swift
│   │   └── NavigationState.swift
│   └── DesignSystem/
│       ├── DSColors.swift
│       ├── DSTypography.swift
│       └── DSSpacing.swift
├── Domain/
│   ├── Entities/
│   │   ├── ItemEntity.swift
│   │   └── UserEntity.swift
│   ├── Interfaces/
│   │   ├── ItemGateway.swift          # 数据网关协议
│   │   └── UserGateway.swift
│   └── UseCases/
│       ├── Item/
│       │   ├── GetItemsUseCase.swift
│       │   ├── AddItemUseCase.swift
│       │   └── RemoveItemUseCase.swift
│       └── User/
│           └── ...
├── Data/
│   ├── Gateways/
│   │   ├── ItemGatewayImpl.swift
│   │   └── UserGatewayImpl.swift
│   ├── LocalStorage/
│   │   ├── JSONFileManager.swift      # JSON文件管理
│   │   ├── FileStorageConfig.swift
│   │   └── DataModels/
│   │       ├── ItemDataModel.swift
│   │       └── UserDataModel.swift
│   └── RemoteAPI/
│       ├── APIService.swift
│       ├── APIEndpoints.swift
│       └── ResponseModels/
│           └── ItemResponse.swift
├── Core/
│   ├── DI/
│   │   └── Container.swift            # 依赖注入
│   ├── Extensions/
│   │   ├── DateExt.swift
│   │   └── OptionalExt.swift
│   ├── Utils/
│   │   ├── Result+Ext.swift
│   │   └── AsyncUtils.swift
│   └── Constants/
│       └── AppConfig.swift
└── Resources/
    ├── Assets.xcassets
    └── Strings/
```

## 三、Clean Architecture 实现

### 3.1 Domain 层 - 实体

```swift
// Domain Entity - 核心业务实体，不依赖任何外部框架
struct ItemEntity: Equatable {
    let identifier: String
    var title: String
    var content: String
    var createdDate: Date
    var modifiedDate: Date
    var status: ItemStatus

    enum ItemStatus {
        case active
        case archived
        case deleted

        var displayName: String {
            switch self {
            case .active: return "活跃"
            case .archived: return "已归档"
            case .deleted: return "已删除"
            }
        }
    }

    init(identifier: String = UUID().uuidString,
         title: String,
         content: String,
         status: ItemStatus = .active) {
        self.identifier = identifier
        self.title = title
        self.content = content
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.status = status
    }
}
```

### 3.2 Domain 层 - Gateway 协议

```swift
// Gateway 协议 - 定义数据访问接口
protocol ItemGateway {
    func fetchAll() async throws -> [ItemEntity]
    func fetchByIdentifier(_ identifier: String) async throws -> ItemEntity?
    func save(_ item: ItemEntity) async throws
    func update(_ item: ItemEntity) async throws
    func remove(_ identifier: String) async throws
}
```

### 3.3 Domain 层 - UseCase

```swift
// UseCase 协议
protocol UseCase {
    associatedtype Input
    associatedtype Output
    func execute(input: Input) async throws -> Output
}

// 获取列表 UseCase
final class GetItemsUseCase: UseCase {
    typealias Input = Void
    typealias Output = [ItemEntity]

    private let gateway: ItemGateway

    init(gateway: ItemGateway) {
        self.gateway = gateway
    }

    func execute(input: Void) async throws -> [ItemEntity] {
        try await gateway.fetchAll()
    }
}

// 添加项目 UseCase
final class AddItemUseCase: UseCase {
    struct Input {
        let title: String
        let content: String
    }
    typealias Output = ItemEntity

    private let gateway: ItemGateway

    init(gateway: ItemGateway) {
        self.gateway = gateway
    }

    func execute(input: Input) async throws -> ItemEntity {
        let item = ItemEntity(title: input.title, content: input.content)
        try await gateway.save(item)
        return item
    }
}

// 删除项目 UseCase
final class RemoveItemUseCase: UseCase {
    typealias Input = String
    typealias Output = Void

    private let gateway: ItemGateway

    init(gateway: ItemGateway) {
        self.gateway = gateway
    }

    func execute(input: String) async throws {
        try await gateway.remove(input)
    }
}
```

### 3.4 Presentation 层 - SceneModel

```swift
// Scene Model - 管理场景状态和业务逻辑
@MainActor
final class HomeSceneModel: ObservableObject {

    struct UIState {
        var items: [ItemPresentation] = []
        var isLoading = false
        var errorText: String?
        var showError = false
    }

    @Published private(set) var uiState = UIState()

    private let getItemsUseCase: GetItemsUseCase
    private let addItemUseCase: AddItemUseCase
    private let removeItemUseCase: RemoveItemUseCase

    init(getItemsUseCase: GetItemsUseCase,
         addItemUseCase: AddItemUseCase,
         removeItemUseCase: RemoveItemUseCase) {
        self.getItemsUseCase = getItemsUseCase
        self.addItemUseCase = addItemUseCase
        self.removeItemUseCase = removeItemUseCase
    }

    func loadItems() {
        uiState.isLoading = true
        Task {
            do {
                let entities = try await getItemsUseCase.execute(input: ())
                uiState.items = entities.map { ItemPresentation(from: $0) }
                uiState.isLoading = false
            } catch {
                uiState.errorText = error.localizedDescription
                uiState.showError = true
                uiState.isLoading = false
            }
        }
    }

    func addItem(title: String, content: String) {
        Task {
            do {
                let input = AddItemUseCase.Input(title: title, content: content)
                _ = try await addItemUseCase.execute(input: input)
                loadItems()
            } catch {
                uiState.errorText = "添加失败"
                uiState.showError = true
            }
        }
    }

    func removeItem(identifier: String) {
        Task {
            do {
                try await removeItemUseCase.execute(input: identifier)
                loadItems()
            } catch {
                uiState.errorText = "删除失败"
                uiState.showError = true
            }
        }
    }

    func dismissError() {
        uiState.showError = false
        uiState.errorText = nil
    }
}

// Presentation Model - 视图展示数据
struct ItemPresentation: Identifiable {
    let id: String
    let title: String
    let content: String
    let dateText: String
    let statusText: String

    init(from entity: ItemEntity) {
        self.id = entity.identifier
        self.title = entity.title
        self.content = entity.content
        self.dateText = Self.formatDate(entity.createdDate)
        self.statusText = entity.status.displayName
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

### 3.5 Presentation 层 - Scene View

```swift
struct HomeScene: View {
    @StateObject private var model: HomeSceneModel

    init(model: HomeSceneModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.uiState.isLoading {
                    loadingView
                } else if model.uiState.items.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("首页")
            .toolbar { toolbarContent }
        }
        .onAppear { model.loadItems() }
        .alert("提示", isPresented: $model.uiState.showError) {
            Button("确定") { model.dismissError() }
        } message: {
            Text(model.uiState.errorText ?? "")
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("加载中...")
                .padding(.top, 16)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("暂无数据")
                .font(.headline)
        }
    }

    private var listView: some View {
        List {
            ForEach(model.uiState.items) { item in
                ItemRow(item: item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.removeItem(identifier: item.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { model.loadItems() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // 添加操作
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
    }
}
```

## 四、数据存储 - JSON 文件

### 4.1 Data Model

```swift
// Data Model - 存储层数据模型
struct ItemDataModel: Codable {
    let identifier: String
    var title: String
    var content: String
    var createdTimestamp: TimeInterval
    var modifiedTimestamp: TimeInterval
    var statusRaw: Int

    init(from entity: ItemEntity) {
        self.identifier = entity.identifier
        self.title = entity.title
        self.content = entity.content
        self.createdTimestamp = entity.createdDate.timeIntervalSince1970
        self.modifiedTimestamp = entity.modifiedDate.timeIntervalSince1970
        self.statusRaw = Self.statusToRaw(entity.status)
    }

    func toEntity() -> ItemEntity {
        var entity = ItemEntity(
            identifier: identifier,
            title: title,
            content: content,
            status: Self.rawToStatus(statusRaw)
        )
        return entity
    }

    private static func statusToRaw(_ status: ItemEntity.ItemStatus) -> Int {
        switch status {
        case .active: return 0
        case .archived: return 1
        case .deleted: return 2
        }
    }

    private static func rawToStatus(_ raw: Int) -> ItemEntity.ItemStatus {
        switch raw {
        case 0: return .active
        case 1: return .archived
        case 2: return .deleted
        default: return .active
        }
    }
}
```

### 4.2 JSON File Manager

```swift
final class JSONFileManager {
    static let shared = JSONFileManager()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
    }

    // MARK: - File Path

    private func fileURL(for fileName: String) -> URL {
        documentsDirectory.appendingPathComponent("\(fileName).json")
    }

    // MARK: - Write

    func write<T: Encodable>(_ data: T, toFile fileName: String) async throws {
        let url = fileURL(for: fileName)
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url, options: .atomic)
    }

    // MARK: - Read

    func read<T: Decodable>(fromFile fileName: String) async throws -> T {
        let url = fileURL(for: fileName)
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Check Exists

    func exists(fileName: String) -> Bool {
        let url = fileURL(for: fileName)
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Delete

    func delete(fileName: String) async throws {
        let url = fileURL(for: fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Read with Default

    func readOrDefault<T: Decodable>(fromFile fileName: String, default defaultValue: T) async -> T {
        do {
            return try await read(fromFile: fileName)
        } catch {
            return defaultValue
        }
    }
}
```

### 4.3 Gateway 实现

```swift
final class ItemGatewayImpl: ItemGateway {
    private let jsonManager: JSONFileManager
    private let fileName = "items_data"

    init(jsonManager: JSONFileManager = .shared) {
        self.jsonManager = jsonManager
    }

    func fetchAll() async throws -> [ItemEntity] {
        let dataModels: [ItemDataModel] = await jsonManager.readOrDefault(
            fromFile: fileName,
            default: []
        )
        return dataModels
            .map { $0.toEntity() }
            .sorted { $0.createdDate > $1.createdDate }
    }

    func fetchByIdentifier(_ identifier: String) async throws -> ItemEntity? {
        let all = try await fetchAll()
        return all.first { $0.identifier == identifier }
    }

    func save(_ item: ItemEntity) async throws {
        var dataModels: [ItemDataModel] = await jsonManager.readOrDefault(
            fromFile: fileName,
            default: []
        )
        let newModel = ItemDataModel(from: item)
        dataModels.append(newModel)
        try await jsonManager.write(dataModels, toFile: fileName)
    }

    func update(_ item: ItemEntity) async throws {
        var dataModels: [ItemDataModel] = await jsonManager.readOrDefault(
            fromFile: fileName,
            default: []
        )
        guard let index = dataModels.firstIndex(where: { $0.identifier == item.identifier }) else {
            throw GatewayError.notFound
        }
        dataModels[index] = ItemDataModel(from: item)
        try await jsonManager.write(dataModels, toFile: fileName)
    }

    func remove(_ identifier: String) async throws {
        var dataModels: [ItemDataModel] = await jsonManager.readOrDefault(
            fromFile: fileName,
            default: []
        )
        dataModels.removeAll { $0.identifier == identifier }
        try await jsonManager.write(dataModels, toFile: fileName)
    }
}

enum GatewayError: Error {
    case notFound
    case saveFailed
}
```

## 五、依赖注入

```swift
final class Container {
    static let shared = Container()

    private init() {}

    // MARK: - Data Layer

    lazy var jsonFileManager: JSONFileManager = .shared

    lazy var itemGateway: ItemGateway = {
        ItemGatewayImpl(jsonManager: jsonFileManager)
    }()

    // MARK: - Use Cases

    func makeGetItemsUseCase() -> GetItemsUseCase {
        GetItemsUseCase(gateway: itemGateway)
    }

    func makeAddItemUseCase() -> AddItemUseCase {
        AddItemUseCase(gateway: itemGateway)
    }

    func makeRemoveItemUseCase() -> RemoveItemUseCase {
        RemoveItemUseCase(gateway: itemGateway)
    }

    // MARK: - Scene Models

    func makeHomeSceneModel() -> HomeSceneModel {
        HomeSceneModel(
            getItemsUseCase: makeGetItemsUseCase(),
            addItemUseCase: makeAddItemUseCase(),
            removeItemUseCase: makeRemoveItemUseCase()
        )
    }
}
```

## 六、网络层

```swift
enum APIEndpoints {
    case fetchItems
    case fetchItem(id: String)
    case createItem
    case updateItem(id: String)
    case deleteItem(id: String)

    var urlPath: String {
        switch self {
        case .fetchItems: return "/api/items"
        case .fetchItem(let id): return "/api/items/\(id)"
        case .createItem: return "/api/items"
        case .updateItem(let id): return "/api/items/\(id)"
        case .deleteItem(let id): return "/api/items/\(id)"
        }
    }

    var httpMethod: String {
        switch self {
        case .fetchItems, .fetchItem: return "GET"
        case .createItem: return "POST"
        case .updateItem: return "PUT"
        case .deleteItem: return "DELETE"
        }
    }
}

final class APIService {
    static let shared = APIService()

    private let baseURLString = "https://api.example.com"
    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    func request<T: Decodable>(endpoint: APIEndpoints, body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: baseURLString + endpoint.urlPath) else {
            throw APIServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIServiceError: Error {
    case badURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
}
```

## 七、命名规范

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| Entity | XxxEntity | `ItemEntity` |
| DataModel | XxxDataModel | `ItemDataModel` |
| Gateway协议 | XxxGateway | `ItemGateway` |
| Gateway实现 | XxxGatewayImpl | `ItemGatewayImpl` |
| UseCase | XxxUseCase | `GetItemsUseCase` |
| Scene | XxxScene | `HomeScene` |
| SceneModel | XxxSceneModel | `HomeSceneModel` |
| Presentation | XxxPresentation | `ItemPresentation` |

## 八、代码风格

### 8.1 文件头注释
```swift
//
//  FileName.swift
//  ProjectD
//
//  Layer: Domain/Data/Presentation
//  Pattern: Clean Architecture
//
```

### 8.2 层级依赖规则
```
Presentation → Domain ← Data
     ↓            ↑        ↓
   Views      Entities   Storage
```

- Domain 层不依赖任何其他层
- Presentation 依赖 Domain
- Data 层实现 Domain 定义的接口

### 8.3 命名约定
- UseCase 方法统一使用 `execute(input:)`
- Gateway 使用动词: `fetch`, `save`, `update`, `remove`
- Scene 使用 `uiState` 管理视图状态

## 九、特色标识

- 架构标识: `// Clean Architecture`
- 层级标识: `// Layer: Domain`, `// Layer: Data`, `// Layer: Presentation`
- 存储标识: `// Storage: JSON Files`
- 使用 `final class` 声明所有类

## 十、第三方依赖

仅使用 Apple 原生框架：
- SwiftUI
- Foundation
