import UIKit

/// Local port of `src/lib/bible/apps.ts` `buildDeepLink` — open Bible refs without a network round-trip.
enum BibleDeepLink {
    struct AppMeta {
        let id: String
        let hasWeb: Bool
        let hasNative: Bool
    }

    struct BookMeta {
        let id: String
        let num: Int
        let logos: String
        let bibliaOnline: String
        let blb: String
        let bibleHub: String
        let names: [String: String]
    }

    struct TranslationMeta {
        let id: String
        let youVersion: Int
        let bibleGateway: String
        let bibliaOnline: String?
        let blb: String
    }

    struct Passage {
        var bookId: String
        var chapter: Int
        var verseStart: Int?
        var verseEnd: Int?
    }

    /// Test seam — when set, `open` calls this instead of `UIApplication.shared.open`.
    static var testOpenHandler: ((URL) -> Void)?
    /// Test seam — overrides `canOpenURL` for native-scheme preference.
    static var testCanOpenURL: ((URL) -> Bool)?

    private static let apps: [AppMeta] = [
        .init(id: "youversion", hasWeb: true, hasNative: true),
        .init(id: "tecarta", hasWeb: true, hasNative: true),
        .init(id: "logos", hasWeb: true, hasNative: false),
        .init(id: "olive-tree", hasWeb: false, hasNative: true),
        .init(id: "bible-gateway", hasWeb: true, hasNative: false),
        .init(id: "blue-letter", hasWeb: true, hasNative: false),
        .init(id: "esv", hasWeb: true, hasNative: false),
        .init(id: "biblia-online", hasWeb: true, hasNative: false),
        .init(id: "bible-hub", hasWeb: true, hasNative: false),
        .init(id: "accordance", hasWeb: false, hasNative: true),
        .init(id: "e-sword", hasWeb: false, hasNative: true),
        .init(id: "mysword", hasWeb: false, hasNative: true),
        .init(id: "jw-library", hasWeb: false, hasNative: true)
    ]

