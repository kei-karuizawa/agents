# 方案B - MVC + UserDefaults/Plist 轻量架构

## 一、架构概述

采用 MVC（Model-View-Controller）架构，使用 UserDefaults 和 Plist 文件进行轻量级数据持久化，适合数据量较小的应用。使用 async/await 进行异步编程。

## 二、项目结构

```
ProjectB/
├── Application/
│   ├── AppMain.swift                  # @main 入口
│   └── AppConfig.swift                # 应用配置
├── Screens/
│   ├── Main/
│   │   ├── MainScreen.swift           # 主界面
│   │   ├── MainController.swift       # 控制器
│   │   └── MainDataProvider.swift     # 数据提供者
│   ├── Detail/
│   │   ├── DetailScreen.swift
│   │   ├── DetailController.swift
│   │   └── DetailDataProvider.swift
│   └── Settings/
│       ├── SettingsScreen.swift
│       └── SettingsController.swift
├── DataLayer/
│   ├── Storage/
│   │   ├── PreferencesManager.swift   # UserDefaults封装
│   │   ├── PlistStorage.swift         # Plist读写
│   │   └── StorageKeys.swift          # 存储键定义
│   ├── Models/
│   │   ├── ItemModel.swift
│   │   └── UserPreferences.swift
│   └── Providers/
│       ├── ItemProvider.swift
│       └── ConfigProvider.swift
├── NetworkLayer/
│   ├── APIManager.swift               # API管理器
│   ├── RequestConfig.swift            # 请求配置
│   └── ResponseParser.swift           # 响应解析
├── CommonUI/
│   ├── Buttons/
│   │   ├── ActionButton.swift
│   │   └── IconButton.swift
│   ├── Cards/
│   │   ├── InfoCard.swift
│   │   └── ListCard.swift
│   └── Layouts/
│       ├── StackLayout.swift
│       └── GridLayout.swift
├── Support/
│   ├── Extensions/
│   │   ├── View+Ext.swift
│   │   └── Color+Ext.swift
│   ├── Utilities/
│   │   ├── DateHelper.swift
│   │   └── StringHelper.swift
│   └── AppConstants.swift
└── Resources/
    ├── Assets.xcassets
    ├── DefaultData.plist              # 默认数据
    └── Localization/
```

## 三、设计模式

### 3.1 Controller 模式实现

```swift
// Controller 协议定义
protocol ScreenController: ObservableObject {
    associatedtype ViewState
    var viewState: ViewState { get }
    func onAppear()
    func onDisappear()
}

// 具体 Controller
final class MainController: ScreenController, ObservableObject {

    struct ViewState {
        var dataList: [ItemModel] = []
        var isRefreshing = false
        var showError = false
        var errorText = ""
    }

    @Published private(set) var viewState = ViewState()

    private let itemProvider: ItemProvider

    init(itemProvider: ItemProvider = .shared) {
        self.itemProvider = itemProvider
    }

    func onAppear() {
        loadData()
    }

    func onDisappear() {
        // 清理工作
    }

    func loadData() {
        viewState.isRefreshing = true
        Task { @MainActor in
            do {
                let items = try await itemProvider.getAllItems()
                viewState.dataList = items
                viewState.isRefreshing = false
            } catch {
                viewState.errorText = error.localizedDescription
                viewState.showError = true
                viewState.isRefreshing = false
            }
        }
    }

    func addNewItem(title: String, content: String) {
        let newItem = ItemModel(title: title, content: content)
        Task { @MainActor in
            try? await itemProvider.saveItem(newItem)
            loadData()
        }
    }

    func removeItem(at index: Int) {
        guard index < viewState.dataList.count else { return }
        let item = viewState.dataList[index]
        Task { @MainActor in
            try? await itemProvider.deleteItem(item)
            loadData()
        }
    }
}
```

### 3.2 Screen 视图实现

```swift
struct MainScreen: View {
    @StateObject private var controller = MainController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if controller.viewState.isRefreshing {
                    loadingSection
                } else {
                    contentSection
                }
            }
            .navigationTitle("主页")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            }
        }
        .onAppear { controller.onAppear() }
        .onDisappear { controller.onDisappear() }
        .alert("提示", isPresented: $controller.viewState.showError) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(controller.viewState.errorText)
        }
    }

    private var loadingSection: some View {
        VStack {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        }
    }

    private var contentSection: some View {
        List {
            ForEach(Array(controller.viewState.dataList.enumerated()), id: \.element.id) { index, item in
                ListCard(item: item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            controller.removeItem(at: index)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            controller.loadData()
        }
    }

    private var addButton: some View {
        Button {
            // 添加逻辑
        } label: {
            Image(systemName: "plus")
        }
    }
}
```

## 四、数据存储 - UserDefaults + Plist

### 4.1 PreferencesManager (UserDefaults封装)

```swift
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Generic Methods

    func setValue<T: Codable>(_ value: T, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(value) {
            defaults.set(encoded, forKey: key)
        }
    }

    func getValue<T: Codable>(forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Convenience Methods

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func getString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func getBool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func setInt(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func getInt(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }
}

// 存储键定义
enum StorageKeys {
    static let itemList = "app.storage.itemList"
    static let userSettings = "app.storage.userSettings"
    static let lastSyncTime = "app.storage.lastSyncTime"
    static let isFirstLaunch = "app.storage.isFirstLaunch"
    static let selectedTheme = "app.storage.selectedTheme"
}
```

