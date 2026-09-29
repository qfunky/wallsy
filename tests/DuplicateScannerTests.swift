import Foundation

@main
struct DuplicateScannerTests {
    static func main() throws {
        let songs = try JSONDecoder().decode([Song].self, from: Data("""
        [
          {"id":"a","title":"One","size":4,"path":"A/one.flac"},
          {"id":"b","title":"One","size":4,"path":"B/one.flac"},
          {"id":"c","title":"Other","size":4,"path":"C/other.flac"},
          {"id":"d","title":"Unique","size":8},
          {"id":"e","title":"Unknown size"}
        ]
        """.utf8))

        let candidates = DuplicateScanner.candidates(from: songs)
        precondition(Set(candidates.map(\.id)) == Set(["a", "b", "c"]))

        let groups = DuplicateScanner.exactGroups(from: [
            ServerSongFingerprint(song: songs[0], digest: "same", size: 4),
            ServerSongFingerprint(song: songs[1], digest: "same", size: 4),
            ServerSongFingerprint(song: songs[2], digest: "different", size: 4),
        ])
        precondition(groups.count == 1)
        precondition(groups[0].songs.map(\.id) == ["a", "b"])
        precondition(groups[0].recoverableBytes == 4)
        precondition(!groups[0].hasSameReportedPath)

        let sharedPathSongs = try JSONDecoder().decode([Song].self, from: Data("""
        [
          {"id":"first","title":"One","size":4,"path":"Virtual/one.flac"},
          {"id":"second","title":"One","size":4,"path":"Virtual/one.flac"}
        ]
        """.utf8))
        let sharedPathGroup = DuplicateScanner.exactGroups(from: sharedPathSongs.map {
            ServerSongFingerprint(song: $0, digest: "same", size: 4)
        })
        precondition(sharedPathGroup.count == 1 && sharedPathGroup[0].hasSameReportedPath)
        print("Server duplicate grouping OK")
    }
}
