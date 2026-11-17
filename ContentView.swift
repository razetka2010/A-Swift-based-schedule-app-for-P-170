import SwiftUI
import UIKit

// MARK: - Main App

struct ContentView: View {
    @StateObject private var schedule = ScheduleViewModel()
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage("appLanguage") private var appLanguage = "ru"

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house") }

            ScheduleView()
                .tabItem { Label("Расписание", systemImage: "calendar") }

            NotesView()
                .tabItem { Label("Конспекты", systemImage: "book.closed") }

            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
        .tint(.blue)
        .environmentObject(schedule)
        .environment(\.locale, Locale(identifier: appLanguage))
        .preferredColorScheme(
            appAppearance == "light" ? .light :
            appAppearance == "dark" ? .dark : nil
        )
    }
}

// MARK: - Colors

extension Color {
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let appBlue = Color.blue
    static let appCard = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Shared components

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Повторить", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MaintenanceBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "wrench.and.screwdriver")
            .font(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct EmptyCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var schedule: ScheduleViewModel
    @Environment(\.locale) private var locale
    private let group = AppConfig.group
    @State private var maintenance: MaintenanceSettings?

    private var todayLessons: [Lesson] { schedule.lessons(on: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let maintenance, maintenance.maintenanceEnabled {
                        MaintenanceBanner(text: maintenance.maintenanceMessage)
                    }

                    if let message = schedule.errorMessage, schedule.lessonsByDate.isEmpty {
                        ErrorCard(message: message) { Task { await schedule.refresh(group: group) } }
                    } else if schedule.isLoading && schedule.lessonsByDate.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        nextLesson
                        todaySection
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await schedule.refresh(group: group) }
            .task(id: group) {
                await schedule.refresh(group: group)
                maintenance = try? await APIService.shared.fetchMaintenance()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide)).capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Привет! 👋")
                .font(.largeTitle.bold())
            Text("Группа \(group)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var nextLesson: some View {
        if let lesson = schedule.upcomingLesson() {
            NextLessonCard(lesson: lesson)
        } else {
            EmptyCard(text: "Ближайших занятий в расписании нет")
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Сегодня").font(.title2.bold())
                Spacer()
                Text(lessonsCountText(todayLessons.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if todayLessons.isEmpty {
                EmptyCard(text: "Сегодня занятий нет 🎉")
            } else {
                LessonList(lessons: todayLessons)
            }
        }
    }

    private func lessonsCountText(_ n: Int) -> String {
        if locale.language.languageCode?.identifier != "ru" {
            return n == 1 ? "\(n) lesson" : "\(n) lessons"
        }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) занятие" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) занятия" }
        return "\(n) занятий"
    }
}

struct NextLessonCard: View {
    @Environment(\.locale) private var locale
    let lesson: Lesson

    private var isOngoing: Bool {
        guard let interval = lesson.interval else { return false }
        return interval.start <= Date() && Date() < interval.end
    }

