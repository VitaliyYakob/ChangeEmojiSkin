-- Источник формата настроек: https://apple.stackexchange.com/questions/422741/are-emoji-color-preferences-stored-somewhere-on-macos

use framework "Foundation"

-- Запуск. В редакторе true - предпросмотр, false - запись.
-- Для osascript ChangeEmojiSkin.applescript доступны --preview, --apply и --restore "/путь/к/копии.plist".
-- Перед записью и откатом закройте панель эмодзи. Откат сохраняет историю использования.
property previewOnly : false

-- Общий тон. 0 - жёлтый, 1 - 🏻, 2 - 🏼, 3 - 🏽, 4 - 🏾, 5 - 🏿.
property defaultSkinTone : 1

-- Рукопожатие. Тоны слева направо, {0, 0} - жёлтый вариант.
property handshakeTones : {1, 1}

-- Портреты 👩 и 👨. "standard" - рисунок Apple.
-- "blond" также задаёт тон отдельному 👱‍♀️ или 👱‍♂️.
-- "brunette" допускает тона 1, 3-5 и жёлтый вариант 0.
property womanSkinTone : 2
property womanHair : "blond"
property manSkinTone : 1
property manHair : "brunette"

-- Исключения имеют приоритет над всеми настройками выше.
-- Один тон задаётся числом, два тона для пары - списком {слева, справа}. 0 сбрасывает тон.
-- Пример: {{"🤝", {2, 5}}, {"👩", 4}, {"☝️", 0}}. При повторе действует последняя запись.
property emojiOverrides : {{"💏", {5, 5}}, {"💑", {5, 5}}, {"🧔‍♀️", 5}}

-- Ключи настроек macOS.
property preferencesDomain : "com.apple.EmojiPreferences"
property defaultsKey : "EMFDefaultsKey"
property tonesKey : "EMFSkinToneBaseKeyPreferences"

-- Выбирает режим запуска: предпросмотр, запись или откат.
on run argv
	-- Редактор может передать сам скрипт вместо списка аргументов.
	if argv is missing value or argv = me or argv = {} then return my applySettings(previewOnly)
	if argv = {"--preview"} then return my applySettings(true)
	if argv = {"--apply"} then return my applySettings(false)
	if (count of argv) = 2 and item 1 of argv = "--restore" then return my restoreTonePreferences(item 2 of argv)
	error "Допустимые аргументы: --preview, --apply, --restore <файл.plist>"
end run