    private static let books: [BookMeta] = [
        .init(id: "GEN", num: 1, logos: "Ge", bibliaOnline: "gn", blb: "gen", bibleHub: "genesis", names: ["en": "Genesis", "pt": "Gênesis", "es": "Génesis"]),
        .init(id: "EXO", num: 2, logos: "Ex", bibliaOnline: "ex", blb: "exo", bibleHub: "exodus", names: ["en": "Exodus", "pt": "Êxodo", "es": "Éxodo"]),
        .init(id: "LEV", num: 3, logos: "Le", bibliaOnline: "lv", blb: "lev", bibleHub: "leviticus", names: ["en": "Leviticus", "pt": "Levítico", "es": "Levítico"]),
        .init(id: "NUM", num: 4, logos: "Nu", bibliaOnline: "nm", blb: "num", bibleHub: "numbers", names: ["en": "Numbers", "pt": "Números", "es": "Números"]),
        .init(id: "DEU", num: 5, logos: "Dt", bibliaOnline: "dt", blb: "deu", bibleHub: "deuteronomy", names: ["en": "Deuteronomy", "pt": "Deuteronômio", "es": "Deuteronomio"]),
        .init(id: "JOS", num: 6, logos: "Jos", bibliaOnline: "js", blb: "jos", bibleHub: "joshua", names: ["en": "Joshua", "pt": "Josué", "es": "Josué"]),
        .init(id: "JDG", num: 7, logos: "Jdg", bibliaOnline: "jz", blb: "jdg", bibleHub: "judges", names: ["en": "Judges", "pt": "Juízes", "es": "Jueces"]),
        .init(id: "RUT", num: 8, logos: "Ru", bibliaOnline: "rt", blb: "rut", bibleHub: "ruth", names: ["en": "Ruth", "pt": "Rute", "es": "Rut"]),
        .init(id: "1SA", num: 9, logos: "1Sa", bibliaOnline: "1sm", blb: "1sa", bibleHub: "1_samuel", names: ["en": "1 Samuel", "pt": "1 Samuel", "es": "1 Samuel"]),
        .init(id: "2SA", num: 10, logos: "2Sa", bibliaOnline: "2sm", blb: "2sa", bibleHub: "2_samuel", names: ["en": "2 Samuel", "pt": "2 Samuel", "es": "2 Samuel"]),
        .init(id: "1KI", num: 11, logos: "1Ki", bibliaOnline: "1rs", blb: "1ki", bibleHub: "1_kings", names: ["en": "1 Kings", "pt": "1 Reis", "es": "1 Reyes"]),
        .init(id: "2KI", num: 12, logos: "2Ki", bibliaOnline: "2rs", blb: "2ki", bibleHub: "2_kings", names: ["en": "2 Kings", "pt": "2 Reis", "es": "2 Reyes"]),
        .init(id: "1CH", num: 13, logos: "1Ch", bibliaOnline: "1cr", blb: "1ch", bibleHub: "1_chronicles", names: ["en": "1 Chronicles", "pt": "1 Crônicas", "es": "1 Crónicas"]),
        .init(id: "2CH", num: 14, logos: "2Ch", bibliaOnline: "2cr", blb: "2ch", bibleHub: "2_chronicles", names: ["en": "2 Chronicles", "pt": "2 Crônicas", "es": "2 Crónicas"]),
        .init(id: "EZR", num: 15, logos: "Ezr", bibliaOnline: "ed", blb: "ezr", bibleHub: "ezra", names: ["en": "Ezra", "pt": "Esdras", "es": "Esdras"]),
        .init(id: "NEH", num: 16, logos: "Ne", bibliaOnline: "ne", blb: "neh", bibleHub: "nehemiah", names: ["en": "Nehemiah", "pt": "Neemias", "es": "Nehemías"]),
        .init(id: "EST", num: 17, logos: "Es", bibliaOnline: "et", blb: "est", bibleHub: "esther", names: ["en": "Esther", "pt": "Ester", "es": "Ester"]),
        .init(id: "JOB", num: 18, logos: "Job", bibliaOnline: "job", blb: "job", bibleHub: "job", names: ["en": "Job", "pt": "Jó", "es": "Job"]),
        .init(id: "PSA", num: 19, logos: "Ps", bibliaOnline: "sl", blb: "psa", bibleHub: "psalms", names: ["en": "Psalms", "pt": "Salmos", "es": "Salmos"]),
        .init(id: "PRO", num: 20, logos: "Pr", bibliaOnline: "pv", blb: "pro", bibleHub: "proverbs", names: ["en": "Proverbs", "pt": "Provérbios", "es": "Proverbios"]),
        .init(id: "ECC", num: 21, logos: "Ec", bibliaOnline: "ec", blb: "ecc", bibleHub: "ecclesiastes", names: ["en": "Ecclesiastes", "pt": "Eclesiastes", "es": "Eclesiastés"]),
        .init(id: "SNG", num: 22, logos: "So", bibliaOnline: "ct", blb: "sng", bibleHub: "song_of_solomon", names: ["en": "Song of Songs", "pt": "Cânticos", "es": "Cantares"]),
        .init(id: "ISA", num: 23, logos: "Is", bibliaOnline: "is", blb: "isa", bibleHub: "isaiah", names: ["en": "Isaiah", "pt": "Isaías", "es": "Isaías"]),
        .init(id: "JER", num: 24, logos: "Je", bibliaOnline: "jr", blb: "jer", bibleHub: "jeremiah", names: ["en": "Jeremiah", "pt": "Jeremias", "es": "Jeremías"]),
        .init(id: "LAM", num: 25, logos: "La", bibliaOnline: "lm", blb: "lam", bibleHub: "lamentations", names: ["en": "Lamentations", "pt": "Lamentações", "es": "Lamentaciones"]),
        .init(id: "EZK", num: 26, logos: "Eze", bibliaOnline: "ez", blb: "eze", bibleHub: "ezekiel", names: ["en": "Ezekiel", "pt": "Ezequiel", "es": "Ezequiel"]),
        .init(id: "DAN", num: 27, logos: "Da", bibliaOnline: "dn", blb: "dan", bibleHub: "daniel", names: ["en": "Daniel", "pt": "Daniel", "es": "Daniel"]),
        .init(id: "HOS", num: 28, logos: "Ho", bibliaOnline: "os", blb: "hos", bibleHub: "hosea", names: ["en": "Hosea", "pt": "Oséias", "es": "Oseas"]),
        .init(id: "JOL", num: 29, logos: "Joe", bibliaOnline: "jl", blb: "joe", bibleHub: "joel", names: ["en": "Joel", "pt": "Joel", "es": "Joel"]),
        .init(id: "AMO", num: 30, logos: "Am", bibliaOnline: "am", blb: "amo", bibleHub: "amos", names: ["en": "Amos", "pt": "Amós", "es": "Amós"]),
        .init(id: "OBA", num: 31, logos: "Ob", bibliaOnline: "ob", blb: "oba", bibleHub: "obadiah", names: ["en": "Obadiah", "pt": "Obadias", "es": "Abdías"]),
        .init(id: "JON", num: 32, logos: "Jon", bibliaOnline: "jn", blb: "jon", bibleHub: "jonah", names: ["en": "Jonah", "pt": "Jonas", "es": "Jonás"]),
        .init(id: "MIC", num: 33, logos: "Mic", bibliaOnline: "mq", blb: "mic", bibleHub: "micah", names: ["en": "Micah", "pt": "Miqueias", "es": "Miqueas"]),
        .init(id: "NAM", num: 34, logos: "Na", bibliaOnline: "na", blb: "nah", bibleHub: "nahum", names: ["en": "Nahum", "pt": "Naum", "es": "Nahúm"]),
        .init(id: "HAB", num: 35, logos: "Hab", bibliaOnline: "hc", blb: "hab", bibleHub: "habakkuk", names: ["en": "Habakkuk", "pt": "Habacuque", "es": "Habacuc"]),
        .init(id: "ZEP", num: 36, logos: "Zep", bibliaOnline: "sf", blb: "zep", bibleHub: "zephaniah", names: ["en": "Zephaniah", "pt": "Sofonias", "es": "Sofonías"]),
        .init(id: "HAG", num: 37, logos: "Hag", bibliaOnline: "ag", blb: "hag", bibleHub: "haggai", names: ["en": "Haggai", "pt": "Ageu", "es": "Hageo"]),
        .init(id: "ZEC", num: 38, logos: "Zec", bibliaOnline: "zc", blb: "zec", bibleHub: "zechariah", names: ["en": "Zechariah", "pt": "Zacarias", "es": "Zacarías"]),
        .init(id: "MAL", num: 39, logos: "Mal", bibliaOnline: "ml", blb: "mal", bibleHub: "malachi", names: ["en": "Malachi", "pt": "Malaquias", "es": "Malaquías"]),
        .init(id: "MAT", num: 40, logos: "Mt", bibliaOnline: "mt", blb: "mat", bibleHub: "matthew", names: ["en": "Matthew", "pt": "Mateus", "es": "Mateo"]),
        .init(id: "MRK", num: 41, logos: "Mk", bibliaOnline: "mc", blb: "mrk", bibleHub: "mark", names: ["en": "Mark", "pt": "Marcos", "es": "Marcos"]),
        .init(id: "LUK", num: 42, logos: "Lk", bibliaOnline: "lc", blb: "luk", bibleHub: "luke", names: ["en": "Luke", "pt": "Lucas", "es": "Lucas"]),
        .init(id: "JHN", num: 43, logos: "Jn", bibliaOnline: "jo", blb: "jhn", bibleHub: "john", names: ["en": "John", "pt": "João", "es": "Juan"]),
        .init(id: "ACT", num: 44, logos: "Ac", bibliaOnline: "at", blb: "act", bibleHub: "acts", names: ["en": "Acts", "pt": "Atos", "es": "Hechos"]),
        .init(id: "ROM", num: 45, logos: "Ro", bibliaOnline: "rm", blb: "rom", bibleHub: "romans", names: ["en": "Romans", "pt": "Romanos", "es": "Romanos"]),
        .init(id: "1CO", num: 46, logos: "1Co", bibliaOnline: "1co", blb: "1co", bibleHub: "1_corinthians", names: ["en": "1 Corinthians", "pt": "1 Coríntios", "es": "1 Corintios"]),
        .init(id: "2CO", num: 47, logos: "2Co", bibliaOnline: "2co", blb: "2co", bibleHub: "2_corinthians", names: ["en": "2 Corinthians", "pt": "2 Coríntios", "es": "2 Corintios"]),
        .init(id: "GAL", num: 48, logos: "Ga", bibliaOnline: "gl", blb: "gal", bibleHub: "galatians", names: ["en": "Galatians", "pt": "Gálatas", "es": "Gálatas"]),
        .init(id: "EPH", num: 49, logos: "Eph", bibliaOnline: "ef", blb: "eph", bibleHub: "ephesians", names: ["en": "Ephesians", "pt": "Efésios", "es": "Efesios"]),
        .init(id: "PHP", num: 50, logos: "Php", bibliaOnline: "fp", blb: "phl", bibleHub: "philippians", names: ["en": "Philippians", "pt": "Filipenses", "es": "Filipenses"]),
        .init(id: "COL", num: 51, logos: "Col", bibliaOnline: "cl", blb: "col", bibleHub: "colossians", names: ["en": "Colossians", "pt": "Colossenses", "es": "Colosenses"]),
        .init(id: "1TH", num: 52, logos: "1Th", bibliaOnline: "1ts", blb: "1th", bibleHub: "1_thessalonians", names: ["en": "1 Thessalonians", "pt": "1 Tessalonicenses", "es": "1 Tesalonicenses"]),
        .init(id: "2TH", num: 53, logos: "2Th", bibliaOnline: "2ts", blb: "2th", bibleHub: "2_thessalonians", names: ["en": "2 Thessalonians", "pt": "2 Tessalonicenses", "es": "2 Tesalonicenses"]),
        .init(id: "1TI", num: 54, logos: "1Ti", bibliaOnline: "1tm", blb: "1ti", bibleHub: "1_timothy", names: ["en": "1 Timothy", "pt": "1 Timóteo", "es": "1 Timoteo"]),
        .init(id: "2TI", num: 55, logos: "2Ti", bibliaOnline: "2tm", blb: "2ti", bibleHub: "2_timothy", names: ["en": "2 Timothy", "pt": "2 Timóteo", "es": "2 Timoteo"]),
        .init(id: "TIT", num: 56, logos: "Tit", bibliaOnline: "tt", blb: "tit", bibleHub: "titus", names: ["en": "Titus", "pt": "Tito", "es": "Tito"]),
        .init(id: "PHM", num: 57, logos: "Phm", bibliaOnline: "fm", blb: "phm", bibleHub: "philemon", names: ["en": "Philemon", "pt": "Filemom", "es": "Filemón"]),
        .init(id: "HEB", num: 58, logos: "Heb", bibliaOnline: "hb", blb: "heb", bibleHub: "hebrews", names: ["en": "Hebrews", "pt": "Hebreus", "es": "Hebreos"]),
        .init(id: "JAS", num: 59, logos: "Jas", bibliaOnline: "tg", blb: "jas", bibleHub: "james", names: ["en": "James", "pt": "Tiago", "es": "Santiago"]),
        .init(id: "1PE", num: 60, logos: "1Pe", bibliaOnline: "1pe", blb: "1pe", bibleHub: "1_peter", names: ["en": "1 Peter", "pt": "1 Pedro", "es": "1 Pedro"]),
        .init(id: "2PE", num: 61, logos: "2Pe", bibliaOnline: "2pe", blb: "2pe", bibleHub: "2_peter", names: ["en": "2 Peter", "pt": "2 Pedro", "es": "2 Pedro"]),
        .init(id: "1JN", num: 62, logos: "1Jn", bibliaOnline: "1jo", blb: "1jo", bibleHub: "1_john", names: ["en": "1 John", "pt": "1 João", "es": "1 Juan"]),
        .init(id: "2JN", num: 63, logos: "2Jn", bibliaOnline: "2jo", blb: "2jo", bibleHub: "2_john", names: ["en": "2 John", "pt": "2 João", "es": "2 Juan"]),
        .init(id: "3JN", num: 64, logos: "3Jn", bibliaOnline: "3jo", blb: "3jo", bibleHub: "3_john", names: ["en": "3 John", "pt": "3 João", "es": "3 Juan"]),
        .init(id: "JUD", num: 65, logos: "Jud", bibliaOnline: "jd", blb: "jde", bibleHub: "jude", names: ["en": "Jude", "pt": "Judas", "es": "Judas"]),
        .init(id: "REV", num: 66, logos: "Re", bibliaOnline: "ap", blb: "rev", bibleHub: "revelation", names: ["en": "Revelation", "pt": "Apocalipse", "es": "Apocalipsis"])
    ]

