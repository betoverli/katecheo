import Foundation
import ObjectiveC
import UIKit
import WebKit

/// One-time import of Capacitor / site WebView `localStorage` into the native store.
///
/// Pre–Phase 5 the iOS shell loaded `https://verse2note.com` (not `capacitor://`), so
/// durable client data lived in the default `WKWebsiteDataStore` under that origin:
/// - `cita-settings` — zustand persist (notes ≤200, speakers ≤80, prefs, collections, plans…)
/// - `verse2note-outbox` — pending cloud jobs (`note.*`, `speaker.*`, `collection.*`, `prefs`, …)
/// - `grok-auth.bearer-token` — bearer if cookie migration missed it
///
/// No IndexedDB stores held notebook data (notes were localStorage-only). Import is
/// idempotent: extract once, push via outbox safely, never enqueue deletes, never wipe
/// server rows. Hidden `WKWebView` runs **once** on the **main thread**.
@MainActor
enum LegacyWebStorageImporter {
    static let statusKey = "verse2note.legacyWebImport.v1"
    static let summaryKey = "verse2note.legacyWebImport.summary.v1"

    enum Status: String {
        case pending
        case extracted
        case completed
        case empty
    }

    struct Summary: Codable {
        var notes: Int
        var speakers: Int
        var collections: Int
        var outboxJobs: Int
        var prefs: Bool
        var bearerRecovered: Bool
    }

    private static var hostView: WKWebView?
    private static var running = false

    static var status: Status {
        let raw = UserDefaults.standard.string(forKey: statusKey) ?? Status.pending.rawValue
        return Status(rawValue: raw) ?? .pending
    }

    private static func setStatus(_ status: Status) {
        UserDefaults.standard.set(status.rawValue, forKey: statusKey)
    }

    /// Entry point: cookie→Keychain first, then localStorage import, then outbox flush.
    static func runIfNeeded() async {
        precondition(Thread.isMainThread, "LegacyWebStorageImporter must run on the main thread")
        guard !running else { return }
        running = true
        defer { running = false }

        switch status {
        case .completed, .empty:
            await NativeOutbox.flushIfPossible()
            return
        case .extracted:
            // WebKit already read once — only retry the durable outbox push.
            await NativeOutbox.flushIfPossible()
            if NativeOutbox.pendingCount == 0 {
                setStatus(.completed)
            }
            return
        case .pending:
            break
        }

        let bag = await extractLocalStorage()
        applyExtracted(bag)
    }

    // MARK: - Extract (hidden WKWebView, once)

    private struct StorageBag {
        var citaSettings: String?
        var outbox: String?
        var bearer: String?
    }

