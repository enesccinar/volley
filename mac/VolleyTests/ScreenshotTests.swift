import AppKit
import SwiftUI
import XCTest
@testable import Volley

/// Renders the messages window with fixture data and captures it. Skipped unless
/// `VOLLEY_SNAPSHOT_DIR` is set (pass `TEST_RUNNER_VOLLEY_SNAPSHOT_DIR=<dir>` to xcodebuild).
@MainActor
final class ScreenshotTests: XCTestCase {
    private var transport: FakeTransport!
    private var session: PhoneSession!
    private var outDir: URL!
    private let conn = ConnectionID()

    override func setUp() async throws {
        guard let dir = ProcessInfo.processInfo.environment["VOLLEY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set VOLLEY_SNAPSHOT_DIR to capture screenshots")
        }
        outDir = URL(fileURLWithPath: dir)
        transport = FakeTransport()
        let trust = FakeTrust()
        trust.save(PairedDevice(id: "d1", name: "Pixel 8"), token: "t1")
        session = PhoneSession(identity: MacIdentity(id: "mac", name: "Mac"), transport: transport, trust: trust,
                               notifier: FakeNotifier(), store: GRDBMessageStore.inMemory(),
                               defaults: scratchDefaults())
        transport.onEvent?(.opened(conn))
        deliver(MsgType.hello, Hello(deviceId: "d1", deviceName: "Pixel 8", token: "t1"))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let minute: Int64 = 60_000
        let ana = Participant(address: "+15550101", contactName: "Ana")
        let bob = Participant(address: "+15550102", contactName: "Bob")
        let cleo = Participant(address: "+15550103", contactName: "Cleo")
        deliver(MsgType.smsBatch, SmsBatch(messages: [
            sms(1, thread: 1, address: "+15550101", name: "Ana", body: "Lunch tomorrow at noon?",
                date: now - 90 * minute),
            sms(2, thread: 2, address: "+15550104", name: "Dana", body: "The package arrived", date: now - 60 * minute),
            sms(3, thread: 3, address: "+15550105", body: "Your code is 482913", date: now - 45 * minute),
            mms(4, thread: 4, address: "+15550102", name: "Bob", body: "Who's bringing snacks for launch day?",
                date: now - 30 * minute, participants: [ana, bob, cleo]),
            sms(5, thread: 5, address: "+15550106", name: "Eli", body: "Running ten minutes late",
                date: now - 5 * minute)
        ], done: true))
    }

    private func deliver<B: Encodable>(_ type: String, _ body: B) {
        transport.onEvent?(.text(conn, Codec.encode(type, body)!))
    }

    func testCaptureSearchAndRetry() throws {
        try capture("search-results", query: "lnch")
        try capture("search-no-matches", query: "zebra")
        session.open(threadId: 1)
        session.sendSms(to: "+15550101", threadId: 1, body: "Sounds good, see you there")
        let req = try XCTUnwrap(transport.sentBodies(MsgType.smsSend, as: SmsSend.self).last)
        deliver(MsgType.smsSent, SmsSent(requestId: req.requestId, ok: false, error: "No service"))
        try capture("failed-send-try-again")
    }

    private func capture(_ name: String, query: String? = nil) throws {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 620),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Volley"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = NSHostingController(rootView: MessagesView(session: session))
        window.setContentSize(NSSize(width: 1000, height: 620))
        window.orderFrontRegardless()
        defer { window.close() }
        settle()
        if let query {
            let field = try XCTUnwrap(searchField(in: window), "no search field in the toolbar")
            field.stringValue = query
            field.sendAction(field.action, to: field.target)
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            field.delegate?
                .controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            settle()
        }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let path = outDir.appendingPathComponent("\(name).png").path
        // The theme frame, so the toolbar and its search field are in the picture too.
        let frame = try XCTUnwrap(window.contentView?.superview)
        let rep = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    }

    private func searchField(in window: NSWindow) -> NSSearchField? {
        if let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first { return item.searchField }
        func find(_ view: NSView) -> NSSearchField? {
            if let f = view as? NSSearchField { return f }
            return view.subviews.lazy.compactMap(find).first
        }
        return window.contentView?.superview.flatMap(find)
    }
}