    private static let translations: [TranslationMeta] = [
        .init(id: "nvi-pt", youVersion: 129, bibleGateway: "NVI", bibliaOnline: "nvi", blb: "nvi"),
        .init(id: "ntlh", youVersion: 211, bibleGateway: "NTLH", bibliaOnline: "ntlh", blb: "ntlh"),
        .init(id: "arc", youVersion: 1608, bibleGateway: "ARC", bibliaOnline: "arc", blb: "arc"),
        .init(id: "naa", youVersion: 1840, bibleGateway: "NAA", bibliaOnline: "naa", blb: "naa"),
        .init(id: "ara", youVersion: 212, bibleGateway: "ARA", bibliaOnline: "aa", blb: "ara"),
        .init(id: "niv", youVersion: 111, bibleGateway: "NIV", bibliaOnline: nil, blb: "niv"),
        .init(id: "esv", youVersion: 59, bibleGateway: "ESV", bibliaOnline: nil, blb: "esv"),
        .init(id: "kjv", youVersion: 1, bibleGateway: "KJV", bibliaOnline: nil, blb: "kjv"),
        .init(id: "nlt", youVersion: 116, bibleGateway: "NLT", bibliaOnline: nil, blb: "nlt"),
        .init(id: "nkjv", youVersion: 114, bibleGateway: "NKJV", bibliaOnline: nil, blb: "nkjv"),
        .init(id: "nasb", youVersion: 100, bibleGateway: "NASB", bibliaOnline: nil, blb: "nasb95"),
        .init(id: "csb", youVersion: 1713, bibleGateway: "CSB", bibliaOnline: nil, blb: "csb"),
        .init(id: "web", youVersion: 206, bibleGateway: "WEB", bibliaOnline: nil, blb: "web"),
        .init(id: "rvr1960", youVersion: 128, bibleGateway: "RVR1960", bibliaOnline: nil, blb: "rvr60"),
        .init(id: "nvi-es", youVersion: 103, bibleGateway: "NVI", bibliaOnline: nil, blb: "nvi"),
        .init(id: "ntv", youVersion: 149, bibleGateway: "NTV", bibliaOnline: nil, blb: "ntv")
    ]

