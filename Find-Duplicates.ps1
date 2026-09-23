<#
.SYNOPSIS
    Поиск дубликатов файлов (по содержимому, SHA256) и безопасное удаление лишних копий.

.DESCRIPTION
    1. Собирает файлы из указанных папок (-Paths).
    2. Группирует по размеру, затем считает SHA256 только для файлов одинакового размера.
    3. Для каждой группы одинаковых файлов решает, что оставить:
       - файлы внутри -ProtectedPaths (папки проектов After Effects) НИКОГДА не удаляются,
         т.к. проект .aep ссылается на них по абсолютному пути;
       - удаляются только копии вне защищённых папок (например, в Загрузках);
       - если ни одна копия не лежит в защищённой папке, оставляется самая старая.
    4. Сохраняет отчёт в CSV. По умолчанию НИЧЕГО не удаляет.
       С ключом -Action Recycle отправляет дубликаты в Корзину (можно восстановить).

.EXAMPLE
    # Только отчёт:
    .\Find-Duplicates.ps1 -Paths "$env:USERPROFILE\Downloads","D:\AE_Projects" -ProtectedPaths "D:\AE_Projects"

.EXAMPLE
    # Отправить найденные дубликаты в Корзину:
    .\Find-Duplicates.ps1 -Paths "$env:USERPROFILE\Downloads","D:\AE_Projects" -ProtectedPaths "D:\AE_Projects" -Action Recycle
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths,

    # Папки, из которых файлы никогда не удаляются (папки проектов).
    [string[]]$ProtectedPaths = @(),

    # Игнорировать файлы меньше этого размера (МБ) — мелочь почти не занимает места.
    [double]$MinSizeMB = 1,

    # Report — только отчёт; Recycle — дубликаты в Корзину.
    [ValidateSet('Report', 'Recycle')]
    [string]$Action = 'Report',

    [string]$ReportPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) ("duplicates_{0:yyyy-MM-dd_HH-mm}.csv" -f (Get-Date)))
)

$ErrorActionPreference = 'Stop'

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return '{0:N2} ГБ' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N1} МБ' -f ($bytes / 1MB) }
    return '{0:N0} КБ' -f ($bytes / 1KB)
}

$protectedFull = $ProtectedPaths | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.TrimEnd('\') + '\' }

function Test-Protected([string]$fullName) {
    foreach ($p in $protectedFull) {
        if ($fullName.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# --- 1. Сбор файлов ---------------------------------------------------------
Write-Host 'Сканирование папок...' -ForegroundColor Cyan
$minBytes = [long]($MinSizeMB * 1MB)
$seen = @{}
$files = foreach ($root in $Paths) {
    Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $minBytes -and -not $seen.ContainsKey($_.FullName) } |
        ForEach-Object { $seen[$_.FullName] = $true; $_ }
}
Write-Host ("Найдено файлов: {0}" -f @($files).Count)

# --- 2. Группировка по размеру, затем по хэшу -------------------------------
$sizeGroups = @($files | Group-Object Length | Where-Object Count -gt 1)
$toHash = @($sizeGroups | ForEach-Object { $_.Group })
Write-Host ("Файлов-кандидатов (совпадает размер): {0}" -f $toHash.Count)

$hashed = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $toHash) {
    $i++
    Write-Progress -Activity 'Вычисление SHA256' -Status $f.Name -PercentComplete ($i * 100 / [Math]::Max($toHash.Count, 1))
    try {
        $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $hashed.Add([pscustomobject]@{ File = $f; Hash = $h })
    } catch {
        Write-Warning "Не удалось прочитать: $($f.FullName)"
    }
}
Write-Progress -Activity 'Вычисление SHA256' -Completed

$dupGroups = @($hashed | Group-Object Hash | Where-Object Count -gt 1)

# --- 3. Решение: что оставить, что удалить ----------------------------------
$report = New-Object System.Collections.Generic.List[object]
$toDelete = New-Object System.Collections.Generic.List[object]
$groupNo = 0

foreach ($g in $dupGroups) {
    $groupNo++
    $items = $g.Group | ForEach-Object { $_.File }
    $protected = @($items | Where-Object { Test-Protected $_.FullName })
    $free = @($items | Where-Object { -not (Test-Protected $_.FullName) })

    if ($protected.Count -gt 0) {
        $keep = $protected           # все копии в проектах сохраняем
        $delete = $free
    } else {
        $oldest = $items | Sort-Object LastWriteTime, FullName | Select-Object -First 1
        $keep = @($oldest)
        $delete = @($items | Where-Object { $_.FullName -ne $oldest.FullName })
    }

    foreach ($k in $keep) {
        $report.Add([pscustomobject]@{ Group = $groupNo; Action = 'KEEP'; Size = Format-Size $k.Length; Bytes = $k.Length; Path = $k.FullName; Hash = $g.Name })
    }
    foreach ($d in $delete) {
        $report.Add([pscustomobject]@{ Group = $groupNo; Action = 'DELETE'; Size = Format-Size $d.Length; Bytes = $d.Length; Path = $d.FullName; Hash = $g.Name })
        $toDelete.Add($d)
    }
}

$report | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'

$totalBytes = ($toDelete | Measure-Object Length -Sum).Sum
Write-Host ''
Write-Host ("Групп одинаковых файлов: {0}" -f $dupGroups.Count) -ForegroundColor Yellow
Write-Host ("Лишних копий к удалению:  {0}" -f $toDelete.Count) -ForegroundColor Yellow
Write-Host ("Можно освободить:        {0}" -f (Format-Size ([long]$totalBytes))) -ForegroundColor Green
Write-Host ("Отчёт: {0}" -f $ReportPath)

# --- 4. Удаление в Корзину --------------------------------------------------
if ($Action -eq 'Recycle' -and $toDelete.Count -gt 0) {
    $answer = Read-Host ("Отправить {0} файлов в Корзину? (y/n)" -f $toDelete.Count)
    if ($answer -ne 'y') { Write-Host 'Отменено.'; return }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $done = 0
    foreach ($d in $toDelete) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $d.FullName,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $done++
        } catch {
            Write-Warning "Не удалось удалить: $($d.FullName) — $($_.Exception.Message)"
        }
    }
    Write-Host ("В Корзину отправлено: {0}. Не забудьте очистить Корзину, чтобы реально освободить место." -f $done) -ForegroundColor Green
}
