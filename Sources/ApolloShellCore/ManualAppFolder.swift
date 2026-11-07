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
