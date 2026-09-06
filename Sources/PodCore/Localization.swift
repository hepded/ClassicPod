import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english = "en", russian = "ru"
    public static func resolved(_ selection: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        guard selection == .system else { return selection }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "ru" { return .russian }
            if code == "en" { return .english }
        }
        return .english
    }
}
public enum L10n {
    public static let preferenceKey = "interfaceLanguage"
    public static var selection: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }
    public static var language: AppLanguage { AppLanguage.resolved(selection, preferredLanguages: Locale.preferredLanguages) }
    public static func text(_ key: String, language: AppLanguage = language) -> String {
        language == .russian ? key : english[key] ?? key
    }
    public static func format(_ key: String, _ arguments: String..., language: AppLanguage = language) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
    public static let english: [String: String] = [
        "Инерция вращения": "Rotation Inertia",
        "Плавное затухание после отпускания. Отключается при уменьшении движения в macOS.": "Gentle coast after release. Disabled when Reduce Motion is enabled in macOS.",
        "Музыка": "Music",
        "Сейчас играет": "Now Playing",
        "Настройки": "Settings",
        "Исполнители": "Artists",
        "Альбомы": "Albums",
        "Треки": "Songs",
        "Импортировать…": "Import…",
        "Плейлисты": "Playlists",
        "Connect-устройства": "Connect Devices",
        "Локальный мост (может открыть окно)": "Legacy Bridge (may bring Spotify forward)",
        "Подключить аккаунт…": "Connect Account…",
        "Устройства": "Devices",
        "Остановка Spotify не подтверждена": "Spotify pause not confirmed",
        "Остановите Spotify вручную. Продолжайте только после остановки, иначе музыка может играть одновременно.": "Pause Spotify manually. Continue only after playback has stopped to avoid both sources playing at once.",
        "Отмена": "Cancel",
        "Я остановил Spotify": "I Paused Spotify",
        "Connect-устройство выбрано. Выберите трек или нажмите Play.": "Connect device selected. Choose a song or press Play.",
        "Spotify подключён": "Spotify connected",
        "MP3, M4A, FLAC, WAV — файлы останутся на исходном месте": "MP3, M4A, FLAC, WAV — files stay in their original location",
        "Импортировать музыку…": "Import Music…",
        "ClassicPod — Настройки и библиотека": "ClassicPod — Settings & Library",
        "Настройки и библиотека…": "Settings & Library…",
        "Вид спереди — Escape": "Front View — Escape",
        "Поверх окон": "Always on Top",
        "Выйти": "Quit",
        "Локальная музыка · Spotify Connect · Desktop Bridge": "Local Music · Spotify Connect · Desktop Bridge",
        "Щелчок колеса": "Wheel Click Sound",
        "Spotify Client ID (не secret)": "Spotify Client ID (not a secret)",
        "Переподключить": "Reconnect",
        "Авторизоваться": "Sign In",
        "Выйти из аккаунта": "Sign Out",
        "Управлять Spotify на этом Mac": "Legacy Bridge (may bring Spotify forward)",
        "Для Web API нужен Premium и собственное приложение в Spotify Dashboard. Мост требует открытый Spotify и разрешение Automation.": "Web API requires Premium and your own Spotify Dashboard app. The legacy bridge requires a running Spotify client and Automation permission.",
        "Найти файл…": "Locate File…",
        "Корпус: вращение 360° · Option-drag: переместить окно · Escape: вид спереди / назад · Колесо: меню · Space: Play/Pause": "Drag body: rotate 360° · Option-drag: move window · Escape: front / back · Wheel: menu · Space: Play/Pause",
        "Загрузка… Menu — отмена": "Loading… Menu to cancel",
        "Выберите музыку": "Choose Your Music",
        "ПЕРЕМОТКА · шаг 5 с": "SEEK · 5-second steps",
        "Пока пусто": "No Items",
        "Неизвестная версия библиотеки; индекс не изменён.": "Unknown library version; the index was not changed.",
        "Не локальный файл": "Not a local file",
        "Формат не воспроизводится AVFoundation": "This format cannot be played by AVFoundation",
        "Неизвестный исполнитель": "Unknown Artist",
        "Неизвестный альбом": "Unknown Album",
        "Очередь пуста": "The queue is empty",
        "Не удалось создать OAuth nonce": "Could not generate an OAuth nonce",
        "Авторизация уже выполняется": "Sign-in is already in progress",
        "Время авторизации истекло": "Sign-in timed out",
        "Авторизация отменена или отклонена Spotify": "Sign-in was cancelled or declined by Spotify",
        "Укажите Spotify Client ID в настройках": "Enter your Spotify Client ID in Settings",
        "Сначала подключите Spotify": "Connect your Spotify account first",
        "Spotify OAuth отклонил запрос. Проверьте Client ID, redirect URI и доступ аккаунта.": "Spotify OAuth rejected the request. Check your Client ID, redirect URI and account access.",
        "Spotify не вернул refresh token": "Spotify did not return a refresh token",
        "Выберите Connect-устройство в меню Spotify или запустите воспроизведение в Spotify вручную. Локальный мост автоматически не используется.": "Choose a Connect device in the Spotify menu or start Spotify playback manually. The legacy bridge is never used automatically.",
        "Остановка Spotify не подтверждена. Остановите его вручную и повторите смену источника.": "Spotify pause was not confirmed. Pause it manually and try switching sources again.",
        "Перемотка недоступна": "Seeking is unavailable",
        "Громкость регулируется на устройстве Spotify": "Adjust the volume on the Spotify device",
        "Spotify играет на другом устройстве. Выберите его в меню устройств.": "Spotify is playing on another device. Select it in the Devices menu.",
        "Недопустимый адрес Spotify API": "Invalid Spotify API URL",
        "Нет ответа Spotify": "No response from Spotify",
        "Spotify: доступ запрещён. Проверьте Premium, scopes, allowlist и ограничения Development Mode.": "Spotify: access denied. Check Premium, scopes, your allowlist and Development Mode restrictions.",
        "Spotify: нет доступного устройства или контента. Откройте клиент и выберите устройство.": "Spotify: no available device or content. Open the client and select a device.",
        "Spotify: авторизуйтесь повторно": "Spotify: sign in again",
        "Spotify вернул циклическую пагинацию": "Spotify returned a pagination loop",
        "Недопустимый ID плейлиста": "Invalid playlist ID",
        "Неверная позиция": "Invalid playback position",
        "Неверная громкость": "Invalid volume",
        "Неверный Spotify URI": "Invalid Spotify URI",
        "Разрешите Automation через «Spotify на этом Mac». Системные настройки → Конфиденциальность → Автоматизация.": "Allow Automation using the Legacy Bridge menu. System Settings → Privacy & Security → Automation.",
        "Spotify не ответил за 5 секунд. Команда не повторена; состояние будет перечитано.": "Spotify did not respond within 5 seconds. The command was not repeated; playback state will be checked.",
        "Откройте Spotify вручную. ClassicPod не запускает и не активирует его автоматически.": "Open Spotify manually. ClassicPod never launches or activates it automatically.",
        "ClassicPod — 3D музыкальный плеер": "ClassicPod — 3D Music Player",
        "Menu — назад": "Menu — Back",
        "Выбрать": "Select",
        "Следующий трек": "Next Track",
        "Предыдущий трек": "Previous Track",
        "Вниз": "Down",
        "Вверх": "Up",
        "Язык": "Language",
        "Системный": "System Default",
        "Библиотека: %@": "Library: %@",
        "Треков в библиотеке: %@": "Songs in library: %@",
        "Новый путь: %@": "Locate: %@",
        "Индекс защищён от перезаписи: %@": "The index is protected from overwriting: %@",
        "Файл перемещён: %@. Выберите новый путь в библиотеке.": "File moved: %@. Locate it in the library.",
        "Пропущен повреждённый файл: %@": "Skipped an invalid file: %@",
        "Spotify: повторите через %@ с": "Spotify: try again in %@ seconds",
        "Spotify ограничил частоту запросов: ожидание %@ с": "Spotify rate limit: wait %@ seconds",
        "Внешняя модель не загружена: %@. Используется встроенная модель.": "Could not load the external model: %@. Using the built-in model.",
        "Spotify Apple Events: ошибка %@": "Spotify Apple Events error: %@",
        "ГРОМКОСТЬ %@%% · Select: позиция": "VOLUME %@%% · Select: seek"
    ]
}