    private static let booksById: [String: BookMeta] = {
        Dictionary(uniqueKeysWithValues: books.map { ($0.id.uppercased(), $0) })
    }()

    private static let translationsById: [String: TranslationMeta] = {
        Dictionary(uniqueKeysWithValues: translations.map { ($0.id, $0) })
    }()

    static func app(for id: String) -> AppMeta {
        apps.first(where: { $0.id == id }) ?? apps[0]
    }

    static func book(for bookId: String) -> BookMeta? {
        booksById[bookId.uppercased()]
    }

    static func translation(for rawId: String, locale: String = AppLocale.apiCode) -> TranslationMeta {
        let canonical = ProfileBibleCatalog.canonicalTranslationId(rawId, locale: locale)
        if let hit = translationsById[canonical] { return hit }
        let fallbackId = ProfileBibleCatalog.defaultTranslationId(for: locale)
        return translationsById[fallbackId] ?? translations[0]
    }

    /// Mirrors `buildDeepLink` in `apps.ts`.
    static func buildDeepLink(
        appId: String,
        passage: Passage,
        translationId: String,
        preferNative: Bool,
        locale: String = AppLocale.apiCode
    ) -> String? {
        guard let book = book(for: passage.bookId) else { return nil }
        let app = app(for: appId)
        let translation = translation(for: translationId, locale: locale)
        let native = (preferNative && app.hasNative) ? true : !app.hasWeb
        switch app.id {
        case "youversion": return youVersion(book: book, passage: passage, translation: translation, preferNative: native)
        case "tecarta": return tecarta(book: book, passage: passage, preferNative: native)
        case "logos": return logos(book: book, passage: passage)
        case "olive-tree": return oliveTree(book: book, passage: passage)
        case "bible-gateway": return bibleGateway(book: book, passage: passage, translation: translation)
        case "blue-letter": return blueLetter(book: book, passage: passage, translation: translation)
        case "esv": return esvOrg(book: book, passage: passage)
        case "biblia-online": return bibliaOnline(book: book, passage: passage, translation: translation)
        case "bible-hub": return bibleHub(book: book, passage: passage)
        case "accordance": return accordance(book: book, passage: passage)
        case "e-sword": return eSword(book: book, passage: passage)
        case "mysword": return mySword(book: book, passage: passage)
        case "jw-library": return jwLibrary(book: book, passage: passage)
        default: return youVersion(book: book, passage: passage, translation: translation, preferNative: native)
        }
    }

