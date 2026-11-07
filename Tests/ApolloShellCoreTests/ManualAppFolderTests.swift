import ApolloShellCore
import Foundation
import Testing

@Suite("Manuelle App-Ordner")
struct ManualAppFolderTests {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private func slots(_ ids: [String]) -> [DockSlot] {
        ids.map { DockSlot(bundleID: $0, pinned: false, running: true) }
    }

    private func kind(_ id: String) -> DockCategory.Kind {
        DockCategory.kind(key: String(id.prefix(while: { $0 != "." })))
    }

    private func members(_ items: [DockItem]) -> [String] {
        items.flatMap { item in
            switch item {
            case .app(let slot): [slot.bundleID]
            case .group(let group): group.members.map(\.bundleID)
            }
        }
    }

    @Test("alte Dock-Optionen behalten Smart Groups und lesen keine Ordner")
    func legacyOptionsDecodeWithoutFolders() throws {
        let legacy = try #require(try? JSONDecoder().decode(BarDockOptions.self, from: Data(#"{"showRunning":false}"#.utf8)))
        #expect(!legacy.showRunning)
        #expect(legacy.smartGroups)
        #expect(legacy.manualFolders.isEmpty)
    }

    @Test("manuelle Ordner bewahren Kennung, Namen und Reihenfolge beim Schreiben")
    func foldersRoundTrip() throws {
        let folder = ManualAppFolder(id: firstID, name: "Arbeit", bundleIDs: ["com.example.editor", "com.example.terminal"])
        let options = BarDockOptions(manualFolders: [folder])

        let decoded = try JSONDecoder().decode(BarDockOptions.self, from: JSONEncoder().encode(options))

        #expect(decoded == options)
        #expect(decoded.manualFolders[0].id == firstID)
        #expect(decoded.manualFolders[0].name == "Arbeit")
        #expect(decoded.manualFolders[0].bundleIDs == ["com.example.editor", "com.example.terminal"])
    }

    @Test("manuelle Mitglieder gewinnen, fehlen nur in der Anzeige und erscheinen nie doppelt")
    func manualMembersWinWithoutMutatingSavedFolders() {
        let folders = [
            ManualAppFolder(id: firstID, name: "Arbeit", bundleIDs: ["media.b", "not.installed", "dev.a", "media.b"]),
            ManualAppFolder(id: secondID, name: "Kommunikation", bundleIDs: ["dev.a", "chat.b"]),
        ]
        let visible = slots(["dev.a", "dev.b", "media.a", "media.b", "chat.a", "chat.b", "web.a", "web.b", "design.a", "design.b"])

        let items = ManualFolderPlanner.items(visible, folders: folders, smartGroups: false, weight: { _ in 0 }, kind: kind)
        let groups = items.compactMap { item -> DockGroup? in if case .group(let group) = item { group } else { nil } }
        let displayed = members(items)

        #expect(groups.map(\.id) == ["g:manual:\(firstID.uuidString)", "g:manual:\(secondID.uuidString)"])
        #expect(groups.map(\.title) == ["Arbeit", "Kommunikation"])
        #expect(groups[0].members.map(\.bundleID) == ["media.b", "dev.a"])
        #expect(groups[1].members.map(\.bundleID) == ["chat.b"])
        #expect(!displayed.contains("not.installed"))
        #expect(Set(displayed).count == displayed.count)
        #expect(Set(displayed) == Set(visible.map(\.bundleID)))
        #expect(folders[0].bundleIDs == ["media.b", "not.installed", "dev.a", "media.b"])
        #expect(folders[1].bundleIDs == ["dev.a", "chat.b"])
    }

    @Test("unzugeordnete Apps behalten DockClustering, Smart Groups bleiben optional")
    func unassignedAppsUseExistingOptionalClustering() {
        let folder = ManualAppFolder(id: firstID, name: "Fest", bundleIDs: ["dev.a"])
        let visible = slots(["dev.a", "dev.b", "dev.c", "media.a", "media.b", "chat.a", "chat.b", "web.a", "web.b", "design.a", "design.b"])
        let unassigned = visible.filter { $0.bundleID != "dev.a" }
        let expectedAutomatic = DockClustering.items(unassigned, weight: { _ in 0 }, kind: kind)

        let grouped = ManualFolderPlanner.items(visible, folders: [folder], smartGroups: true, weight: { _ in 0 }, kind: kind)
        let loose = ManualFolderPlanner.items(visible, folders: [folder], smartGroups: false, weight: { _ in 0 }, kind: kind)
        let noManualFolders = ManualFolderPlanner.items(visible, folders: [], smartGroups: true, weight: { _ in 0 }, kind: kind)

        #expect(Array(grouped.dropFirst()) == expectedAutomatic)
        #expect(Array(loose.dropFirst()) == unassigned.map(DockItem.app))
        #expect(noManualFolders == DockClustering.items(visible, weight: { _ in 0 }, kind: kind))
    }

