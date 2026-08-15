# Instalador da statusline adaptativa do Claude Code — Windows sem Git Bash.
#
# Uso (PowerShell, na pasta do pacote):
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Se você TEM Git Bash instalado, use install.sh no Git Bash: o Claude Code
# executa a statusline por lá e a versão Bash é a mais testada.

$ErrorActionPreference = 'Stop'

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src    = Join-Path $srcDir 'statusline.ps1'
if (-not (Test-Path -LiteralPath $src)) { throw "statusline.ps1 não encontrado em $srcDir" }

$configDir = $env:CLAUDE_CONFIG_DIR
if ([string]::IsNullOrWhiteSpace($configDir)) { $configDir = Join-Path $env:USERPROFILE '.claude' }
$dest     = Join-Path $configDir 'statusline.ps1'
$settings = Join-Path $configDir 'settings.json'
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host ''
Write-Host 'Statusline adaptativa para Claude Code'
Write-Host '======================================'
Write-Host ''

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host '  + git encontrado'
} else {
    Write-Host '  ! git não encontrado — a statusline funciona, mas sem pasta/branch'
}

New-Item -ItemType Directory -Force -Path $configDir | Out-Null

if (Test-Path -LiteralPath $dest) {
    Copy-Item -LiteralPath $dest -Destination "$dest.bak-$stamp" -Force
    Write-Host "  + backup da statusline anterior: $dest.bak-$stamp"
}
Copy-Item -LiteralPath $src -Destination $dest -Force
Write-Host "  + script instalado em $dest"

# Caminho com barras normais: o Claude Code pode rotear o comando pelo Git Bash,
# que consome as contrabarras do Windows como escape.
$cmdPath = $dest -replace '\\', '/'
$command = "powershell -NoProfile -File $cmdPath"

if (Test-Path -LiteralPath $settings) {
    Copy-Item -LiteralPath $settings -Destination "$settings.bak-$stamp" -Force
    Write-Host "  + backup do settings.json: $settings.bak-$stamp"
    try {
        $json = Get-Content -LiteralPath $settings -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($json)) { $json = '{}' }
        $obj = $json | ConvertFrom-Json
    } catch {
        Write-Host '  ! settings.json ilegível; começando de um objeto vazio (o backup está salvo)'
        $obj = [PSCustomObject]@{}
    }
} else {
    $obj = [PSCustomObject]@{}
    Write-Host '  + settings.json criado'
}

$statusLine = [PSCustomObject]@{ type = 'command'; command = $command; padding = 0 }
$obj | Add-Member -MemberType NoteProperty -Name 'statusLine' -Value $statusLine -Force
($obj | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $settings -Encoding UTF8
Write-Host '  + settings.json atualizado'

Write-Host ''
Write-Host 'Prévia:'
Write-Host ''
$preview = '{"model":{"display_name":"Opus 5"},"effort":{"level":"high"},"context_window":{"total_input_tokens":47000,"used_percentage":31,"remaining_percentage":69},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":0},"seven_day":{"used_percentage":28}},"cost":{"total_cost_usd":0.87},"transcript_path":"","workspace":{"current_dir":"' + ($PWD.Path -replace '\\', '/') + '"}}'
$preview | & powershell -NoProfile -File $dest

Write-Host ''
Write-Host 'Pronto. Abra o Claude Code e a barra já aparece.'
Write-Host 'Dicas (PowerShell):'
Write-Host '  $env:CLAUDE_STATUSLINE_STYLE = "ascii"     # console sem suporte a emoji'
Write-Host '  $env:CLAUDE_STATUSLINE_LABEL = "trabalho"  # rótulo fixo de conta'
Write-Host '  $env:CLAUDE_STATUSLINE_MARGIN = "6"        # mais folga na borda direita'
Write-Host ''
