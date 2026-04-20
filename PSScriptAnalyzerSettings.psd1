@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',       # Разрешаем Write-Host для цветного вывода в интерактивных скриптах
        'PSUseBOMForUnicodeEncodedFile' # Игнорируем требование BOM (UTF-8 без BOM стандарт для Git)
    )
}