    @Test("doppelte sichtbare Bundle-IDs erzeugen nur ein sichtbares Mitglied")
    func duplicateVisibleBundleIDsAreSuppressed() {
        let folder = ManualAppFolder(id: firstID, name: "Arbeit", bundleIDs: ["dev.a"])
        let visible = slots(["dev.a", "dev.a", "media.a"])

        let displayed = members(ManualFolderPlanner.items(visible, folders: [folder], smartGroups: false, weight: { _ in 0 }, kind: kind))

        #expect(displayed == ["dev.a", "media.a"])
    }

    @Test("Ordnerbearbeitung trimmt Namen und aendert nur die ausdruecklich bearbeitete Stelle")
    func editorMutationsPreserveUntouchedLegacyData() {
        var folders = [
            ManualAppFolder(id: firstID, name: "  Bestehend\n", bundleIDs: ["missing.app", "dev.a", "dev.a"]),
            ManualAppFolder(id: secondID, name: "Zwei", bundleIDs: ["dev.a", "chat.a"]),
        ]

        #expect(!ManualFolderEditor.rename(firstID, to: " \n ", in: &folders))
        #expect(folders[0].name == "  Bestehend\n")
        #expect(ManualFolderEditor.rename(firstID, to: " \n Arbeit \t", in: &folders))
        #expect(ManualFolderEditor.add(bundleID: "media.a", to: firstID, in: &folders))
        #expect(ManualFolderEditor.removeMember(at: 1, from: firstID, in: &folders))

        #expect(folders[0] == ManualAppFolder(id: firstID, name: "Arbeit", bundleIDs: ["missing.app", "dev.a", "media.a"]))
        #expect(folders[1] == ManualAppFolder(id: secondID, name: "Zwei", bundleIDs: ["dev.a", "chat.a"]))
    }

    @Test("Ordner und Mitglieder haben sichere Verschiebegrenzen und explizite Entfernung")
    func editorMoveBoundariesAndExplicitRemoval() {
        var folders = [
            ManualAppFolder(id: firstID, name: "Eins", bundleIDs: ["a", "b"]),
            ManualAppFolder(id: secondID, name: "Zwei", bundleIDs: ["c"]),
        ]

        #expect(!ManualFolderEditor.moveFolder(firstID, by: -1, in: &folders))
        #expect(!ManualFolderEditor.moveFolder(secondID, by: 1, in: &folders))
        #expect(ManualFolderEditor.moveFolder(secondID, by: -1, in: &folders))
        #expect(!ManualFolderEditor.moveMember(at: 0, in: firstID, by: -1, folders: &folders))
        #expect(!ManualFolderEditor.moveMember(at: 1, in: firstID, by: 1, folders: &folders))
        #expect(ManualFolderEditor.moveMember(at: 1, in: firstID, by: -1, folders: &folders))
        #expect(ManualFolderEditor.removeFolder(secondID, from: &folders))
        #expect(!ManualFolderEditor.removeFolder(secondID, from: &folders))

        #expect(folders == [ManualAppFolder(id: firstID, name: "Eins", bundleIDs: ["b", "a"])])
    }

    @Test("neue Ordner bekommen eine frische Kennung und lehnen leere Namen ab")
    func editorCreatesFreshFolderOnlyForNonEmptyName() {
        var folders = [ManualAppFolder(id: firstID, name: "Bestehend", bundleIDs: [])]

        #expect(ManualFolderEditor.create(named: " \n ", in: &folders) == nil)
        let created = ManualFolderEditor.create(named: " \n Neu \t", in: &folders)

        #expect(created != nil)
        #expect(created != firstID)
        #expect(folders.map(\.id).count == 2)
        #expect(folders.last == ManualAppFolder(id: created!, name: "Neu", bundleIDs: []))
    }
}
