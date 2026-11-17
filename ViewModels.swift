import Foundation
import SwiftUI
import Combine

private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

// MARK: - Schedule

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var lessonsByDate: [String: [Lesson]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var serverNote: String?
    @Published var weekStart: Date
    @Published var selectedDate: Date

    let calendar: Calendar

    // Отслеживаем запросы отдельно: главный экран загружает 28 дней,
    // а экран расписания — 7 дней. Они могут выполняться одновременно.
    private var activeRequests: Set<UUID> = []
    private var requestSequence = 0
    private var latestRequestByRange: [String: Int] = [:]
    private var daySequence: [String: Int] = [:]

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // понедельник
        calendar = cal
        let today = Date()
        selectedDate = today
        weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
    }

    var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    func lessons(on date: Date) -> [Lesson] {
        lessonsByDate[DateFormatting.dayKey.string(from: date)] ?? []
    }

    func hasLoadedCurrentWeek() -> Bool {
        weekDays.contains { !lessons(on: $0).isEmpty }
    }

    /// Ближайшее занятие: идущее сейчас или первое будущее
    func upcomingLesson(now: Date = Date()) -> Lesson? {
        lessonsByDate.keys.sorted()
            .flatMap { lessonsByDate[$0] ?? [] }
            .first { ($0.interval?.end ?? .distantPast) > now }
    }

    func shiftWeek(by weeks: Int) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) else { return }
        weekStart = next
        let today = Date()
        selectedDate = weekDays.contains { calendar.isDate($0, inSameDayAs: today) } ? today : next
    }

    func goToToday() {
        let today = Date()
        weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        selectedDate = today
    }

    /// Главная: текущая неделя + 3 следующие (28 дней)
    func refresh(group: String) async {
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        await fetch(group: group, from: start, days: 28)
    }

    /// Экран расписания: выбранная неделя
    func loadWeek(group: String) async {
        await fetch(group: group, from: weekStart, days: 7)
    }

    private func fetch(group: String, from: Date, days: Int) async {
        let requestID = UUID()
        requestSequence += 1
        let sequence = requestSequence
        let rangeKey = "\(group)|\(DateFormatting.dayKey.string(from: from))|\(days)"

        activeRequests.insert(requestID)
        latestRequestByRange[rangeKey] = sequence
        isLoading = true
        errorMessage = nil
        defer {
            activeRequests.remove(requestID)
            isLoading = !activeRequests.isEmpty
        }

        do {
            let response = try await APIService.shared.fetchSchedule(group: group, from: from, days: days)

            // Если для точно такого же диапазона уже стартовал более новый
            // запрос, игнорируем запоздавший ответ.
            guard latestRequestByRange[rangeKey] == sequence else { return }

            var map = lessonsByDate
            var updatedKeys = Set<String>()

            // Сначала очищаем запрошенные дни, включая дни без занятий.
            for offset in 0..<max(days, 0) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
                let key = DateFormatting.dayKey.string(from: day)
                if sequence >= (daySequence[key] ?? 0) {
                    map[key] = []
                    daySequence[key] = sequence
                    updatedKeys.insert(key)
                }
            }

            // Добавляем только занятия, для даты которых этот ответ всё ещё
            // является самым новым из применённых ответов.
            // Дубликаты (одинаковые id) ломают ForEach, поэтому отбрасываем повторы.
            var seen = Set<String>()
            for lesson in response.schedule where seen.insert(lesson.id).inserted {
                let key = lesson.dateKey
                if sequence >= (daySequence[key] ?? 0) {
                    if !updatedKeys.contains(key) {
                        map[key] = []
                        daySequence[key] = sequence
                        updatedKeys.insert(key)
                    }
                    map[key, default: []].append(lesson)
                }
            }

            for key in updatedKeys {
                map[key]?.sort { ($0.startMinutes, $0.time) < ($1.startMinutes, $1.time) }
            }
            lessonsByDate = map
            if sequence == requestSequence {
                serverNote = response.note
                errorMessage = nil
            }
        } catch {
            if isCancellation(error) { return }
            // Не показываем ошибку от уже устаревшего запроса.
            guard sequence == requestSequence else { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notes

@MainActor
final class SubjectsViewModel: ObservableObject {
    @Published private(set) var subjects: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            subjects = try await APIService.shared.fetchSubjects()
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class SubjectNotesViewModel: ObservableObject {
    let subject: String
    @Published private(set) var notes: [StudyNote] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var googleDocURL: URL?

    private var nextOffset = 0
    private var currentSearch = ""

    init(subject: String) { self.subject = subject }

    func reload(search: String) async {
        currentSearch = search
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIService.shared.fetchNotes(subject: subject, search: search, offset: 0)
            notes = page.notes
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            googleDocURL = page.googleDocUrl.flatMap(URL.init(string:))
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await APIService.shared.fetchNotes(
                subject: subject, search: currentSearch, offset: nextOffset
            )
            notes.append(contentsOf: page.notes)
            hasMore = page.hasMore
            nextOffset = page.nextOffset
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}
