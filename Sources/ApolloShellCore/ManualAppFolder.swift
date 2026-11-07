import Foundation

/// Ein vom Nutzer benannter App-Ordner im Dock der ApolloShell.
/// Die Mitgliedschaft bleibt gespeichert, auch wenn eine App voruebergehend
/// nicht installiert ist.
public struct ManualAppFolder: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]

    public init(id: UUID = UUID(), name: String, bundleIDs: [String]) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
    }
}

/// Intentional, local mutations for `BarDockOptions.manualFolders`.
///
/// This editor deliberately never canonicalizes the complete collection. Old
/// rows can contain duplicate or unavailable bundle IDs (and memberships that
/// overlap another folder); an unrelated edit must preserve those values.
public enum ManualFolderEditor {
    @discardableResult
    public static func create(named name: String, in folders: inout [ManualAppFolder]) -> UUID? {
        let name = trimmed(name)
        guard !name.isEmpty else { return nil }
        let folder = ManualAppFolder(name: name, bundleIDs: [])
        folders.append(folder)
        return folder.id
    }

    @discardableResult
    public static func rename(_ id: UUID, to name: String, in folders: inout [ManualAppFolder]) -> Bool {
        let name = trimmed(name)
        guard !name.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders[index].name = name
        return true
    }

    @discardableResult
    public static func removeFolder(_ id: UUID, from folders: inout [ManualAppFolder]) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders.remove(at: index)
        return true
    }

    @discardableResult
    public static func moveFolder(_ id: UUID, by step: Int, in folders: inout [ManualAppFolder]) -> Bool {
        guard step != 0, let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        let target = index + step
        guard folders.indices.contains(target) else { return false }
        folders.swapAt(index, target)
        return true
    }

    @discardableResult
    public static func add(bundleID: String, to id: UUID, in folders: inout [ManualAppFolder]) -> Bool {
        guard !bundleID.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders[index].bundleIDs.append(bundleID)
        return true
    }

    @discardableResult
    public static func removeMember(at memberIndex: Int, from id: UUID, in folders: inout [ManualAppFolder]) -> Bool {
        guard let folderIndex = folders.firstIndex(where: { $0.id == id }),
              folders[folderIndex].bundleIDs.indices.contains(memberIndex)
        else { return false }
        folders[folderIndex].bundleIDs.remove(at: memberIndex)
        return true
    }

    @discardableResult
    public static func moveMember(at memberIndex: Int, in id: UUID, by step: Int, folders: inout [ManualAppFolder]) -> Bool {
        guard step != 0, let folderIndex = folders.firstIndex(where: { $0.id == id }) else { return false }
        let target = memberIndex + step
        guard folders[folderIndex].bundleIDs.indices.contains(memberIndex),
              folders[folderIndex].bundleIDs.indices.contains(target)
        else { return false }
        folders[folderIndex].bundleIDs.swapAt(memberIndex, target)
        return true
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Baut die sichtbaren Dock-Elemente aus manuellen Ordnern und den
/// verbleibenden Apps. Der Typ kennt keine AppKit- oder SwiftUI-Typen, damit
/// die Zusammensetzung direkt getestet werden kann.
public enum ManualFolderPlanner {
    public static func items(
        _ slots: [DockSlot],
        folders: [ManualAppFolder],
        smartGroups: Bool,
        fixed: Set<String> = [],
        weight: (String) -> Double,
        kind: (String) -> DockCategory.Kind,
        partner: (String) -> String? = { _ in nil },
        limit: Int = DockClustering.limit,
        keep: Int = DockClustering.keep
    ) -> [DockItem] {
        let visible = uniqueSlots(slots)
        var slotByBundleID: [String: DockSlot] = [:]
        for slot in visible {
            slotByBundleID[slot.bundleID] = slot
        }

        var claimed = Set<String>()
        var folderIDs = Set<UUID>()
        var result: [DockItem] = []
        for folder in folders where folderIDs.insert(folder.id).inserted {
            var members: [DockSlot] = []
            for bundleID in folder.bundleIDs {
                guard !claimed.contains(bundleID), let slot = slotByBundleID[bundleID] else { continue }
                claimed.insert(bundleID)
                members.append(slot)
            }
            guard !members.isEmpty else { continue }
            result.append(.group(DockGroup(
                key: "manual:" + folder.id.uuidString,
                title: folder.name,
                symbol: "folder.fill",
                members: members
            )))
        }

        let unassigned = visible.filter { !claimed.contains($0.bundleID) }
        if smartGroups {
            result.append(contentsOf: DockClustering.items(
                unassigned,
                fixed: fixed.intersection(Set(unassigned.map(\.bundleID))),
                weight: weight,
                kind: kind,
                partner: partner,
                limit: limit,
                keep: keep
            ))
        } else {
            result.append(contentsOf: unassigned.map(DockItem.app))
        }
        return result
    }

    private static func uniqueSlots(_ slots: [DockSlot]) -> [DockSlot] {
        var seen = Set<String>()
        return slots.filter { seen.insert($0.bundleID).inserted }
    }
}