    /// HTTPS Keep/WhatsApp URL — falls back to YouVersion web when the app has no site.
    static func buildHttpLink(
        appId: String,
        passage: Passage,
        translationId: String,
        locale: String = AppLocale.apiCode
    ) -> String? {
        let preferred = buildDeepLink(appId: appId, passage: passage, translationId: translationId, preferNative: false, locale: locale)
        if let preferred, preferred.hasPrefix("http") { return preferred }
        return buildDeepLink(appId: "youversion", passage: passage, translationId: translationId, preferNative: false, locale: locale) ?? preferred
    }

    // MARK: - Prefs (disk / account defaults)

    struct ResolvedPrefs {
        var appId: String
        var translationId: String
        var preferNative: Bool
        var locale: String
    }

    /// Read cached prefs without network. Falls back to account defaults.
    static func loadLocalPrefs() -> ResolvedPrefs {
        let prefs = NativeSWR.loadPrefs() ?? LocalSessionCache.loadMe()?.prefs
        let locale = prefs?.locale ?? AppLocale.apiCode
        let appId = prefs?.appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let translationRaw = prefs?.translationId ?? ProfileBibleCatalog.defaultTranslationId(for: locale)
        return ResolvedPrefs(
            appId: (appId?.isEmpty == false) ? appId! : "youversion",
            translationId: ProfileBibleCatalog.canonicalTranslationId(translationRaw, locale: locale),
            preferNative: prefs?.preferNative ?? true,
            locale: locale
        )
    }

