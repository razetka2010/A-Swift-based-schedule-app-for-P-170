import Foundation

// MARK: - Config

enum AppConfig {
    /// Группа, для которой показывается расписание.
    static let group = "П-170"
}

// MARK: - Date helpers

enum DateFormatting {
    static let dayKey: DateFormatter = make("yyyy-MM-dd")
    static let apiDate: DateFormatter = make("dd-MM-yyyy")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    static func parseISO(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: value) { return d }
        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Schedule

struct ScheduleResponse: Decodable {
    let group: String?
    let status: String?
    let updatedAt: String?
    let schedule: [Lesson]
    let note: String?

    enum CodingKeys: String, CodingKey { case group, status, updatedAt, schedule, note }

    // Сервер может вернуть только `note` (например, «расписание недоступно») без массива занятий.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try? c.decodeIfPresent(String.self, forKey: .group)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        schedule = (try? c.decodeIfPresent([Lesson].self, forKey: .schedule)) ?? []
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct Lesson: Decodable, Identifiable, Hashable {
    let dateKey: String
    let time: String
    let lesson: String
    let teacher: String
    let room: String

    var id: String { "\(dateKey)|\(time)|\(lesson)|\(teacher)|\(room)" }

    enum CodingKeys: String, CodingKey { case dateKey, time, lesson, teacher, room }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        lesson = try c.decodeIfPresent(String.self, forKey: .lesson) ?? ""
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        room = try c.decodeIfPresent(String.self, forKey: .room) ?? ""
    }

    /// Название без типа занятия («Математика · Лекция» → «Математика»)
    var title: String { lesson.components(separatedBy: " · ").first ?? lesson }

    var kind: String? {
        let parts = lesson.components(separatedBy: " · ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
    }

    var date: Date? { DateFormatting.dayKey.date(from: dateKey) }

    /// Части времени. Принимает «–», «—», «−» и обычный дефис между началом и концом.
    private var timeParts: [String] {
        time.components(separatedBy: CharacterSet(charactersIn: "–—−-"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var startText: String { timeParts.first ?? time }
    var endText: String? {
        let parts = timeParts
        return parts.count == 2 ? parts[1] : nil
    }

    /// Минуты от полуночи для сортировки («9:00» раньше «10:00»).
    var startMinutes: Int {
        let hm = startText.split(separator: ":")
        guard hm.count >= 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return Int.max }
        return h * 60 + m
    }

    /// Начало и конец занятия; nil, если время не в формате «ЧЧ:ММ–ЧЧ:ММ»
    var interval: DateInterval? {
        let parts = timeParts
        guard parts.count == 2, let day = date,
              let start = Self.combine(day, parts[0]),
              let end = Self.combine(day, parts[1]),
              end >= start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func combine(_ day: Date, _ clock: String) -> Date? {
        let hm = clock.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard hm.count >= 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    var symbol: String { SubjectIcon.symbol(for: title) }
}

enum SubjectIcon {
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("информат", "desktopcomputer"), ("программ", "chevron.left.forwardslash.chevron.right"),
            ("математ", "function"), ("алгебр", "function"), ("физик", "atom"),
            ("истори", "clock.arrow.circlepath"), ("биолог", "leaf"), ("хими", "testtube.2"),
            ("географ", "globe.europe.africa"), ("русск", "text.book.closed"),
            ("литератур", "books.vertical"), ("англ", "character.bubble"),
            ("общество", "person.3"), ("обзр", "cross.case"), ("безопасн", "cross.case"), ("физкульт", "figure.run"),
            ("специальност", "graduationcap")
        ]
        return table.first { n.contains($0.0) }?.1 ?? "book"
    }
}

// MARK: - Notes

struct SubjectsResponse: Decodable { let subjects: [String] }

struct StudyNote: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String
    let author: String
    let content: String   // HTML, уже очищенный сервером
    let createdAt: String

    var date: Date? { DateFormatting.parseISO(createdAt) }

    enum CodingKeys: String, CodingKey { case id, subject, author, content, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id может прийти строкой или числом
        if let str = try? c.decode(String.self, forKey: .id) {
            id = str
        } else if let num = try? c.decode(Int.self, forKey: .id) {
            id = String(num)
        } else {
            id = UUID().uuidString
        }
        subject = (try? c.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? "Без имени"
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}

struct NotesPage: Decodable {
    let notes: [StudyNote]
    let hasMore: Bool
    let nextOffset: Int
    let googleDocUrl: String?

    enum CodingKeys: String, CodingKey { case notes, hasMore, nextOffset, googleDocUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = (try? c.decodeIfPresent([StudyNote].self, forKey: .notes)) ?? []
        hasMore = (try? c.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? false
        nextOffset = (try? c.decodeIfPresent(Int.self, forKey: .nextOffset)) ?? notes.count
        googleDocUrl = try? c.decodeIfPresent(String.self, forKey: .googleDocUrl)
    }
}

struct CreateNoteResponse: Decodable { let note: StudyNote }

struct MaintenanceSettings: Decodable {
    let maintenanceEnabled: Bool
    let maintenanceMessage: String

    enum CodingKeys: String, CodingKey { case maintenanceEnabled, maintenanceMessage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maintenanceEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .maintenanceEnabled)) ?? false
        maintenanceMessage = (try? c.decodeIfPresent(String.self, forKey: .maintenanceMessage))
            ?? "Идут технические работы."
    }
}

// MARK: - HTML → текст

extension String {
    /// Простое преобразование HTML конспекта в обычный текст (таблицы и схемы — текстом).
    var htmlToPlainText: String {
        var s = self
        let rules: [(String, String)] = [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|li|tr|pre|h[1-6]|table)>", "\n"),
            ("(?i)</t[dh]>", "  |  "),
            ("(?i)<li[^>]*>", "• "),
            ("<[^>]+>", "")
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (e, r) in entities { s = s.replacingOccurrences(of: e, with: r) }
        // &#1234; и &#x1F600;
        while let range = s.range(of: "&#(x[0-9A-Fa-f]+|[0-9]+);", options: .regularExpression) {
            let body = s[range].dropFirst(2).dropLast()
            let code = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            let char = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
            s.replaceSubrange(range, with: char)
        }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Обычный текст → HTML, который принимает POST /api/notes
    var plainTextToNoteHTML: String {
        let escaped = self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
            .joined()
    }
}
