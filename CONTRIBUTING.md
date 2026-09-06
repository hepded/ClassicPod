# Разработка ClassicPod

Нужны macOS, Swift 6 и macOS SDK. Полный Xcode необходим для XCTest. Внешних Swift Package-зависимостей нет.

```sh
swift build
bash scripts/check.sh
bash scripts/build-app.sh
```

`check.sh` включает core assertions, HTTP/PKCE/loopback, временную WAV-библиотеку и рендер SceneKit. Запускайте его в графической сессии Mac; отсутствие GPU/WindowServer в headless-среде не является проверкой сцены. Тесты не требуют Spotify-аккаунта и не отправляют команды реальному Spotify.

CI выполняет `swift test`, Release-сборку и проверку ad-hoc подписи. Он не выполняет живую OAuth/Spotify-проверку, не проверяет интерфейс и не публикует бинарники. Workflow подготовлен, но до первого запуска на GitHub не считается проверенным. Образ runner: [официальный macos-15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

## Границы архитектуры

- Состояние интерфейса — MainActor; колесо и arcball — PodCore.
- SceneKit не обращается к аудио и сети напрямую.
- Изменяемая SpriteKit-сцена не передаётся одновременно двум renderer; экран получает готовые изображения.
- Одна команда — один транспорт. Не открывайте Spotify URI через NSWorkspace, не прячьте Spotify и не возвращайте фокус принудительно.
- Не повторяйте Next/Previous после неоднозначного timeout; перечитайте состояние.

Добавляйте небольшие тестируемые изменения. Не включайте музыку, токены, пользовательские JSON/bookmarks, внешние модели с неясной лицензией или сгенерированные сборки. Перед отправкой смотрите полный diff, включая новые файлы. Вклад должен быть совместим с MIT-лицензией проекта.
