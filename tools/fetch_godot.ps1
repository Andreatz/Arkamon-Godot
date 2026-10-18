[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Arkamon\godot-4.7.2'),
    [switch]$WithTemplates
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$version = '4.7.2'
$releaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$version-stable"
$editorArchive = "Godot_v$version-stable_win64.exe.zip"
$templateArchive = "Godot_v$version-stable_export_templates.tpz"
$consoleExe = Join-Path $Destination "Godot_v$version-stable_win64_console.exe"
$templateDirectory = Join-Path $env:APPDATA "Godot\export_templates\$version.stable"
$templateNames = @('version.txt', 'windows_release_x86_64.exe', 'windows_debug_x86_64.exe')

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$needsEditor = -not (Test-Path -LiteralPath $consoleExe)
$missingTemplates = @($templateNames | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $templateDirectory $_))
})
$needsTemplates = $WithTemplates -and $missingTemplates.Count -gt 0

if ($needsEditor -or $needsTemplates) {
    $checksumPath = Join-Path $Destination 'SHA512-SUMS.txt'
    Write-Host "Scarico i checksum ufficiali Godot $version."
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/SHA512-SUMS.txt" -OutFile $checksumPath
    $checksumLines = Get-Content -LiteralPath $checksumPath
}

function Get-VerifiedArchive([string]$Name) {
    $archivePath = Join-Path $Destination $Name
    $escapedName = [regex]::Escape($Name)
    $checksumLine = @($checksumLines | Where-Object { $_ -match "\s+\*?$escapedName$" })
    if ($checksumLine.Count -ne 1) {
        throw "Checksum ufficiale assente o ambiguo per $Name."
    }
    $expectedHash = ($checksumLine[0] -split '\s+')[0]
    if (Test-Path -LiteralPath $archivePath) {
        $existingHash = (Get-FileHash -Algorithm SHA512 -LiteralPath $archivePath).Hash
        if ($existingHash -eq $expectedHash) { return $archivePath }
    }
    Write-Host "Scarico $Name dalla release ufficiale."
    Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$Name" -OutFile $archivePath
    $actualHash = (Get-FileHash -Algorithm SHA512 -LiteralPath $archivePath).Hash
    if ($actualHash -ne $expectedHash) {
        throw "SHA512 non corrispondente per $Name. L'archivio non viene estratto."
    }
    return $archivePath
}

if ($needsEditor) {
    $verifiedEditor = Get-VerifiedArchive $editorArchive
    Expand-Archive -LiteralPath $verifiedEditor -DestinationPath $Destination -Force
}

if ($needsTemplates) {
    # The official archive contains every platform (about 1.3 GB). Only Windows
    # x86_64 templates are installed. Existing user templates are never replaced.
    $verifiedTemplates = Get-VerifiedArchive $templateArchive
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($verifiedTemplates)
    try {
        New-Item -ItemType Directory -Force -Path $templateDirectory | Out-Null
        foreach ($name in $missingTemplates) {
            $entry = $archive.GetEntry("templates/$name")
            if ($null -eq $entry) { throw "Template mancante nell'archivio: $name" }
            $target = Join-Path $templateDirectory $name
            if (-not (Test-Path -LiteralPath $target)) {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
        }
    } finally {
        $archive.Dispose()
    }
    Write-Host "Template Windows installati in $templateDirectory."
}

$reportedVersion = (& $consoleExe --headless --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $reportedVersion.StartsWith("$version.stable.")) {
    throw "Versione dell'editor inattesa: $reportedVersion"
}
Write-Host "Godot pronto: $reportedVersion"
# Return just the executable path so callers can use: $godot = & ./tools/fetch_godot.ps1
Write-Output $consoleExe
