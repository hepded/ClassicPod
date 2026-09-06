# Перед публикацией

Это инструкция, а не выполненная публикация. Репозиторий, remote, commit, tag и Release автоматически не создавались.

Что проверено перед упаковкой: [PUBLICATION_AUDIT.md](PUBLICATION_AUDIT.md).

## Контрольный список владельца

- [x] По выбору владельца добавлена лицензия MIT; прочитайте LICENSE перед публикацией.
- [ ] Просмотреть исходники, README, GIF и полный список файлов архива.
- [ ] Убедиться, что в Git нет токенов, личных данных, Application Support, Keychain, бинарников и чужой музыки.
- [ ] Если используется существующая история Git, отдельно проверить всю историю секрет-сканером; проверка текущих файлов её не заменяет.
- [ ] Создать пустой репозиторий с нужной видимостью в своём аккаунте. Название: ClassicPod; описание: Native macOS 3D music player with a click wheel, local audio and Spotify Connect.
- [ ] По желанию включить приватные сообщения об уязвимостях; не считать их включёнными заранее.
- [ ] После push проверить первый запуск Actions. Подготовленный CI ещё не запускался на GitHub.

Не загружайте общую рабочую папку разработки целиком. Используйте очищенный source-архив или только каталог проекта с проверенными исключениями. `.gitignore` не убирает уже отслеживаемые файлы.

Чтобы пересоздать архив исходников (Python 3, без сторонних пакетов):

```sh
python3 scripts/package-source.py ../ClassicPod-source.zip
```

Скрипт включает только выбранные каталоги и типы файлов, исключает сборки/историю и отклоняет symlinks в публикуемых каталогах. Это упаковщик, не секрет-сканер: содержимое исходников и изображений всё равно нужно проверять.

## Первый push — только после проверки

Распакуйте `ClassicPod-source.zip` и откройте в терминале **внутреннюю папку ClassicPod**, где лежит Package.swift. Не добавляйте сам ZIP в Git вместо исходников. Каталоги `.github` и `.gitignore` скрытые — они также нужны.

Из корня очищенного проекта выполните вручную:

```sh
git init
git add .
git diff --cached --stat
git diff --cached
```

Остановитесь и проверьте diff. Затем создайте первый commit, выберите имя основной ветки и добавьте **реальный URL своего репозитория**, выданный GitHub. Не копируйте выдуманные username/remote. Публикация не требует передавать токен GitHub в исходники проекта.

После проверки можно выполнить вручную:

```sh
git commit -m "Initial release: ClassicPod 0.3.0 beta"
git branch -M main
printf 'Repository URL (SSH or HTTPS, without a token): '
read -r REPOSITORY_URL
git remote add origin "$REPOSITORY_URL"
git push -u origin main
```

Эта последовательность предназначена для нового пустого репозитория. Если он уже содержит файлы/историю, сначала согласуйте историю; не используйте force push. В README уже есть English guide, иконка и GIF. Рекомендуемые topics: `macos`, `swift`, `swiftui`, `scenekit`, `music-player`, `spotify-connect`.

## Beta Release

Готовый текст: [RELEASE-0.3.0.md](RELEASE-0.3.0.md). Рекомендуемый тег: `v0.3.0`, заголовок: `ClassicPod 0.3.0 Beta`. Тег и Release пока не создавались. Прикрепляйте `ClassicPod-macOS-arm64.zip` и `SHA256SUMS.txt` как release assets, не в исходники. SHA256SUMS может также содержать checksum отдельно подготовленного source-архива; это не checksum автоматически генерируемого GitHub Source code ZIP.

1. На доверенном Mac: `bash scripts/check.sh`, затем `bash scripts/build-app.sh`.
2. Проверьте живое воспроизведение, подпись и актуальные ограничения в VALIDATION.md.
3. Создайте архив приложения:

```sh
ditto -c -k --sequesterRsrc --keepParent dist/ClassicPod.app dist/ClassicPod-macOS.zip
shasum -a 256 dist/ClassicPod-macOS.zip
```

4. После проверенного commit/tag создайте GitHub Release вручную, отметьте pre-release и приложите архив с checksum. Не заявляйте universal/Intel-поддержку для arm64-сборки.
5. Укажите: beta, macOS 14+ deployment target, фактически проверенная ОС/архитектура, ad-hoc подпись, отсутствие нотарификации, требования Spotify Premium/собственного Client ID. Не советуйте глобально отключать Gatekeeper.

Публикация исходников не расширяет доступ к Spotify API. Каждый пользователь настраивает собственный Client ID и доступ аккаунта согласно правилам Spotify; ваш личный аккаунт/токены в Release не включаются.
