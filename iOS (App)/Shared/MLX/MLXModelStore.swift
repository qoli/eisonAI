import Foundation

struct MLXModelStore {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadSelectedModelID() -> String? {
        let value = defaults?.string(forKey: AppConfig.mlxSelectedModelIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    func saveSelectedModelID(_ modelID: String?) {
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults?.set(trimmed, forKey: AppConfig.mlxSelectedModelIDKey)
    }

    func hasConfiguredModel() -> Bool {
        loadSelectedModelID() != nil
    }

    func loadInstalledModels() -> [InstalledMLXModel] {
        guard let data = defaults?.data(forKey: AppConfig.mlxInstalledModelsKey) else {
            return []
        }
        return (try? decoder.decode([InstalledMLXModel].self, from: data)) ?? []
    }

    func saveInstalledModels(_ models: [InstalledMLXModel]) {
        let sorted = models.sorted {
            ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast)
        }
        guard let data = try? encoder.encode(sorted) else { return }
        defaults?.set(data, forKey: AppConfig.mlxInstalledModelsKey)
    }

    func upsertInstalledModel(_ model: MLXCatalogModel) {
        var models = loadInstalledModels()
        let stored = InstalledMLXModel(model: model)
        if let index = models.firstIndex(where: { $0.id == stored.id }) {
            models[index] = stored
        } else {
            models.append(stored)
        }
        saveInstalledModels(models)
    }

    func removeInstalledModel(id: String) {
        let filtered = loadInstalledModels().filter { $0.id != id }
        saveInstalledModels(filtered)
        if loadSelectedModelID() == id {
            saveSelectedModelID(filtered.first?.id)
        }
    }
}
