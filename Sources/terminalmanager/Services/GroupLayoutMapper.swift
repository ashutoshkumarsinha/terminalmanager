import Foundation

enum GroupLayoutMapper {
    static func fromSplitLayout(_ node: SplitLayoutNode, tabToMember: [UUID: UUID]) -> GroupLayoutNode? {
        if let tabID = node.tabID {
            guard let memberID = tabToMember[tabID] else { return nil }
            return .leaf(memberID: memberID)
        }
        guard node.children.count == 2, let orientation = node.orientation else { return nil }
        guard let left = fromSplitLayout(node.children[0], tabToMember: tabToMember),
              let right = fromSplitLayout(node.children[1], tabToMember: tabToMember) else {
            return nil
        }
        return .split(orientation, left, right, ratio: node.ratio)
    }

    static func toSplitLayout(_ node: GroupLayoutNode, memberToTab: [UUID: UUID]) -> SplitLayoutNode? {
        if let memberID = node.memberID {
            guard let tabID = memberToTab[memberID] else { return nil }
            return .leaf(tabID: tabID)
        }
        guard node.children.count == 2, let orientation = node.orientation else { return nil }
        guard let left = toSplitLayout(node.children[0], memberToTab: memberToTab),
              let right = toSplitLayout(node.children[1], memberToTab: memberToTab) else {
            return nil
        }
        return .split(orientation, left, right, ratio: node.ratio)
    }

    static func remapMemberIDs(in node: GroupLayoutNode, map: [UUID: UUID]) -> GroupLayoutNode? {
        if let memberID = node.memberID {
            guard let newID = map[memberID] else { return nil }
            return .leaf(memberID: newID)
        }
        guard node.children.count == 2, let orientation = node.orientation else { return nil }
        guard let left = remapMemberIDs(in: node.children[0], map: map),
              let right = remapMemberIDs(in: node.children[1], map: map) else {
            return nil
        }
        return .split(orientation, left, right, ratio: node.ratio)
    }
}
