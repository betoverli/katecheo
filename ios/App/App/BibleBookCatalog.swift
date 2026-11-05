import Foundation

/// Offline Bible book names/abbreviations (pt/en/es), mirrored from `src/lib/bible/books.ts`.
enum BibleBookCatalog {
    struct Entry {
        let id: String
        let names: [String: String]
        let abbr: [String: String]
    }

    static let all: [Entry] = [
        Entry(id: "GEN", names: ["pt": "Gênesis", "en": "Genesis", "es": "Génesis"], abbr: ["pt": "Gn", "en": "Gen", "es": "Gn"]),
        Entry(id: "EXO", names: ["pt": "Êxodo", "en": "Exodus", "es": "Éxodo"], abbr: ["pt": "Ex", "en": "Exod", "es": "Ex"]),
        Entry(id: "LEV", names: ["pt": "Levítico", "en": "Leviticus", "es": "Levítico"], abbr: ["pt": "Lv", "en": "Lev", "es": "Lv"]),
        Entry(id: "NUM", names: ["pt": "Números", "en": "Numbers", "es": "Números"], abbr: ["pt": "Nm", "en": "Num", "es": "Nm"]),
        Entry(id: "DEU", names: ["pt": "Deuteronômio", "en": "Deuteronomy", "es": "Deuteronomio"], abbr: ["pt": "Dt", "en": "Deut", "es": "Dt"]),
        Entry(id: "JOS", names: ["pt": "Josué", "en": "Joshua", "es": "Josué"], abbr: ["pt": "Js", "en": "Josh", "es": "Jos"]),
        Entry(id: "JDG", names: ["pt": "Juízes", "en": "Judges", "es": "Jueces"], abbr: ["pt": "Jz", "en": "Judg", "es": "Jue"]),
        Entry(id: "RUT", names: ["pt": "Rute", "en": "Ruth", "es": "Rut"], abbr: ["pt": "Rt", "en": "Ruth", "es": "Rt"]),
        Entry(id: "1SA", names: ["pt": "1 Samuel", "en": "1 Samuel", "es": "1 Samuel"], abbr: ["pt": "1Sm", "en": "1 Sam", "es": "1S"]),
        Entry(id: "2SA", names: ["pt": "2 Samuel", "en": "2 Samuel", "es": "2 Samuel"], abbr: ["pt": "2Sm", "en": "2 Sam", "es": "2S"]),
        Entry(id: "1KI", names: ["pt": "1 Reis", "en": "1 Kings", "es": "1 Reyes"], abbr: ["pt": "1Rs", "en": "1 Kgs", "es": "1R"]),
        Entry(id: "2KI", names: ["pt": "2 Reis", "en": "2 Kings", "es": "2 Reyes"], abbr: ["pt": "2Rs", "en": "2 Kgs", "es": "2R"]),
        Entry(id: "1CH", names: ["pt": "1 Crônicas", "en": "1 Chronicles", "es": "1 Crónicas"], abbr: ["pt": "1Cr", "en": "1 Chr", "es": "1Cr"]),
        Entry(id: "2CH", names: ["pt": "2 Crônicas", "en": "2 Chronicles", "es": "2 Crónicas"], abbr: ["pt": "2Cr", "en": "2 Chr", "es": "2Cr"]),
        Entry(id: "EZR", names: ["pt": "Esdras", "en": "Ezra", "es": "Esdras"], abbr: ["pt": "Ed", "en": "Ezra", "es": "Esd"]),
        Entry(id: "NEH", names: ["pt": "Neemias", "en": "Nehemiah", "es": "Nehemías"], abbr: ["pt": "Ne", "en": "Neh", "es": "Neh"]),
        Entry(id: "EST", names: ["pt": "Ester", "en": "Esther", "es": "Ester"], abbr: ["pt": "Et", "en": "Esth", "es": "Est"]),
        Entry(id: "JOB", names: ["pt": "Jó", "en": "Job", "es": "Job"], abbr: ["pt": "Jó", "en": "Job", "es": "Job"]),
        Entry(id: "PSA", names: ["pt": "Salmos", "en": "Psalms", "es": "Salmos"], abbr: ["pt": "Sl", "en": "Ps", "es": "Sal"]),
        Entry(id: "PRO", names: ["pt": "Provérbios", "en": "Proverbs", "es": "Proverbios"], abbr: ["pt": "Pv", "en": "Prov", "es": "Pr"]),
        Entry(id: "ECC", names: ["pt": "Eclesiastes", "en": "Ecclesiastes", "es": "Eclesiastés"], abbr: ["pt": "Ec", "en": "Eccl", "es": "Ec"]),
        Entry(id: "SNG", names: ["pt": "Cânticos", "en": "Song of Songs", "es": "Cantares"], abbr: ["pt": "Ct", "en": "Song", "es": "Cnt"]),
        Entry(id: "ISA", names: ["pt": "Isaías", "en": "Isaiah", "es": "Isaías"], abbr: ["pt": "Is", "en": "Isa", "es": "Is"]),
        Entry(id: "JER", names: ["pt": "Jeremias", "en": "Jeremiah", "es": "Jeremías"], abbr: ["pt": "Jr", "en": "Jer", "es": "Jer"]),
        Entry(id: "LAM", names: ["pt": "Lamentações", "en": "Lamentations", "es": "Lamentaciones"], abbr: ["pt": "Lm", "en": "Lam", "es": "Lm"]),
        Entry(id: "EZK", names: ["pt": "Ezequiel", "en": "Ezekiel", "es": "Ezequiel"], abbr: ["pt": "Ez", "en": "Ezek", "es": "Ez"]),
        Entry(id: "DAN", names: ["pt": "Daniel", "en": "Daniel", "es": "Daniel"], abbr: ["pt": "Dn", "en": "Dan", "es": "Dn"]),
        Entry(id: "HOS", names: ["pt": "Oséias", "en": "Hosea", "es": "Oseas"], abbr: ["pt": "Os", "en": "Hos", "es": "Os"]),
        Entry(id: "JOL", names: ["pt": "Joel", "en": "Joel", "es": "Joel"], abbr: ["pt": "Jl", "en": "Joel", "es": "Jl"]),
        Entry(id: "AMO", names: ["pt": "Amós", "en": "Amos", "es": "Amós"], abbr: ["pt": "Am", "en": "Amos", "es": "Am"]),
        Entry(id: "OBA", names: ["pt": "Obadias", "en": "Obadiah", "es": "Abdías"], abbr: ["pt": "Ob", "en": "Obad", "es": "Abd"]),
        Entry(id: "JON", names: ["pt": "Jonas", "en": "Jonah", "es": "Jonás"], abbr: ["pt": "Jn", "en": "Jonah", "es": "Jon"]),
        Entry(id: "MIC", names: ["pt": "Miqueias", "en": "Micah", "es": "Miqueas"], abbr: ["pt": "Mq", "en": "Mic", "es": "Mi"]),
        Entry(id: "NAM", names: ["pt": "Naum", "en": "Nahum", "es": "Nahúm"], abbr: ["pt": "Na", "en": "Nah", "es": "Nah"]),
        Entry(id: "HAB", names: ["pt": "Habacuque", "en": "Habakkuk", "es": "Habacuc"], abbr: ["pt": "Hc", "en": "Hab", "es": "Hab"]),
        Entry(id: "ZEP", names: ["pt": "Sofonias", "en": "Zephaniah", "es": "Sofonías"], abbr: ["pt": "Sf", "en": "Zeph", "es": "Sof"]),
        Entry(id: "HAG", names: ["pt": "Ageu", "en": "Haggai", "es": "Hageo"], abbr: ["pt": "Ag", "en": "Hag", "es": "Hag"]),
        Entry(id: "ZEC", names: ["pt": "Zacarias", "en": "Zechariah", "es": "Zacarías"], abbr: ["pt": "Zc", "en": "Zech", "es": "Zac"]),
        Entry(id: "MAL", names: ["pt": "Malaquias", "en": "Malachi", "es": "Malaquías"], abbr: ["pt": "Ml", "en": "Mal", "es": "Mal"]),
        Entry(id: "MAT", names: ["pt": "Mateus", "en": "Matthew", "es": "Mateo"], abbr: ["pt": "Mt", "en": "Matt", "es": "Mt"]),
        Entry(id: "MRK", names: ["pt": "Marcos", "en": "Mark", "es": "Marcos"], abbr: ["pt": "Mc", "en": "Mark", "es": "Mc"]),
        Entry(id: "LUK", names: ["pt": "Lucas", "en": "Luke", "es": "Lucas"], abbr: ["pt": "Lc", "en": "Luke", "es": "Lc"]),
        Entry(id: "JHN", names: ["pt": "João", "en": "John", "es": "Juan"], abbr: ["pt": "Jo", "en": "John", "es": "Jn"]),
        Entry(id: "ACT", names: ["pt": "Atos", "en": "Acts", "es": "Hechos"], abbr: ["pt": "At", "en": "Acts", "es": "Hch"]),
        Entry(id: "ROM", names: ["pt": "Romanos", "en": "Romans", "es": "Romanos"], abbr: ["pt": "Rm", "en": "Rom", "es": "Ro"]),
        Entry(id: "1CO", names: ["pt": "1 Coríntios", "en": "1 Corinthians", "es": "1 Corintios"], abbr: ["pt": "1Co", "en": "1 Cor", "es": "1Co"]),
        Entry(id: "2CO", names: ["pt": "2 Coríntios", "en": "2 Corinthians", "es": "2 Corintios"], abbr: ["pt": "2Co", "en": "2 Cor", "es": "2Co"]),
        Entry(id: "GAL", names: ["pt": "Gálatas", "en": "Galatians", "es": "Gálatas"], abbr: ["pt": "Gl", "en": "Gal", "es": "Gá"]),
        Entry(id: "EPH", names: ["pt": "Efésios", "en": "Ephesians", "es": "Efesios"], abbr: ["pt": "Ef", "en": "Eph", "es": "Ef"]),
        Entry(id: "PHP", names: ["pt": "Filipenses", "en": "Philippians", "es": "Filipenses"], abbr: ["pt": "Fp", "en": "Phil", "es": "Fil"]),
        Entry(id: "COL", names: ["pt": "Colossenses", "en": "Colossians", "es": "Colosenses"], abbr: ["pt": "Cl", "en": "Col", "es": "Col"]),
        Entry(id: "1TH", names: ["pt": "1 Tessalonicenses", "en": "1 Thessalonians", "es": "1 Tesalonicenses"], abbr: ["pt": "1Ts", "en": "1 Thess", "es": "1Ts"]),
        Entry(id: "2TH", names: ["pt": "2 Tessalonicenses", "en": "2 Thessalonians", "es": "2 Tesalonicenses"], abbr: ["pt": "2Ts", "en": "2 Thess", "es": "2Ts"]),
        Entry(id: "1TI", names: ["pt": "1 Timóteo", "en": "1 Timothy", "es": "1 Timoteo"], abbr: ["pt": "1Tm", "en": "1 Tim", "es": "1Ti"]),
        Entry(id: "2TI", names: ["pt": "2 Timóteo", "en": "2 Timothy", "es": "2 Timoteo"], abbr: ["pt": "2Tm", "en": "2 Tim", "es": "2Ti"]),
        Entry(id: "TIT", names: ["pt": "Tito", "en": "Titus", "es": "Tito"], abbr: ["pt": "Tt", "en": "Titus", "es": "Tit"]),
        Entry(id: "PHM", names: ["pt": "Filemom", "en": "Philemon", "es": "Filemón"], abbr: ["pt": "Fm", "en": "Phlm", "es": "Flm"]),
        Entry(id: "HEB", names: ["pt": "Hebreus", "en": "Hebrews", "es": "Hebreos"], abbr: ["pt": "Hb", "en": "Heb", "es": "He"]),
        Entry(id: "JAS", names: ["pt": "Tiago", "en": "James", "es": "Santiago"], abbr: ["pt": "Tg", "en": "Jas", "es": "Stg"]),
        Entry(id: "1PE", names: ["pt": "1 Pedro", "en": "1 Peter", "es": "1 Pedro"], abbr: ["pt": "1Pe", "en": "1 Pet", "es": "1P"]),
        Entry(id: "2PE", names: ["pt": "2 Pedro", "en": "2 Peter", "es": "2 Pedro"], abbr: ["pt": "2Pe", "en": "2 Pet", "es": "2P"]),
        Entry(id: "1JN", names: ["pt": "1 João", "en": "1 John", "es": "1 Juan"], abbr: ["pt": "1Jo", "en": "1 John", "es": "1Jn"]),
        Entry(id: "2JN", names: ["pt": "2 João", "en": "2 John", "es": "2 Juan"], abbr: ["pt": "2Jo", "en": "2 John", "es": "2Jn"]),
        Entry(id: "3JN", names: ["pt": "3 João", "en": "3 John", "es": "3 Juan"], abbr: ["pt": "3Jo", "en": "3 John", "es": "3Jn"]),
        Entry(id: "JUD", names: ["pt": "Judas", "en": "Jude", "es": "Judas"], abbr: ["pt": "Jd", "en": "Jude", "es": "Jds"]),
        Entry(id: "REV", names: ["pt": "Apocalipse", "en": "Revelation", "es": "Apocalipsis"], abbr: ["pt": "Ap", "en": "Rev", "es": "Ap"]),
    ]

