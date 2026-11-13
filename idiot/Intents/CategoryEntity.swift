import AppIntents
import Foundation

nonisolated struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    let id: UUID
    let name: String
    let typeName: String
    let iconName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(typeName)", image: .init(systemName: iconName))
    }
}

extension CategoryEntity {
    @MainActor
    init(_ category: Category) {
        self.init(
            id: category.id,
            name: category.name.isEmpty ? "Untitled" : category.name,
            typeName: category.type.displayName,
            iconName: category.iconName
        )
    }
}

nonisolated struct CategoryEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let wanted = Set(identifiers)
        return IntentData.categories().filter { wanted.contains($0.id) }.map(CategoryEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CategoryEntity] {
        IntentData.categories().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        IntentData.categories().map(CategoryEntity.init)
    }
}

nonisolated struct ExpenseCategoryOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [CategoryEntity] {
        IntentData.categories(.expense).map(CategoryEntity.init)
    }
}

nonisolated struct IncomeCategoryOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [CategoryEntity] {
        IntentData.categories(.income).map(CategoryEntity.init)
    }
}