    private static func extractLocalStorage() async -> StorageBag {
        await withCheckedContinuation { (continuation: CheckedContinuation<StorageBag, Never>) in
            precondition(Thread.isMainThread)
            // Uses the default data store (same jar as the old Cap https://verse2note.com host).
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: WKWebViewConfiguration())
            webView.isHidden = true
            hostView = webView

            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first
            {
                window.addSubview(webView)
            }

            let bridge = NavigationBridge { result in
                webView.removeFromSuperview()
                hostView = nil
                continuation.resume(returning: result)
            }
            webView.navigationDelegate = bridge
            objc_setAssociatedObject(webView, &Associated.bridge, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            let url = NativeAPIClient.baseURL.appendingPathComponent("auth/native-config")
            webView.load(URLRequest(url: url))

            // Hard timeout so a network hang never blocks cold start forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                guard hostView === webView else { return }
                bridge.finish(.init(citaSettings: nil, outbox: nil, bearer: nil))
            }
        }
    }

    private final class NavigationBridge: NSObject, WKNavigationDelegate {
        private var finished = false
        private let onDone: (StorageBag) -> Void

        init(onDone: @escaping (StorageBag) -> Void) {
            self.onDone = onDone
        }

        func finish(_ bag: StorageBag) {
            guard !finished else { return }
            finished = true
            onDone(bag)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            (function(){
              function g(k){ try { return localStorage.getItem(k); } catch(e) { return null; } }
              return JSON.stringify({
                cita: g('cita-settings'),
                outbox: g('verse2note-outbox'),
                bearer: g('grok-auth.bearer-token')
              });
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                var bag = StorageBag()
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    bag.citaSettings = obj["cita"] as? String
                    bag.outbox = obj["outbox"] as? String
                    bag.bearer = obj["bearer"] as? String
                }
                self?.finish(bag)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.init(citaSettings: nil, outbox: nil, bearer: nil))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.init(citaSettings: nil, outbox: nil, bearer: nil))
        }
    }

    private enum Associated {
        static var bridge: UInt8 = 0
    }

    // MARK: - Apply

    private static func applyExtracted(_ bag: StorageBag) {
        var summary = Summary(notes: 0, speakers: 0, collections: 0, outboxJobs: 0, prefs: false, bearerRecovered: false)
        var importJobs: [NativeOutbox.Job] = []

        if !NativeAPIClient.hasBearer, let bearer = bag.bearer, !bearer.isEmpty {
            if KeychainStore.setBearerToken(bearer) {
                summary.bearerRecovered = true
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            }
        }

        if let raw = bag.citaSettings, let data = raw.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let state = (root["state"] as? [String: Any]) ?? root
            summary = mergeCitaState(state, summary: summary, jobs: &importJobs)
        }

        if let raw = bag.outbox, let data = raw.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any]
        {
            let fromOutbox = convertLegacyOutbox(list)
            importJobs.append(contentsOf: fromOutbox)
            summary.outboxJobs += fromOutbox.count
        }

        NativeOutbox.enqueueImported(jobs: importJobs)

        let empty = summary.notes == 0
            && summary.speakers == 0
            && summary.collections == 0
            && summary.outboxJobs == 0
            && !summary.prefs
            && !summary.bearerRecovered

        if let encoded = try? JSONEncoder().encode(summary),
           let text = String(data: encoded, encoding: .utf8)
        {
            UserDefaults.standard.set(text, forKey: summaryKey)
        }

        if empty {
            setStatus(.empty)
            print("[LegacyImport] no WebView localStorage payload to import")
        } else {
            setStatus(.extracted)
            print("[LegacyImport] extracted notes=\(summary.notes) speakers=\(summary.speakers) collections=\(summary.collections) outbox=\(summary.outboxJobs)")
            NotificationCenter.default.post(name: .nativeNoteDidChange, object: nil)
            Task { @MainActor in
                await NativeOutbox.flushIfPossible()
                if NativeAPIClient.hasBearer, NativeOutbox.pendingCount == 0 {
                    setStatus(.completed)
                }
            }
        }
    }

    private static func mergeCitaState(
        _ state: [String: Any],
        summary: Summary,
        jobs: inout [NativeOutbox.Job]
    ) -> Summary {
        var summary = summary
        var localNotes = LocalNoteCache.loadNotes()
        var noteById = Dictionary(uniqueKeysWithValues: localNotes.map { ($0.id, $0) })

        if let notesRaw = state["notes"] as? [Any] {
            for item in notesRaw.prefix(200) {
                guard let doc = LegacyNoteConverter.noteDocument(fromLegacy: item) else { continue }
                if let existing = noteById[doc.id] {
                    let chosen = LegacyNoteConverter.preferNewer(existing, doc)
                    noteById[doc.id] = chosen
                    if chosen.updatedAt == doc.updatedAt, chosen != existing {
                        summary.notes += 1
                        if let payload = try? JSONEncoder().encode(chosen) {
                            jobs.append(NativeOutbox.makeJob(type: .noteUpsert, payload: payload))
                        }
                    }
                } else {
                    noteById[doc.id] = doc
                    summary.notes += 1
                    if let payload = try? JSONEncoder().encode(doc) {
                        jobs.append(NativeOutbox.makeJob(type: .noteUpsert, payload: payload))
                    }
                }
            }
            localNotes = Array(noteById.values).sorted { lhs, rhs in
                if lhs.happenedAt != rhs.happenedAt { return lhs.happenedAt > rhs.happenedAt }
                return lhs.updatedAt > rhs.updatedAt
            }
            LocalNoteCache.saveNotes(localNotes)
        }

        if let speakersRaw = state["speakers"] as? [Any] {
            var speakers = LocalNoteCache.loadSpeakers()
            var byId = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })
            for item in speakersRaw.prefix(80) {
                guard let speaker = LegacyNoteConverter.speaker(fromLegacy: item) else { continue }
                if byId[speaker.id] == nil || (byId[speaker.id]?.updatedAt ?? "") < speaker.updatedAt {
                    byId[speaker.id] = speaker
                    summary.speakers += 1
                    if let payload = try? JSONEncoder().encode(speaker) {
                        jobs.append(NativeOutbox.makeJob(type: .speakerUpsert, payload: payload))
                    }
                }
            }
            speakers = Array(byId.values)
            LocalNoteCache.saveSpeakers(speakers)
        }

        if let collections = state["myCollections"] as? [Any] {
            for item in collections.prefix(40) {
                guard let row = item as? [String: Any] else { continue }
                let id = (row["id"] as? String) ?? ""
                let title = (row["title"] as? String) ?? ""
                guard !id.isEmpty, !title.isEmpty else { continue }
                let passages = (row["passages"] as? [Any] ?? []).compactMap { raw -> NativeAPIClient.PassageDTO? in
                    guard let p = raw as? [String: Any],
                          let bookId = p["bookId"] as? String,
                          let chapter = p["chapter"] as? Int
                    else { return nil }
                    return NativeAPIClient.PassageDTO(
                        bookId: bookId,
                        chapter: chapter,
                        verseStart: p["verseStart"] as? Int,
                        verseEnd: p["verseEnd"] as? Int
                    )
                }
                let dto = NativeAPIClient.UserCollectionDTO(
                    id: String(id.prefix(40)),
                    title: String(title.prefix(60)),
                    slug: row["slug"] as? String,
                    visibility: row["visibility"] as? String,
                    sourceId: row["sourceId"] as? String,
                    passages: passages,
                    updatedAt: row["updatedAt"] as? String
                )
                if let payload = try? JSONEncoder().encode(dto) {
                    jobs.append(NativeOutbox.makeJob(type: .collectionUpsert, payload: payload))
                    summary.collections += 1
                }
            }
        }

        var prefsPatch: [String: Any] = [:]
        let stringKeys = [
            "locale", "copyLocale", "appId", "translationId", "copyFormat",
            "citeBook", "citeSep", "theme",
        ]
        for key in stringKeys {
            if let value = state[key] as? String, !value.isEmpty {
                prefsPatch[key] = value
            }
        }
        if let preferNative = state["preferNative"] as? Bool { prefsPatch["preferNative"] = preferNative }
        if let booksCompact = state["booksCompact"] as? Bool { prefsPatch["booksCompact"] = booksCompact }
        if let activePlans = state["activePlans"] as? [String] { prefsPatch["activePlans"] = activePlans }
        // planProgress is server-owned via plan_marks; prefs PATCH ignores client planProgress.
        if !prefsPatch.isEmpty {
            summary.prefs = true
            if let payload = try? JSONSerialization.data(withJSONObject: prefsPatch) {
                jobs.append(NativeOutbox.makeJob(type: .prefsPatch, payload: payload))
            }
        }

        return summary
    }

    /// Convert legacy `verse2note-outbox` jobs. **Skips deletes** so import never removes server data.
    private static func convertLegacyOutbox(_ list: [Any]) -> [NativeOutbox.Job] {
        var out: [NativeOutbox.Job] = []
        for item in list.prefix(80) {
            guard let row = item as? [String: Any], let type = row["type"] as? String else { continue }
            switch type {
            case "note.upsert":
                guard let noteRaw = row["note"],
                      let doc = LegacyNoteConverter.noteDocument(fromLegacy: noteRaw),
                      let payload = try? JSONEncoder().encode(doc)
                else { continue }
                LocalNoteCache.upsertNote(doc)
                out.append(NativeOutbox.makeJob(type: .noteUpsert, payload: payload))
            case "speaker.upsert":
                guard let speakerRaw = row["speaker"],
                      let speaker = LegacyNoteConverter.speaker(fromLegacy: speakerRaw),
                      let payload = try? JSONEncoder().encode(speaker)
                else { continue }
                var speakers = LocalNoteCache.loadSpeakers()
                if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
                    speakers[idx] = speaker
                } else {
                    speakers.append(speaker)
                }
                LocalNoteCache.saveSpeakers(speakers)
                out.append(NativeOutbox.makeJob(type: .speakerUpsert, payload: payload))
            case "prefs":
                // Full prefs snapshot isn't in the job — cita-settings merge already queued a patch.
                continue
            case "collection.upsert":
                guard let col = row["collection"] as? [String: Any],
                      let id = col["id"] as? String,
                      let title = col["title"] as? String,
                      !id.isEmpty, !title.isEmpty
                else { continue }
                let passages = (col["passages"] as? [Any] ?? []).compactMap { raw -> NativeAPIClient.PassageDTO? in
                    guard let p = raw as? [String: Any],
                          let bookId = p["bookId"] as? String,
                          let chapter = p["chapter"] as? Int
                    else { return nil }
                    return NativeAPIClient.PassageDTO(
                        bookId: bookId,
                        chapter: chapter,
                        verseStart: p["verseStart"] as? Int,
                        verseEnd: p["verseEnd"] as? Int
                    )
                }
                let dto = NativeAPIClient.UserCollectionDTO(
                    id: id,
                    title: title,
                    slug: col["slug"] as? String,
                    visibility: col["visibility"] as? String,
                    sourceId: col["sourceId"] as? String,
                    passages: passages,
                    updatedAt: col["updatedAt"] as? String
                )
                if let payload = try? JSONEncoder().encode(dto) {
                    out.append(NativeOutbox.makeJob(type: .collectionUpsert, payload: payload))
                }
            case "note.delete", "speaker.delete", "collection.delete", "plan.mark", "plan.reset":
                // Intentionally skipped: import must not delete server data; plan marks via prefs.
                continue
            default:
                continue
            }
        }
        return out
    }
}
