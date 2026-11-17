import Foundation

enum APIError: LocalizedError {
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .server(let message), .network(let message): return message
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
    let note: String?
}

private struct NewNoteBody: Encodable {
    let subject: String
    let author: String
    let content: String
}

final class APIService {
    static let shared = APIService()

    /// Адрес деплоя на Vercel (тот же, что у сайта).
    let baseURL = URL(string: "https://schedule-for-programmers.vercel.app")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData   // расписание всегда свежее
        return URLSession(configuration: config)
    }()

    // MARK: Core

    private func send<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.network("Неверный адрес сервера.") }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.network("Неверный адрес сервера.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw APIError.network(error.code == .timedOut
                ? "Сервер долго не отвечает. Попробуй ещё раз."
                : "Нет связи с сервером. Проверь интернет.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Сервер вернул неожиданный ответ.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw APIError.server(body?.error ?? body?.note ?? "Ошибка сервера (HTTP \(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server("Не удалось разобрать ответ сервера.")
        }
    }

    // MARK: Schedule

    /// Загружает `days` дней (не больше 31), начиная с `from`.
    func fetchSchedule(group: String, from: Date, days: Int) async throws -> ScheduleResponse {
        let end = Calendar.current.date(byAdding: .day, value: max(days, 1) - 1, to: from) ?? from
        return try await send(
            ScheduleResponse.self,
            path: "api/schedule",
            query: [
                URLQueryItem(name: "group", value: group),
                URLQueryItem(name: "datebegin", value: DateFormatting.apiDate.string(from: from)),
                URLQueryItem(name: "dateend", value: DateFormatting.apiDate.string(from: end))
            ]
        )
    }

    func fetchMaintenance() async throws -> MaintenanceSettings {
        try await send(MaintenanceSettings.self, path: "api/admin-settings")
    }

    // MARK: Notes

    func fetchSubjects() async throws -> [String] {
        try await send(SubjectsResponse.self, path: "api/notes/subjects").subjects
    }

    func fetchNotes(subject: String, search: String, offset: Int, limit: Int = 20) async throws -> NotesPage {
        var query = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { query.append(URLQueryItem(name: "search", value: trimmed)) }
        return try await send(NotesPage.self, path: "api/notes", query: query)
    }

    func createNote(subject: String, author: String, text: String) async throws -> StudyNote {
        let body = try JSONEncoder().encode(
            NewNoteBody(subject: subject, author: author, content: text.plainTextToNoteHTML)
        )
        return try await send(CreateNoteResponse.self, path: "api/notes", method: "POST", body: body).note
    }
}
