[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT_BIN,
    [switch]$ExportWindows
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $installed = Get-Command 'godot' -ErrorAction SilentlyContinue
    if ($null -ne $installed) {
        $Godot = $installed.Source
    } else {
        $Godot = & (Join-Path $PSScriptRoot 'fetch_godot.ps1') -WithTemplates:$ExportWindows
    }
}

function Invoke-GodotChecked([string[]]$Arguments, [string]$Description, [string]$Executable = $Godot) {
    Write-Host $Description
    $output = & $Executable @Arguments 2>&1
    $engineExitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    # A script parse error can leave Godot's exit status at zero during import.
    if ($engineExitCode -ne 0 -or ($output -match '(?m)^(SCRIPT ERROR:|ERROR:)')) {
        throw "Godot ha segnalato un errore durante: $Description"
    }
}

Invoke-GodotChecked -Arguments @('--headless', '--path', $projectDirectory, '--editor', '--quit') -Description 'Importazione risorse e script.'
Invoke-GodotChecked -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tests/test_core.gd') -Description 'Verifica logica di gioco e salvataggi.'
Invoke-GodotChecked -Arguments @('--headless', '--path', $projectDirectory, '--script', 'res://tests/test_flow.gd') -Description 'Verifica flusso di gioco e interfaccia.'
Invoke-GodotChecked -Arguments @('--headless', '--path', $projectDirectory, '--quit-after', '120') -Description 'Avvio della scena principale senza finestra.'

if ($ExportWindows) {
    $buildDirectory = Join-Path $projectDirectory 'build\windows'
    New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
    $executable = Join-Path $buildDirectory 'Arkamon.exe'
    Invoke-GodotChecked -Arguments @('--headless', '--path', $projectDirectory, '--export-release', 'Windows Desktop', $executable) -Description 'Esportazione Windows x86_64.'
    Invoke-GodotChecked -Executable $executable -Arguments @('--headless', '--quit-after', '120') -Description 'Avvio del pacchetto Windows esportato.'
    Write-Host "Build disponibile: $executable"
}

Write-Host 'Tutte le verifiche sono completate.'
