import Foundation

final class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    
    private var cacheDirectory: URL? {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let cacheDir = docs.appendingPathComponent("Cache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        return cacheDir
    }
    
    func saveMovies(_ movies: [MovieItem], forKey key: String) {
        guard let dir = cacheDirectory else { return }
        let fileURL = dir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(movies) {
            try? data.write(to: fileURL)
        }
    }
    
    func loadMovies(forKey key: String) -> [MovieItem]? {
        guard let dir = cacheDirectory else { return nil }
        let fileURL = dir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([MovieItem].self, from: data)
    }
    
    func saveCategories(_ categories: [MovieCategory], forKey key: String) {
        guard let dir = cacheDirectory else { return }
        let fileURL = dir.appendingPathComponent("\(key)_categories.json")
        if let data = try? JSONEncoder().encode(categories) {
            try? data.write(to: fileURL)
        }
    }
    
    func loadCategories(forKey key: String) -> [MovieCategory]? {
        guard let dir = cacheDirectory else { return nil }
        let fileURL = dir.appendingPathComponent("\(key)_categories.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([MovieCategory].self, from: data)
    }

    func removeMovies(forKey key: String) {
        guard let dir = cacheDirectory else { return }
        let fileURL = dir.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: fileURL)
    }

    func removeCategories(forKey key: String) {
        guard let dir = cacheDirectory else { return }
        let fileURL = dir.appendingPathComponent("\(key)_categories.json")
        try? fileManager.removeItem(at: fileURL)
    }
}