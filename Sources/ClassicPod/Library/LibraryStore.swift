import Foundation
import AVFoundation
import PodCore

actor LibraryStore {
    struct Index: Codable { var version = 1; var tracks: [Track] = [] }
    struct ImportResult: Sendable { var tracks: [Track]; var errors: [String] }
    private let file: URL
    private var index = Index()
    private var loadError: String?
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClassicPod/library.json")
    }
    func load() throws -> [Track] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        do {
            let decoded = try JSONDecoder().decode(Index.self, from: Data(contentsOf: file))
            guard decoded.version == 1 else { throw PodError.message(L10n.text("Неизвестная версия библиотеки; индекс не изменён.")) }
            index = decoded; loadError = nil
            return index.tracks
        } catch { loadError = error.localizedDescription; throw error }
    }
    func importURLs(_ roots: [URL]) async throws -> ImportResult {
        if let loadError { throw PodError.message(L10n.format("Индекс защищён от перезаписи: %@", loadError)) }
        var urls: [URL] = []
        for root in roots {
            let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true {
                guard values?.isSymbolicLink != true else { continue }
                let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let url = iterator?.nextObject() as? URL {
                    let entry = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if entry?.isSymbolicLink == true { iterator?.skipDescendants(); continue }
                    if entry?.isDirectory != true { urls.append(url) }
                }
            } else { urls.append(root) }
        }
        var errors: [String] = []
        for url in urls.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            guard ["mp3", "m4a", "flac", "wav"].contains(url.pathExtension.lowercased()) else { continue }
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            if index.tracks.contains(where: { $0.id == canonical.path || (try? Self.resolve($0).resolvingSymlinksInPath().standardizedFileURL.path) == canonical.path }) { continue }
            do { index.tracks.append(try await Self.read(canonical)) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        try persist()
        return ImportResult(tracks: index.tracks, errors: errors)
    }
    func relocate(id: String, to url: URL) async throws -> [Track] {
        if let loadError { throw PodError.message(L10n.format("Индекс защищён от перезаписи: %@", loadError)) }
        guard let position = index.tracks.firstIndex(where: { $0.id == id }) else { return index.tracks }
        var replacement = try await Self.read(url)
        replacement.id = id
        index.tracks[position] = replacement
        try persist()
        return index.tracks
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: file, options: .atomic)
    }
    static func resolve(_ track: Track) throws -> URL {
        guard case .local(let bookmark, let path) = track.location else { throw PodError.message(L10n.text("Не локальный файл")) }
        var stale = false
        let url = (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)) ?? URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw PodError.message(L10n.format("Файл перемещён: %@. Выберите новый путь в библиотеке.", track.title)) }
        return url
    }
    private static func read(_ url: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw PodError.message(L10n.text("Формат не воспроизводится AVFoundation")) }
        let duration = try await asset.load(.duration).seconds
        let metadata = try await asset.load(.commonMetadata)
        func string(_ key: AVMetadataKey) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let title = await string(.commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent
        let artist = await string(.commonKeyArtist) ?? "Неизвестный исполнитель"
        let album = await string(.commonKeyAlbumName) ?? "Неизвестный альбом"
        let item = AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first
        let artwork = try await item?.load(.dataValue)
        return Track(id: url.path, title: title, artist: artist, album: album, duration: duration.isFinite ? duration : 0, artwork: artwork,
                     location: .local(bookmark: try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), path: url.path))
    }
}
