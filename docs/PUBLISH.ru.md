# Как загрузить проект в GitHub

1. Распакуйте архив `e-cloudfiles-github.zip` на компьютере.
2. Войдите в GitHub под `dagmagnat`, откройте https://github.com/new.
3. В поле Repository name укажите **e-cloudfiles**. Выберите **Public**, чтобы
   команда скачивания установщика работала без токена GitHub.
4. Создайте пустой репозиторий кнопкой Create repository. README, .gitignore
   и лицензию на этом шаге добавлять не нужно: файлы проекта уже подготовлены.
5. На странице нового репозитория выберите **uploading an existing file**.
   Если репозиторий уже содержит файлы, используйте **Add file → Upload files**
   и предварительно убедитесь, что не перезаписываете другой проект.
6. Откройте распакованную папку `e-cloudfiles` и перетащите **её содержимое**
   в окно загрузки, включая `.github`, `.gitattributes` и `.gitignore`.
   Не загружайте ZIP и не вкладывайте проект в дополнительную папку.
7. Нажмите Commit changes. Ветка должна называться **main**.

В корне репозитория должны отображаться:

```text
.github/workflows/check.yml
.gitattributes
.gitignore
README.md
install-e-cloudfiles.sh
docs/INSTALL.ru.md
docs/PUBLISH.ru.md
```

Откройте вкладку **Actions**, найдите `Check installer` и дождитесь зелёного
результата. Это проверка конфигурации, а не установка на VPS.

Затем выполните шаги установки из [README](../README.md).

Команда в README ожидает точный адрес:
`https://raw.githubusercontent.com/dagmagnat/e-cloudfiles/main/install-e-cloudfiles.sh`.
При другом имени репозитория или ветки этот адрес нужно изменить.

Пароли появятся только после запуска на VPS. Не загружайте в GitHub каталог
`/opt/e-cloudfiles`, файл `credentials.txt`, `.env` или резервную копию сервера.