### 4.2 PlistStorage (Plist文件存储)

```swift
final class PlistStorage {
    static let shared = PlistStorage()

    private let fileManager = FileManager.default

    private var documentsPath: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {}

    // MARK: - Save

    func save<T: Codable>(_ object: T, toFile fileName: String) async throws {
        let fileURL = documentsPath.appendingPathComponent("\(fileName).plist")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(object)
        try data.write(to: fileURL)
    }

    // MARK: - Load

    func load<T: Codable>(fromFile fileName: String) async throws -> T {
        let fileURL = documentsPath.appendingPathComponent("\(fileName).plist")
        let data = try Data(contentsOf: fileURL)
        let decoder = PropertyListDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Delete

    func delete(fileName: String) async throws {
        let fileURL = documentsPath.appendingPathComponent("\(fileName).plist")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Check Exists

    func fileExists(fileName: String) -> Bool {
        let fileURL = documentsPath.appendingPathComponent("\(fileName).plist")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - Load Default Plist from Bundle

    func loadFromBundle<T: Codable>(fileName: String) throws -> T {
        guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: "plist") else {
            throw StorageError.fileNotFound
        }
        let data = try Data(contentsOf: bundleURL)
        let decoder = PropertyListDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

enum StorageError: Error {
    case fileNotFound
    case encodingFailed
    case decodingFailed
}
```

### 4.3 数据模型

```swift
struct ItemModel: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var content: String
    var createTime: Date
    var updateTime: Date

    init(id: String = UUID().uuidString, title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
        self.createTime = Date()
        self.updateTime = Date()
    }
}

struct UserPreferences: Codable {
    var themeMode: Int
    var fontSize: Int
    var notificationEnabled: Bool
    var language: String

    static var defaultValue: UserPreferences {
        UserPreferences(
            themeMode: 0,
            fontSize: 16,
            notificationEnabled: true,
            language: "zh-Hans"
        )
    }
}
```

### 4.4 ItemProvider (数据提供者)

```swift
final class ItemProvider {
    static let shared = ItemProvider()

    private let preferences = PreferencesManager.shared
    private let plistStorage = PlistStorage.shared
    private let storageFileName = "ItemData"

    private init() {}

    func getAllItems() async throws -> [ItemModel] {
        // 优先从Plist加载
        if plistStorage.fileExists(fileName: storageFileName) {
            return try await plistStorage.load(fromFile: storageFileName)
        }
        // 回退到UserDefaults
        if let items: [ItemModel] = preferences.getValue(forKey: StorageKeys.itemList) {
            return items
        }
        return []
    }

    func saveItem(_ item: ItemModel) async throws {
        var items = (try? await getAllItems()) ?? []
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try await plistStorage.save(items, toFile: storageFileName)
    }

    func deleteItem(_ item: ItemModel) async throws {
        var items = (try? await getAllItems()) ?? []
        items.removeAll { $0.id == item.id }
        try await plistStorage.save(items, toFile: storageFileName)
    }

    func clearAll() async throws {
        try await plistStorage.delete(fileName: storageFileName)
        preferences.removeValue(forKey: StorageKeys.itemList)
    }
}
```

## 五、网络层设计

```swift
final class APIManager {
    static let shared = APIManager()

    private let session: URLSession
    private let baseURLString = "https://api.example.com"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable>(path: String, params: [String: String]? = nil) async throws -> T {
        var components = URLComponents(string: baseURLString + path)
        if let params = params {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable, U: Encodable>(path: String, body: U) async throws -> T {
        guard let url = URL(string: baseURLString + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: Error {
    case invalidURL
    case requestFailed
    case decodingFailed
}
```

## 六、命名规范

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| 文件 | PascalCase | `MainScreen.swift` |
| Screen | Screen后缀 | `MainScreen` |
| Controller | Controller后缀 | `MainController` |
| Provider | Provider后缀 | `ItemProvider` |
| 视图组件 | 描述性名称 | `ActionButton`, `InfoCard` |
| 扩展文件 | Type+Ext | `View+Ext.swift` |
| 变量 | camelCase | `viewState`, `dataList` |

## 七、代码风格

### 7.1 文件头注释
```swift
//
//  FileName.swift
//  ProjectB
//
//  MVC + UserDefaults/Plist
//  Author: Developer
//
```

### 7.2 MARK 标记
```swift
final class ExampleController {
    // MARK: - Properties

    // MARK: - Lifecycle

    // MARK: - Public Methods

    // MARK: - Private Methods
}
```

### 7.3 闭包简写
- 单行闭包使用简写: `items.map { $0.name }`
- 多行闭包使用完整参数名

## 八、特色标识

- 架构标识: `// MARK: - MVC Pattern`
- 存储标识: `// Storage: UserDefaults + Plist`
- 控制器使用 `final class` 声明
- Screen 使用 `struct` 声明

## 九、第三方依赖

仅使用 Apple 原生框架：
- SwiftUI
- Foundation