-- Собирает профиль с учётом исключений и показывает или сохраняет его.
on applySettings(isPreview)
	my validateTone(defaultSkinTone, "defaultSkinTone")
	if class of emojiOverrides is not list then error "emojiOverrides должен быть списком пар {\"эмодзи\", тон}."
	set catalog to my skinToneCatalog()
	set selectedVariants to current application's NSMutableDictionary's dictionary()
	repeat with entry in (catalog's allKeys() as list)
		set tile to contents of entry
		set options to (catalog's objectForKey:tile) as list
		(selectedVariants's setObject:(my selectTone(tile, options, defaultSkinTone)) forKey:tile)
	end repeat
	
	set handOptions to my catalogOptions(catalog, "🤝")
	selectedVariants's setObject:(my selectTone("🤝", handOptions, handshakeTones)) forKey:"🤝"
	my setPortraitTone(selectedVariants, catalog, "👩", "👱‍♀️", womanSkinTone, womanHair)
	my setPortraitTone(selectedVariants, catalog, "👨", "👱‍♂️", manSkinTone, manHair)
	
	set samples to {"👍", "🤝", "👩", "👱‍♀️", "👨", "👱‍♂️", "💏", "💑"}
	repeat with overrideEntry in emojiOverrides
		set entry to contents of overrideEntry
		if class of entry is not list or (count of entry) is not 2 then error "Запись в emojiOverrides должна иметь вид {\"эмодзи\", тон}."
		set tile to item 1 of entry
		if class of tile is not text then error "В emojiOverrides укажите эмодзи строкой."
		if tile is not "" and (catalog's objectForKey:tile) is missing value then
			set alternateTile to my alternatePresentation(tile)
			if (catalog's objectForKey:alternateTile) is not missing value then set tile to alternateTile
		end if
		set options to my catalogOptions(catalog, tile)
		(selectedVariants's setObject:(my selectTone(tile, options, item 2 of entry)) forKey:tile)
		if tile is not in samples then set end of samples to tile
	end repeat
	
	set report to ""
	repeat with entry in samples
		set tile to contents of entry
		set chosen to (selectedVariants's objectForKey:tile)
		if chosen is not missing value then set report to report & linefeed & tile & " → " & (chosen as text)
	end repeat
	if isPreview then return "Предпросмотр. Вариантов в профиле: " & (selectedVariants's |count|() as integer) & report
	
	set oldRoot to my readPreferencesRoot()
	set oldTones to my readDictionary(oldRoot, tonesKey)
	set updatedTones to oldTones's mutableCopy()
	repeat with entry in (selectedVariants's allKeys() as list)
		set tile to contents of entry
		set chosen to (selectedVariants's objectForKey:tile) as text
		set storageKeys to {tile}
		-- Компактная панель также ищет ☝ и похожие значки без селектора U+FE0F.
		set codePoints to (id of tile) as list
		if (count of codePoints) > 1 and item 2 of codePoints = 65039 then
			set plainTile to my alternatePresentation(tile)
			if (catalog's objectForKey:plainTile) is missing value then set end of storageKeys to plainTile
		end if
		-- Для 💏 и 💑 панели нужны оба ключа.
		if tile = "💑" then set end of storageKeys to "🧑‍❤️‍🧑"
		if tile = "💏" then set end of storageKeys to "🧑‍❤️‍💋‍🧑"
		repeat with storageKey in storageKeys
			if chosen = tile then
				(updatedTones's removeObjectForKey:(contents of storageKey))
			else
				(updatedTones's setObject:chosen forKey:(contents of storageKey))
			end if
		end repeat
	end repeat
	set keepTonesKey to (updatedTones's |count|() as integer) > 0 or (oldRoot's objectForKey:tonesKey) is not missing value
	return my saveTonePreferences(oldRoot, updatedTones, keepTonesKey) & report
end applySettings

-- Загружает доступные варианты тонов из внутреннего каталога macOS.
on skinToneCatalog()
	set frameworkBundle to current application's NSBundle's bundleWithPath:"/System/Library/PrivateFrameworks/EmojiFoundation.framework"
	if frameworkBundle is missing value or not (frameworkBundle's load() as boolean) then error "Не удалось открыть каталог эмодзи macOS."
	set categoryClass to frameworkBundle's classNamed:"EMFEmojiCategory"
	set tokenClass to frameworkBundle's classNamed:"EMFEmojiToken"
	set utilitiesClass to frameworkBundle's classNamed:"EMFStringUtilities"
	if categoryClass is missing value or tokenClass is missing value or utilitiesClass is missing value or not ((utilitiesClass's respondsToSelector:"_skinToneVariantsForString:") as boolean) then error "Эта версия macOS использует другой каталог вариантов эмодзи."
	
	set catalog to current application's NSMutableDictionary's dictionary()
	set categories to {"PeopleEmoji", "ActivityEmoji", "ObjectsEmoji"}
	repeat with categoryName in categories
		set entries to (categoryClass's performSelector:(contents of categoryName)) as list
		repeat with entry in entries
			set tile to contents of entry
			if class of tile is text then
				set tokenRef to (tokenClass's emojiTokenWithString:tile localeData:(missing value))
				if (tokenRef's supportsSkinToneVariants() as boolean) then
					set options to (utilitiesClass's performSelector:"_skinToneVariantsForString:" withObject:tile)
					if options is not missing value then
						set optionCount to options's |count|() as integer
						if optionCount = 6 or optionCount = 25 then (catalog's setObject:options forKey:tile)
					end if
				end if
			end if
		end repeat
	end repeat
	return catalog
end skinToneCatalog

-- Добавляет или убирает селектор U+FE0F после первого знака эмодзи.
on alternatePresentation(tile)
	set codePoints to (id of tile) as list
	set tailPoints to rest of codePoints
	if (count of tailPoints) > 0 and item 1 of tailPoints = 65039 then
		set tailPoints to rest of tailPoints
	else
		set tailPoints to {65039} & tailPoints
	end if
	return string id ({item 1 of codePoints} & tailPoints)
end alternatePresentation

-- Возвращает варианты тона для эмодзи или сообщает, что их нет.
on catalogOptions(catalog, tile)
	set options to catalog's objectForKey:tile
	if options is missing value then error "В каталоге macOS нет поддерживаемых вариантов тона для " & tile & "."
	return options as list
end catalogOptions

-- Проверяет, что тон задан целым числом от 0 до 5.
on validateTone(tone, labelText)
	if class of tone is not integer or tone < 0 or tone > 5 then error labelText & " должен быть целым числом от 0 до 5."
end validateTone

-- Выбирает вариант для одного тона или пары тонов.
on selectTone(tile, options, toneSpec)
	if (count of options) = 6 then
		my validateTone(toneSpec, "Тон для " & tile)
		return item (toneSpec + 1) of options
	end if
	if class of toneSpec is list then
		if (count of toneSpec) is not 2 then error "Для " & tile & " укажите два тона."
		set {firstTone, secondTone} to toneSpec
	else
		set {firstTone, secondTone} to {toneSpec, toneSpec}
	end if
	my validateTone(firstTone, "Первый тон для " & tile)
	my validateTone(secondTone, "Второй тон для " & tile)
	if firstTone = 0 and secondTone = 0 then return tile
	if firstTone = 0 or secondTone = 0 then error "Для " & tile & " доступны либо {0, 0}, либо два тона от 1 до 5."
	-- При одинаковом тоне сохраняем короткую форму 💏 и 💑.
	if firstTone = secondTone and tile is in {"💏", "💑"} then
		set toneModifiers to {"🏻", "🏼", "🏽", "🏾", "🏿"}
		return tile & item firstTone of toneModifiers
	end if
	-- В каталоге пять вариантов второго тона на каждый первый.
	return item ((firstTone - 1) * 5 + secondTone) of options
end selectTone

-- Задаёт тон портрету и, при выборе blond, отдельному светловолосому значку.
on setPortraitTone(selectedVariants, catalog, tile, blondTile, tone, hair)
	my validateTone(tone, "Тон для " & tile)
	if hair is not in {"blond", "brunette", "standard"} then error "Для " & tile & " укажите blond, brunette или standard."
	if hair = "brunette" and tone = 2 then error "У " & tile & " с тоном 2 светлые волосы. Для тёмных волос укажите тон 1, 3, 4 или 5."
	set ordinaryVariants to my catalogOptions(catalog, tile)
	selectedVariants's setObject:(item (tone + 1) of ordinaryVariants) forKey:tile
	if hair = "blond" then
		set blondVariants to my catalogOptions(catalog, blondTile)
		selectedVariants's setObject:(item (tone + 1) of blondVariants) forKey:blondTile
	end if
end setPortraitTone

-- Проверяет резервную копию и восстанавливает из неё тона.
on restoreTonePreferences(backupFile)
	set backupDomain to current application's NSDictionary's dictionaryWithContentsOfFile:backupFile
	if backupDomain is missing value then error "Не удалось прочитать резервную копию: " & backupFile
	if (backupDomain's objectForKey:defaultsKey) is missing value then
		-- Копия без настроек эмодзи бывает пустой или содержит данные стикеров.
		repeat with entry in (backupDomain's allKeys() as list)
			if (contents of entry) does not start with "com.apple.stickers.recency." then error "Этот файл не похож на резервную копию настроек эмодзи: " & backupFile
		end repeat
	end if
	set backupRoot to my readDictionary(backupDomain, defaultsKey)
	set restoredTones to my readDictionary(backupRoot, tonesKey)
	repeat with variant in (restoredTones's allValues() as list)
		if class of (contents of variant) is not text then error "В резервной копии найден неверный вариант эмодзи: " & backupFile
	end repeat
	set keepTonesKey to (backupRoot's objectForKey:tonesKey) is not missing value
	return my saveTonePreferences(my readPreferencesRoot(), restoredTones, keepTonesKey)
end restoreTonePreferences

-- Читает словарь по ключу. Если ключа нет, возвращает пустой словарь.
on readDictionary(parentDict, keyName)
	set valueDict to parentDict's objectForKey:keyName
	if valueDict is missing value then return current application's NSDictionary's dictionary()
	if not ((valueDict's isKindOfClass:(current application's NSDictionary)) as boolean) then error "Неожиданный формат настройки " & keyName & "."
	return valueDict
end readDictionary

-- Читает основной блок настроек эмодзи из файла macOS.
on readPreferencesRoot()
	set plistFile to my preferencesFile()
	set fileManager to current application's NSFileManager's defaultManager()
	set domainValues to current application's NSDictionary's dictionaryWithContentsOfFile:plistFile
	if domainValues is missing value then
		if (fileManager's fileExistsAtPath:plistFile) as boolean then error "Не удалось прочитать " & plistFile
		return current application's NSDictionary's dictionary()
	end if
	return my readDictionary(domainValues, defaultsKey)
end readPreferencesRoot

-- Сохраняет изменённые тона и запрашивает обновление панели.
on saveTonePreferences(oldRoot, tonePreferences, keepTonesKey)
	set newRoot to oldRoot's mutableCopy()
	if keepTonesKey then
		newRoot's setObject:tonePreferences forKey:tonesKey
	else
		newRoot's removeObjectForKey:tonesKey
	end if
	set statusText to "Выбор вариантов уже соответствует настройкам."
	if not ((oldRoot's isEqualToDictionary:newRoot) as boolean) then set statusText to my writePreferences(oldRoot, newRoot)
	-- Запрашиваем обновление панели даже при повторном применении.
	set notificationCenterRef to current application's NSDistributedNotificationCenter's defaultCenter()
	notificationCenterRef's postNotificationName:"CPKCharacterPickerRecentsChangedNotification" object:(missing value) userInfo:(missing value) deliverImmediately:true
	return statusText
end saveTonePreferences

-- Создаёт резервную копию, записывает настройки через defaults и проверяет результат.
on writePreferences(oldRoot, newRoot)
	set backupFile to my backUpPreferences()
	try
		set defaultsTool to current application's NSTask's alloc()'s init()
		defaultsTool's setLaunchPath:"/usr/bin/defaults"
		set diagnostics to current application's NSPipe's pipe()
		defaultsTool's setStandardError:diagnostics
		if (newRoot's |count|() as integer) = 0 then
			defaultsTool's setArguments:{"delete", preferencesDomain, defaultsKey}
		else
			set serializer to current application's NSPropertyListSerialization
			set {xmlData, serializationError} to serializer's dataWithPropertyList:newRoot format:(current application's NSPropertyListXMLFormat_v1_0) options:0 |error|:(reference)
			if xmlData is missing value then error (serializationError's localizedDescription() as text)
			set xmlText to current application's NSString's alloc()'s initWithData:xmlData encoding:(current application's NSUTF8StringEncoding)
			defaultsTool's setArguments:{"write", preferencesDomain, defaultsKey, xmlText}
		end if
		set latestRoot to my readPreferencesRoot()
		if not ((latestRoot's isEqualToDictionary:oldRoot) as boolean) then error "Настройки изменились во время запуска. Закройте панель эмодзи и запустите скрипт ещё раз."
		defaultsTool's |launch|()
		set errorData to diagnostics's fileHandleForReading()'s readDataToEndOfFile()
		defaultsTool's waitUntilExit()
		if (defaultsTool's terminationStatus() as integer) is not 0 then
			set errorOutput to current application's NSString's alloc()'s initWithData:errorData encoding:(current application's NSUTF8StringEncoding)
			error "macOS не подтвердила запись настроек. " & (errorOutput as text)
		end if
		my verifySavedRoot(newRoot)
	on error messageText number errorNumber
		error messageText & linefeed & "Резервная копия: " & backupFile number errorNumber
	end try
	return "Выбор вариантов сохранён. Резервная копия: " & backupFile
end writePreferences

-- Ждёт, пока файл настроек отразит записанные изменения.
on verifySavedRoot(expectedRoot)
	set plistFile to my preferencesFile()
	set fileManager to current application's NSFileManager's defaultManager()
	set expectedEmpty to (expectedRoot's |count|() as integer) = 0
	-- defaults может обновить файл с задержкой.
	repeat 30 times
		set savedDomain to current application's NSDictionary's dictionaryWithContentsOfFile:plistFile
		if savedDomain is not missing value then
			set savedRoot to my readDictionary(savedDomain, defaultsKey)
			if (savedRoot's isEqualToDictionary:expectedRoot) as boolean then return
		else if expectedEmpty and not ((fileManager's fileExistsAtPath:plistFile) as boolean) then
			return
		end if
		current application's NSThread's sleepForTimeInterval:0.1
	end repeat
	error "Не удалось подтвердить запись настроек в файл macOS."
end verifySavedRoot

-- Возвращает путь к файлу настроек эмодзи текущего пользователя.
on preferencesFile()
	return (current application's NSHomeDirectory() as text) & "/Library/Preferences/" & preferencesDomain & ".plist"
end preferencesFile

-- Копирует текущий файл с сохранением прав или создаёт пустую копию при первом запуске.
on backUpPreferences()
	set homePath to current application's NSHomeDirectory() as text
	set plistFile to my preferencesFile()
	set backupFolder to homePath & "/Library/Application Support/ChangeEmojiSkin/Backups"
	set formatter to current application's NSDateFormatter's alloc()'s init()
	formatter's setLocale:(current application's NSLocale's localeWithLocaleIdentifier:"en_US_POSIX")
	formatter's setDateFormat:"yyyy-MM-dd_HHmmss"
	set stamp to (formatter's stringFromDate:(current application's NSDate's |date|())) as text
	set copyID to (current application's NSUUID's UUID()'s UUIDString()) as text
	set copyFolder to backupFolder & "/" & stamp & "-" & copyID
	set copyFile to copyFolder & "/com.apple.EmojiPreferences.plist"
	set fileManager to current application's NSFileManager's defaultManager()
	set privateFolder to current application's NSDictionary's dictionaryWithObject:448 forKey:(current application's NSFilePosixPermissions)
	set {folderCreated, fileError} to fileManager's createDirectoryAtPath:copyFolder withIntermediateDirectories:true attributes:privateFolder |error|:(reference)
	if not folderCreated then error "Не удалось создать папку резервной копии. " & (fileError's localizedDescription() as text)
	if (fileManager's fileExistsAtPath:plistFile) as boolean then
		set {fileCopied, fileError} to fileManager's copyItemAtPath:plistFile toPath:copyFile |error|:(reference)
		if not fileCopied then error "Не удалось скопировать настройки. " & (fileError's localizedDescription() as text)
	else
		set emptyDomain to current application's NSDictionary's dictionary()
		if not ((emptyDomain's writeToFile:copyFile atomically:true) as boolean) then error "Не удалось создать резервную копию."
	end if
	return copyFile
end backUpPreferences
