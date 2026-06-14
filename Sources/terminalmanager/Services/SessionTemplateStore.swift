import Foundation

enum SessionTemplateStore {
    private static var templatesJSONURL: URL {
        FileLocations.configDirectory.appendingPathComponent("templates.json")
    }

    static func load() -> [SessionTemplate] {
        let url = templatesJSONURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([SessionTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    static func save(_ templates: [SessionTemplate]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(templates)
        try FileManager.default.createDirectory(
            at: FileLocations.configDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: templatesJSONURL, options: .atomic)
    }

    static func allTemplates(from settings: AppSettings) -> [SessionTemplate] {
        let fromFile = load()
        if fromFile.isEmpty {
            return settings.sessionTemplates
        }
        if settings.sessionTemplates.isEmpty {
            return fromFile
        }
        var byID: [UUID: SessionTemplate] = [:]
        for template in fromFile {
            byID[template.id] = template
        }
        for template in settings.sessionTemplates {
            byID[template.id] = template
        }
        return Array(byID.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    static func add(_ template: SessionTemplate, to settings: inout AppSettings) throws -> SessionTemplate {
        var templates = allTemplates(from: settings)
        var saved = template
        if templates.contains(where: { $0.id == saved.id }) == false,
           templates.contains(where: { $0.name.compare(saved.name, options: .caseInsensitive) == .orderedSame }) {
            saved.name = uniqueName(basedOn: saved.name, among: templates)
        }
        templates.append(saved)
        try persist(templates, settings: &settings)
        return saved
    }

    @discardableResult
    static func update(_ template: SessionTemplate, in settings: inout AppSettings) throws -> SessionTemplate {
        var templates = allTemplates(from: settings)
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else {
            throw TemplateStoreError.notFound
        }
        templates[index] = template
        try persist(templates, settings: &settings)
        return template
    }

    static func delete(id: UUID, from settings: inout AppSettings) throws {
        var templates = allTemplates(from: settings)
        let previousCount = templates.count
        templates.removeAll { $0.id == id }
        guard templates.count != previousCount else {
            throw TemplateStoreError.notFound
        }
        try persist(templates, settings: &settings)
    }

    enum TemplateStoreError: Error {
        case notFound
    }

    private static func persist(_ templates: [SessionTemplate], settings: inout AppSettings) throws {
        try save(templates)
        settings.sessionTemplates = templates
    }

    private static func uniqueName(basedOn name: String, among templates: [SessionTemplate]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? "New Template" : base
        let existing = templates.map(\.name)
        if !existing.contains(where: { $0.compare(root, options: .caseInsensitive) == .orderedSame }) {
            return root
        }
        var counter = 2
        while existing.contains(where: { $0.compare("\(root) \(counter)", options: .caseInsensitive) == .orderedSame }) {
            counter += 1
        }
        return "\(root) \(counter)"
    }
}
