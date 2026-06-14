import XCTest
@testable import terminalmanager

final class GroupLayoutMapperTests: XCTestCase {
    func testMapsSplitLayoutToGroupLayoutAndBack() {
        let tabA = UUID()
        let tabB = UUID()
        let memberA = UUID()
        let memberB = UUID()
        let tabToMember = [tabA: memberA, tabB: memberB]
        let memberToTab = [memberA: tabA, memberB: tabB]

        let split = SplitLayoutNode.split(
            .vertical,
            .leaf(tabID: tabA),
            .leaf(tabID: tabB),
            ratio: 0.4
        )

        guard let groupLayout = GroupLayoutMapper.fromSplitLayout(split, tabToMember: tabToMember) else {
            return XCTFail("Expected group layout")
        }
        XCTAssertEqual(groupLayout.orientation, .vertical)
        XCTAssertEqual(groupLayout.ratio, 0.4, accuracy: 0.001)

        guard let restored = GroupLayoutMapper.toSplitLayout(groupLayout, memberToTab: memberToTab) else {
            return XCTFail("Expected split layout")
        }
        XCTAssertEqual(restored.tabIDsInLayout(), split.tabIDsInLayout())
    }

    func testRemapMemberIDsPreservesStructure() {
        let oldA = UUID()
        let oldB = UUID()
        let newA = UUID()
        let newB = UUID()
        let layout = GroupLayoutNode.split(
            .horizontal,
            .leaf(memberID: oldA),
            .leaf(memberID: oldB)
        )

        guard let remapped = GroupLayoutMapper.remapMemberIDs(
            in: layout,
            map: [oldA: newA, oldB: newB]
        ) else {
            return XCTFail("Expected remapped layout")
        }

        XCTAssertEqual(remapped.children[0].memberID, newA)
        XCTAssertEqual(remapped.children[1].memberID, newB)
    }
}