    // MARK: - Open (native scheme preferred when installed)

    /// Pick the URL to open: installed native scheme first (even if preferNative is false), else HTTPS.
    static func urlForOpening(
        appId: String,
        passage: Passage,
        translationId: String,
        preferNative: Bool,
        locale: String = AppLocale.apiCode
    ) -> URL? {
        let nativeString = buildDeepLink(appId: appId, passage: passage, translationId: translationId, preferNative: true, locale: locale)
        let webString = buildDeepLink(appId: appId, passage: passage, translationId: translationId, preferNative: false, locale: locale)
            ?? buildHttpLink(appId: appId, passage: passage, translationId: translationId, locale: locale)

        if let nativeString,
           let nativeURL = URL(string: nativeString),
           isNativeScheme(nativeURL),
           canOpen(nativeURL) {
            return nativeURL
        }
        if let webString, let webURL = URL(string: webString) {
            return webURL
        }
        if preferNative, let nativeString, let nativeURL = URL(string: nativeString) {
            return nativeURL
        }
        return nil
    }

    static func open(_ url: URL) {
        if let testOpenHandler {
            testOpenHandler(url)
            return
        }
        // Never restrict to universal links — custom schemes must open the Bible app.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private static func isNativeScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme != "http" && scheme != "https"
    }