    private var dayLabel: String? {
        guard let date = lesson.date, !Calendar.current.isDateInToday(date) else { return nil }
        return date.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide)).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isOngoing ? "ИДЁТ СЕЙЧАС" : "СЛЕДУЮЩЕЕ ЗАНЯТИЕ")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Image(systemName: "clock").foregroundStyle(.white.opacity(0.8))
            }

            Text(lesson.title)
                .font(.title.bold())
                .foregroundStyle(.white)

            if let dayLabel {
                Text(dayLabel).font(.subheadline).foregroundStyle(.white.opacity(0.9))
            }

            HStack {
                Label(lesson.time, systemImage: "clock")
                Spacer()
                if !lesson.room.isEmpty { Label(lesson.room, systemImage: "mappin") }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))

            if !lesson.teacher.isEmpty {
                Label(lesson.teacher, systemImage: "person")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let interval = lesson.interval, interval.start > Date() {
                (Text("Начало через ") + Text(durationText(until: interval.start)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.blue, Color(red: 0.25, green: 0.48, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func durationText(until date: Date) -> String {
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let isRussian = locale.language.languageCode?.identifier == "ru"

        if hours == 0 {
            return isRussian ? "\(minutes) мин" : "\(minutes) min"
        }
        if minutes == 0 {
            return isRussian ? "\(hours) ч" : "\(hours) hrs"
        }
        return isRussian ? "\(hours) ч, \(minutes) мин" : "\(hours) hrs, \(minutes) min"
    }
}

// MARK: - Lessons

struct LessonList: View {
    let lessons: [Lesson]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { item in
                let index = item.offset
                let lesson = item.element
                LessonRow(lesson: lesson)
                if index != lessons.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct LessonRow: View {
    @Environment(\.locale) private var locale
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.startText)
                    .font(.subheadline.monospacedDigit().bold())
                if let end = lesson.endText {
                    Text(end)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, alignment: .leading)

            Image(systemName: lesson.symbol)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title)
                    .font(.system(.body, weight: .semibold))
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }

    private var details: String {
        let roomLabel = locale.language.languageCode?.identifier == "ru" ? "ауд." : "room"
        return [lesson.kind, lesson.room.isEmpty ? nil : "\(roomLabel) \(lesson.room)", lesson.teacher.isEmpty ? nil : lesson.teacher]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @EnvironmentObject private var schedule: ScheduleViewModel
    @Environment(\.locale) private var locale
    private let group = AppConfig.group

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Расписание").font(.largeTitle.bold())

                    weekHeader
                    dayChips

                    Text(selectedDayTitle).font(.title2.bold())

                    content
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .refreshable { await schedule.loadWeek(group: group) }
            .task(id: "\(schedule.weekStart.timeIntervalSince1970)-\(group)") {
                await schedule.loadWeek(group: group)
            }
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { schedule.shiftWeek(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(weekRangeText).font(.headline)
                Button("Сегодня") { schedule.goToToday() }
                    .font(.caption)
            }
            Spacer()
            Button { schedule.shiftWeek(by: 1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var weekRangeText: String {
        guard let first = schedule.weekDays.first, let last = schedule.weekDays.last else { return "" }
        let style = Date.FormatStyle().locale(locale).day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private var dayChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(schedule.weekDays.enumerated()), id: \.element) { item in
                let day = item.element
                let isSelected = schedule.calendar.isDate(day, inSameDayAs: schedule.selectedDate)
                let isToday = schedule.calendar.isDateInToday(day)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { schedule.selectedDate = day }
                } label: {
                    VStack(spacing: 8) {
                        Text(dayName(for: day)).font(.caption.bold())
                        Text("\(schedule.calendar.component(.day, from: day))").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.blue : Color.primary))
                    .background(isSelected ? Color.blue : Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedDayTitle: String {
        schedule.selectedDate.formatted(.dateTime.locale(locale).weekday(.wide).day().month(.wide)).capitalized
    }

    private func dayName(for day: Date) -> String {
        day.formatted(.dateTime.locale(locale).weekday(.abbreviated)).uppercased()
    }

    @ViewBuilder
    private var content: some View {
        let lessons = schedule.lessons(on: schedule.selectedDate)
        if let message = schedule.errorMessage, lessons.isEmpty {
            ErrorCard(message: message) { Task { await schedule.loadWeek(group: group) } }
        } else if schedule.isLoading && lessons.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
        } else if lessons.isEmpty {
            EmptyCard(text: schedule.serverNote ?? "В этот день занятий нет")
        } else {
            LessonList(lessons: lessons)
        }
    }
}

// MARK: - Notes

struct NotesView: View {
    @StateObject private var vm = SubjectsViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let message = vm.errorMessage, vm.subjects.isEmpty {
                    ErrorCard(message: message) { Task { await vm.load() } }
                        .listRowBackground(Color.clear)
                }
                ForEach(vm.subjects, id: \.self) { subject in
                    NavigationLink(value: subject) {
                        HStack(spacing: 14) {
                            Image(systemName: SubjectIcon.symbol(for: subject))
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(subject).font(.headline)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .overlay { if vm.isLoading && vm.subjects.isEmpty { ProgressView() } }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Конспекты")
            .navigationDestination(for: String.self) { SubjectNotesView(subject: $0) }
            .refreshable { await vm.load() }
            .task { if vm.subjects.isEmpty { await vm.load() } }
        }
    }
}

struct SubjectNotesView: View {
    @Environment(\.locale) private var locale
    @StateObject private var vm: SubjectNotesViewModel
    @State private var search = ""
    @State private var showingNew = false

    init(subject: String) {
        _vm = StateObject(wrappedValue: SubjectNotesViewModel(subject: subject))
    }

    var body: some View {
        List {
            if let message = vm.errorMessage, vm.notes.isEmpty {
                ErrorCard(message: message) { Task { await vm.reload(search: search) } }
                    .listRowBackground(Color.clear)
            } else if vm.notes.isEmpty && !vm.isLoading {
                EmptyCard(text: search.isEmpty ? "Пока нет конспектов. Опубликуй первый!" : "Ничего не найдено")
                    .listRowBackground(Color.clear)
            }

            ForEach(vm.notes) { note in
                NavigationLink {
                    NoteDetailView(note: note)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(note.author).font(.headline)
                            Spacer()
                            if let date = note.date {
                                Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(note.content.htmlToPlainText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if note.id == vm.notes.last?.id { Task { await vm.loadMore() } }
                }
            }

            if vm.hasMore {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .overlay { if vm.isLoading && vm.notes.isEmpty { ProgressView() } }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(vm.subject)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Поиск по автору и тексту")
        .task(id: search) {
            if !search.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            if Task.isCancelled { return }
            await vm.reload(search: search)
        }
        .refreshable { await vm.reload(search: search) }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let url = vm.googleDocURL {
                    Link(destination: url) { Image(systemName: "doc.text") }
                }
                Button { showingNew = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showingNew) {
            NewNoteView(subject: vm.subject) {
                Task { await vm.reload(search: search) }
            }
        }
    }
}

struct NoteDetailView: View {
    @Environment(\.locale) private var locale
    let note: StudyNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(note.author, systemImage: "person.crop.circle")
                    Spacer()
                    if let date = note.date {
                        Text(date.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(locale)))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(note.content.htmlToPlainText)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationTitle(note.subject)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewNoteView: View {
    let subject: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("authorName") private var author = ""
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        author.trimmingCharacters(in: .whitespaces).count >= 2
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= 30000
            && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Автор") {
                    TextField("Твоё имя", text: $author)
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 220)
                } header: {
                    Text("Конспект — \(subject)")
                } footer: {
                    Text("После публикации студент не может изменить или удалить конспект — это может только администратор.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Новый конспект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Отправка…" : "Опубликовать") { Task { await send() } }
                        .disabled(!canSend)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await APIService.shared.createNote(
                subject: subject,
                author: author.trimmingCharacters(in: .whitespaces),
                text: text
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Profile

struct ProfileView: View {
    private let group = AppConfig.group

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(.blue)
                        Text("Студент")
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                }

                Section("Настройки") {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        Label("Язык", systemImage: "globe")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Внешний вид", systemImage: "paintbrush")
                    }

                    NavigationLink {
                        AboutAppView()
                    } label: {
                        Label("О приложении", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Профиль")
        }
    }
}

// MARK: - Language settings

struct LanguageSettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = "ru"

    var body: some View {
        Form {
            Picker("Язык приложения", selection: $appLanguage) {
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }
        }
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance settings

struct AppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appAppearance = "system"

    var body: some View {
        Form {
            Section {
                appearanceOption("Системная", value: "system", symbol: "iphone")
                appearanceOption("Светлая", value: "light", symbol: "sun.max")
                appearanceOption("Тёмная", value: "dark", symbol: "moon")
            } header: {
                Text("Тема приложения")
            } footer: {
                Text("Выбранная тема сохраняется и применяется ко всему приложению.")
            }
        }
        .navigationTitle("Внешний вид")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceOption(_ title: String, value: String, symbol: String) -> some View {
        Button {
            appAppearance = value
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                if appAppearance == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - About

struct AboutAppView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 64, height: 64)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule")
                            .font(.title2.bold())
                        Text("Расписание учёбы и конспекты")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Информация") {
                LabeledContent("Версия", value: version)
                LabeledContent("Сборка", value: build)
            }

            Section {
                Text("Приложение помогает просматривать расписание занятий и делиться учебными конспектами.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("О приложении")
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
