import XCTest
@testable import Volley

final class FuzzySearchTests: XCTestCase {
    private func note(_ key: String, app: String = "Mail", title: String = "", text: String = "",
                      at secs: Double = 0) -> StoredNotification {
        StoredNotification(key: key, contentHash: key, pkg: "p.\(app)", appName: app, title: title, text: text,
                           postedAt: Date(timeIntervalSince1970: secs), receivedAt: Date(timeIntervalSince1970: secs),
                           cleared: false)
    }

    func testSubsequenceMatches() { XCTAssertNotNil(FuzzySearch.score("dploy", in: "deploy is green")) }

    func testNonSubsequenceFails() { XCTAssertNil(FuzzySearch.score("xyz", in: "deploy is green")) }

    func testCaseAndDiacriticInsensitive() { XCTAssertNotNil(FuzzySearch.score("CAFE", in: "Café au lait")) }

    func testWordStartBeatsScattered() {
        XCTAssertGreaterThan(FuzzySearch.score("dep", in: "deploy")!, FuzzySearch.score("dep", in: "dxexpx")!)
        XCTAssertGreaterThan(FuzzySearch.score("green", in: "deploy is green")!,
                             FuzzySearch.score("green", in: "gxrxexexn")!)
    }

    func testTokensCanMatchDifferentFields() {
        let items = [note("a", app: "Slack", text: "deploy is green"), note("b", app: "Mail", text: "deploy is green")]
        XCTAssertEqual(FuzzySearch.search("slack green", in: items).map(\.key), ["a"])
    }

    func testAllTokensMustMatch() {
        XCTAssertTrue(FuzzySearch.search("deploy zzz", in: [note("a", text: "deploy is green")]).isEmpty)
    }

    func testRankingThenRecency() {
        let items = [
            note("scattered", title: "dxexpxlxoxy", at: 3),
            note("old", title: "deploy", at: 1),
            note("new", title: "deploy", at: 2)
        ]
        XCTAssertEqual(FuzzySearch.search("deploy", in: items).map(\.key), ["new", "old", "scattered"])
    }

    func testSloppyQueryFindsIt() {
        let items = [note("a", title: "Ana", text: "deploy is green")]
        XCTAssertEqual(FuzzySearch.search("dploy grn", in: items).map(\.key), ["a"])
    }

    func testBlankQueryReturnsInput() {
        let items = [note("b", at: 1), note("a", at: 2)]
        XCTAssertEqual(FuzzySearch.search("   ", in: items), items)
    }

    private func convo(_ id: Int64, name: String? = nil, address: String = "+1555", body: String = "",
                       members: [String] = [], at secs: Double = 0) -> ConversationSummary {
        ConversationSummary(threadId: id, address: address, name: name, lastBody: body,
                            lastDate: Date(timeIntervalSince1970: secs), participants: members)
    }

    func testConversationsMatchByNameNumberAndBody() {
        let items = [
            convo(1, name: "Ana", address: "+1555", body: "see you soon"),
            convo(2, name: "Bob", address: "+1777", body: "lunch tomorrow?")
        ]
        XCTAssertEqual(FuzzySearch.search("ana", in: items).map(\.threadId), [1])
        XCTAssertEqual(FuzzySearch.search("1777", in: items).map(\.threadId), [2])
        XCTAssertEqual(FuzzySearch.search("lnch", in: items).map(\.threadId), [2])
    }

    func testGroupConversationMatchesAnyMember() {
        let items = [convo(1, members: ["Ana", "Bob", "Cleo", "Dev"]), convo(2, name: "Eve")]
        XCTAssertEqual(FuzzySearch.search("cleo", in: items).map(\.threadId), [1])
    }

    func testConversationTiesGoNewestFirst() {
        let items = [convo(1, name: "Ana", at: 1), convo(2, name: "Ana", at: 2)]
        XCTAssertEqual(FuzzySearch.search("ana", in: items).map(\.threadId), [2, 1])
    }
}
