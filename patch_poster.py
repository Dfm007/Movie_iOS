import pathlib

p = pathlib.Path(r'C:\Users\DUAN\Desktop\iosmovie\iosmovie\Sources\AppleCMSSource.swift')
text = p.read_text(encoding='utf-8')

old = '''    private func fetchMovies(path: String) async throws -> [MovieItem] {
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)
        return resp.list.map { item in
            MovieItem(
                id: String(item.vod_id),
                title: item.vod_name,
                type: item.type_name ?? "",
                year: item.vod_year ?? "",
                rating: item.vod_score ?? "",
                detailURL: String(item.vod_id),
                posterURL: item.vod_pic
            )
        }
    }
'''

new = '''    private func fetchMovies(path: String) async throws -> [MovieItem] {
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)
        let movies = resp.list.map { item in
            MovieItem(
                id: String(item.vod_id),
                title: item.vod_name,
                type: item.type_name ?? "",
                year: item.vod_year ?? "",
                rating: item.vod_score ?? "",
                detailURL: String(item.vod_id),
                posterURL: item.vod_pic
            )
        }
        return await fillPosters(for: movies)
    }

    private func fillPosters(for movies: [MovieItem]) async -> [MovieItem] {
        var result = movies
        let needPoster = movies.filter { $0.posterURL?.isEmpty ?? true }
        guard !needPoster.isEmpty else { return result }

        let semaphore = AsyncSemaphore(limit: 5)
        await withTaskGroup(of: (String, String?).self) { group in
            for movie in needPoster {
                group.addTask { [weak self] in
                    guard let self = self else { return (movie.id, nil) }
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    let poster = try? await self.fetchPoster(movieId: movie.id)
                    return (movie.id, poster)
                }
            }

            var posterMap: [String: String] = [:]
            for await (id, poster) in group {
                if let poster = poster {
                    posterMap[id] = poster
                }
            }

            for index in result.indices {
                if let poster = posterMap[result[index].id] {
                    result[index].posterURL = poster
                }
            }
        }
        return result
    }

    private func fetchPoster(movieId: String) async throws -> String? {
        guard let url = URL(string: "\(baseURL)?ac=detail&ids=\(movieId)") else { return nil }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)
        return resp.list.first?.vod_pic
    }
'''

if old in text:
    text = text.replace(old, new)
    print('FETCH_OK')
else:
    print('FETCH_MISS')

sem = '''

actor AsyncSemaphore {
    private var count: Int

    init(limit: Int) {
        self.count = limit
    }

    func wait() async {
        while count <= 0 {
            await Task.yield()
        }
        count -= 1
    }

    func signal() {
        count += 1
    }
}
'''

if 'private struct CMSSearchResponse' in text and 'AsyncSemaphore' not in text:
    text = text.replace('private struct CMSSearchResponse', sem + '\nprivate struct CMSSearchResponse')
    print('SEM_OK')
else:
    print('SEM_SKIP')

p.write_text(text, encoding='utf-8')
print('DONE')