    private static let byId: [String: Entry] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id.uppercased(), $0) })
    }()

    static func entry(for bookId: String) -> Entry? {
        byId[bookId.uppercased()]
    }

    /// Resolves reference display locale: prefs `copyLocale`, else iPhone/app language.
    static func referenceLocale() -> String {
        let stored = UserDefaults.standard.string(forKey: ReferencePrefs.copyLocaleKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let stored, !stored.isEmpty {
            if stored.hasPrefix("en") { return "en" }
            if stored.hasPrefix("es") { return "es" }
            if stored.hasPrefix("pt") { return "pt" }
        }
        return AppLocale.apiCode
    }

    static func bookLabel(bookId: String, locale: String? = nil, style: String? = nil) -> String {
        let loc = locale ?? referenceLocale()
        let cite = style ?? ReferencePrefs.citeBook
        guard let entry = entry(for: bookId) else { return bookId }
        if cite == "abbr" {
            return entry.abbr[loc] ?? entry.abbr["en"] ?? bookId
        }
        return entry.names[loc] ?? entry.names["en"] ?? bookId
    }

    static func formatPassage(
        bookId: String,
        chapter: Int,
        verseStart: Int?,
        verseEnd: Int?,
        locale: String? = nil
    ) -> String {
        let label = bookLabel(bookId: bookId, locale: locale)
        let sep: String = {
            switch ReferencePrefs.citeSep {
            case "dot": return "."
            case "comma": return ","
            default: return ":"
            }
        }()
        guard let verseStart else { return "\(label) \(chapter)" }
        if let verseEnd, verseEnd != verseStart {
            let lo = min(verseStart, verseEnd)
            let hi = max(verseStart, verseEnd)
            return "\(label) \(chapter)\(sep)\(lo)–\(hi)"
        }
        return "\(label) \(chapter)\(sep)\(verseStart)"
    }
}

/// Cached reference-language prefs (UserDefaults), synced from `PrefsDTO`.
enum ReferencePrefs {
    static let copyLocaleKey = "v2n.copyLocale"
    static let citeBookKey = "v2n.citeBook"
    static let citeSepKey = "v2n.citeSep"

    static var copyLocale: String {
        get {
            let stored = UserDefaults.standard.string(forKey: copyLocaleKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let stored, !stored.isEmpty { return stored }
            return AppLocale.apiCode
        }
        set { UserDefaults.standard.set(newValue, forKey: copyLocaleKey) }
    }

    static var citeBook: String {
        get { UserDefaults.standard.string(forKey: citeBookKey) ?? "name" }
        set { UserDefaults.standard.set(newValue, forKey: citeBookKey) }
    }

    static var citeSep: String {
        get { UserDefaults.standard.string(forKey: citeSepKey) ?? "colon" }
        set { UserDefaults.standard.set(newValue, forKey: citeSepKey) }
    }

    static func sync(from prefs: NativeAPIClient.PrefsDTO) {
        copyLocale = prefs.copyLocale
        citeBook = prefs.citeBook
        citeSep = prefs.citeSep
    }
}
