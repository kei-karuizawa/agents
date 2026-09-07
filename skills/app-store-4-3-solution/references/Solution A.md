# 方案A - MVVM + CoreData 经典架构

## 一、架构概述

采用经典 MVVM（Model-View-ViewModel）架构配合 CoreData 持久化存储，使用 Combine 进行响应式编程。

## 二、项目结构

```
ProjectA/
├── App/
│   ├── ProjectAApp.swift              # 应用入口
│   └── AppDelegate.swift              # 应用代理（CoreData初始化）
├── Core/
│   ├── CoreData/
│   │   ├── ProjectA.xcdatamodeld      # CoreData模型
│   │   ├── CoreDataStack.swift        # CoreData栈管理
│   │   └── Entities/                  # NSManagedObject子类
│   ├── Network/
│   │   ├── APIClient.swift            # 网络请求客户端
│   │   ├── Endpoints.swift            # API端点定义
│   │   └── NetworkError.swift         # 网络错误类型
│   └── Utilities/
│       ├── Extensions/                # 扩展方法
│       ├── Helpers/                   # 工具类
│       └── Constants.swift            # 常量定义
├── Features/
│   ├── Home/
│   │   ├── Views/
│   │   │   ├── HomeView.swift
│   │   │   └── HomeSubviews/
│   │   ├── ViewModels/
│   │   │   └── HomeViewModel.swift
│   │   └── Models/
│   │       └── HomeModel.swift
│   ├── Settings/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
│   └── [OtherFeatures]/
├── Shared/
│   ├── Components/                    # 可复用UI组件
│   ├── Styles/                        # 样式定义
│   └── Modifiers/                     # ViewModifier
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.strings
    └── Info.plist
```

## 三、设计模式

### 3.1 MVVM 模式实现

```swift
// ViewModel 基类
import Combine
import Foundation

class BaseViewModel: ObservableObject {
    var cancellables = Set<AnyCancellable>()

    @Published var isLoading = false
    @Published var errorMessage: String?

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

// 具体 ViewModel 示例
class HomeViewModel: BaseViewModel {
    @Published var items: [ItemModel] = []

    private let repository: ItemRepository

    init(repository: ItemRepository = ItemRepository()) {
        self.repository = repository
        super.init()
        loadItems()
    }

    func loadItems() {
        isLoading = true
        repository.fetchItems()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] items in
                    self?.items = items
                }
            )
            .store(in: &cancellables)
    }
}
```

### 3.2 View 层实现

```swift
// View 示例
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    contentView
                }
            }
            .navigationTitle("首页")
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var contentView: some View {
        List(viewModel.items) { item in
            ItemRowView(item: item)
        }
    }
}
```

## 四、数据存储 - CoreData

### 4.1 CoreData 栈配置

```swift
import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "ProjectA")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }

    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError)")
            }
        }
    }
}
```

### 4.2 Repository 模式封装

```swift
protocol RepositoryProtocol {
    associatedtype Entity
    func fetchAll() -> AnyPublisher<[Entity], Error>
    func save(_ entity: Entity) -> AnyPublisher<Void, Error>
    func delete(_ entity: Entity) -> AnyPublisher<Void, Error>
}

class ItemRepository: RepositoryProtocol {
    private let coreDataStack: CoreDataStack

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    func fetchItems() -> AnyPublisher<[ItemModel], Error> {
        Future { [weak self] promise in
            guard let self = self else { return }
            let request: NSFetchRequest<ItemEntity> = ItemEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ItemEntity.createdAt, ascending: false)]

            do {
                let entities = try self.coreDataStack.viewContext.fetch(request)
                let models = entities.map { ItemModel(entity: $0) }
                promise(.success(models))
            } catch {
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
}
```

## 五、网络层设计

```swift
import Combine

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

protocol APIEndpoint {
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
}

class APIClient {
    static let shared = APIClient()
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://api.example.com")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) -> AnyPublisher<T, Error> {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.allHTTPHeaderFields = endpoint.headers
        request.httpBody = endpoint.body

        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: T.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
}
```

## 六、依赖注入

```swift
// 简单的依赖容器
class DependencyContainer {
    static let shared = DependencyContainer()

    lazy var coreDataStack = CoreDataStack.shared
    lazy var apiClient = APIClient.shared
    lazy var itemRepository = ItemRepository(coreDataStack: coreDataStack)

    private init() {}
}

// 使用 Environment 注入
struct ItemRepositoryKey: EnvironmentKey {
    static let defaultValue: ItemRepository = DependencyContainer.shared.itemRepository
}

extension EnvironmentValues {
    var itemRepository: ItemRepository {
        get { self[ItemRepositoryKey.self] }
        set { self[ItemRepositoryKey.self] = newValue }
    }
}
```

## 七、命名规范

| 类型 | 命名规则 | 示例 |
|------|---------|------|
| 文件 | PascalCase | `HomeViewModel.swift` |
| 类/结构体 | PascalCase | `HomeViewModel` |
| 变量/函数 | camelCase | `loadItems()` |
| 常量 | camelCase | `let maxCount = 10` |
| 协议 | PascalCase + Protocol后缀 | `RepositoryProtocol` |
| 扩展文件 | Type+Extension | `String+Validation.swift` |

## 八、代码风格

### 8.1 导入顺序
```swift
// 1. 系统框架（按字母排序）
import Combine
import CoreData
import Foundation
import SwiftUI

// 2. 第三方库（按字母排序）
// import Alamofire

// 3. 项目内部模块
// import MyModule
```

### 8.2 结构体/类内部顺序
```swift
struct/class Example {
    // 1. 类型别名
    // 2. 静态属性
    // 3. 静态方法
    // 4. 实例属性（按访问级别排序）
    // 5. 初始化方法
    // 6. 实例方法（按访问级别排序）
}
```

### 8.3 访问控制
- 默认使用 `private` 或 `fileprivate`
- 需要外部访问时使用 `internal`（可省略）
- 框架/模块接口使用 `public`

## 九、特色标识

- **架构标识**: `// MARK: - MVVM Pattern`
- **文件头注释格式**:
```swift
//
//  FileName.swift
//  ProjectA
//
//  Created by Developer on Date.
//  Architecture: MVVM + CoreData
//
```

## 十、第三方依赖

仅使用 Apple 原生框架：
- SwiftUI
- Combine
- CoreData
- Foundation