    private static func canOpen(_ url: URL) -> Bool {
        if let testCanOpenURL { return testCanOpenURL(url) }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - Builders (parity with apps.ts)

    private static func verseBounds(_ passage: Passage) -> (start: Int?, end: Int?) {
        guard let verseStart = passage.verseStart else { return (nil, nil) }
        guard let verseEnd = passage.verseEnd else { return (verseStart, verseStart) }
        return (min(verseStart, verseEnd), max(verseStart, verseEnd))
    }

    private static func usfmRef(book: BookMeta, passage: Passage) -> String {
        let bounds = verseBounds(passage)
        guard let start = bounds.start else { return "\(book.id).\(passage.chapter)" }
        if let end = bounds.end, end != start {
            return "\(book.id).\(passage.chapter).\(start)-\(end)"
        }
        return "\(book.id).\(passage.chapter).\(start)"
    }

    private static func englishName(_ book: BookMeta) -> String {
        book.names["en"] ?? book.id
    }

    private static func colonRef(book: BookMeta, passage: Passage, locale: String) -> String {
        let name = book.names[locale] ?? book.names["en"] ?? book.id
        let bounds = verseBounds(passage)
        guard let start = bounds.start else { return "\(name) \(passage.chapter)" }
        if let end = bounds.end, end != start {
            return "\(name) \(passage.chapter):\(start)-\(end)"
        }
        return "\(name) \(passage.chapter):\(start)"
    }

    /// JS `encodeURI` — leaves `:`, `/`, `?`, etc. intact; encodes spaces.
    private static func encodeURI(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ";,/?:@&=+$-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private static func youVersion(book: BookMeta, passage: Passage, translation: TranslationMeta, preferNative: Bool) -> String {
        let ref = usfmRef(book: book, passage: passage)
        if preferNative { return "youversion://bible?reference=\(ref)" }
        return "https://www.bible.com/bible/\(translation.youVersion)/\(ref)"
    }

    private static func tecarta(book: BookMeta, passage: Passage, preferNative: Bool) -> String {
        let bounds = verseBounds(passage)
        let name = englishName(book).replacingOccurrences(of: " ", with: "+")
        var tail = "\(name)+\(passage.chapter)"
        if let start = bounds.start {
            tail += ":\(start)"
            if let end = bounds.end, end != start {
                tail += "-\(end)"
            }
        }
        if preferNative {
            let ref = colonRef(book: book, passage: passage, locale: "en")
            return "bible://\(encodeURI(ref))"
        }
        return "https://tecartabible.com/bible/\(tail)"
    }

    private static func logos(book: BookMeta, passage: Passage) -> String {
        let bounds = verseBounds(passage)
        var ref = "\(book.logos)\(passage.chapter)"
        if let start = bounds.start {
            ref += ".\(start)"
            if let end = bounds.end, end != start {
                ref += "-\(end)"
            }
        }
        return "https://ref.ly/\(ref)"
    }

    private static func oliveTree(book: BookMeta, passage: Passage) -> String {
        let verse = verseBounds(passage).start ?? 1
        return "olivetree://bible/\(book.num).\(passage.chapter).\(verse)"
    }

    private static func bibleGateway(book: BookMeta, passage: Passage, translation: TranslationMeta) -> String {
        let search = encodeURIComponent(colonRef(book: book, passage: passage, locale: "en"))
        let version = encodeURIComponent(translation.bibleGateway)
        return "https://www.biblegateway.com/passage/?search=\(search)&version=\(version)"
    }

    private static func encodeURIComponent(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private static func blueLetter(book: BookMeta, passage: Passage, translation: TranslationMeta) -> String {
        let verse = verseBounds(passage).start ?? 1
        return "https://www.blueletterbible.org/\(translation.blb)/\(book.blb)/\(passage.chapter)/\(verse)"
    }

    private static func esvOrg(book: BookMeta, passage: Passage) -> String {
        let ref = colonRef(book: book, passage: passage, locale: "en").replacingOccurrences(of: " ", with: "+")
        return "https://www.esv.org/\(ref)/"
    }

    private static func bibliaOnline(book: BookMeta, passage: Passage, translation: TranslationMeta) -> String {
        let slug = translation.bibliaOnline ?? "nvi"
        let bounds = verseBounds(passage)
        var path = "https://www.bibliaonline.com.br/\(slug)/\(book.bibliaOnline)/\(passage.chapter)"
        if let start = bounds.start {
            path += "/\(start)"
            if let end = bounds.end, end != start {
                path += "-\(end)"
            }
        }
        return path
    }

    private static func bibleHub(book: BookMeta, passage: Passage) -> String {
        let bounds = verseBounds(passage)
        guard let start = bounds.start else {
            return "https://biblehub.com/\(book.bibleHub)/\(passage.chapter).htm"
        }
        return "https://biblehub.com/\(book.bibleHub)/\(passage.chapter)-\(start).htm"
    }

    private static func accordance(book: BookMeta, passage: Passage) -> String {
        let ref = colonRef(book: book, passage: passage, locale: "en").replacingOccurrences(of: " ", with: "_")
        return "accord://read/?\(ref)"
    }

    private static func eSword(book: BookMeta, passage: Passage) -> String {
        let verse = verseBounds(passage).start ?? 1
        let name = englishName(book).lowercased().replacingOccurrences(of: " ", with: "")
        return "e-sword://\(name).\(passage.chapter).\(verse)"
    }

    private static func mySword(book: BookMeta, passage: Passage) -> String {
        return "mysword://bible/\(encodeURI(colonRef(book: book, passage: passage, locale: "en")))"
    }

    private static func jwLibrary(book: BookMeta, passage: Passage) -> String {
        let bounds = verseBounds(passage)
        let verse = bounds.start ?? 1
        func code(_ bookNum: Int, _ ch: Int, _ v: Int) -> Int {
            bookNum * 1_000_000 + ch * 1000 + v
        }
        let a = code(book.num, passage.chapter, verse)
        if let end = bounds.end, end != verse {
            let b = code(book.num, passage.chapter, end)
            return "jwlibrary:///finder?bible=\(a)-\(b)"
        }
        return "jwlibrary:///finder?bible=\(a)"
    }
}
