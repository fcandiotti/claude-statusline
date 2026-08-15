# Statusline adaptativa para Claude Code — versão PowerShell.
# Use esta versão apenas no Windows SEM Git Bash instalado; havendo Git Bash,
# prefira statusline.sh (o Claude Code o executa nativamente).
#
# Variáveis de ambiente opcionais:
#   CLAUDE_STATUSLINE_STYLE=ascii   -> desliga emojis
#   CLAUDE_STATUSLINE_LABEL=nome    -> rótulo fixo de conta
#   CLAUDE_STATUSLINE_MARGIN=4      -> colunas reservadas na borda direita

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }
try { $d = $raw | ConvertFrom-Json } catch { $d = $null }

function Get-Node($obj, $name) {
    if ($null -ne $obj -and $null -ne $obj.PSObject.Properties[$name] -and $null -ne $obj.$name) { return $obj.$name }
    return $null
}
function Get-Str($obj, $name, $default) {
    $v = Get-Node $obj $name
    if ($null -eq $v -or "$v" -eq '') { return $default }
    return "$v"
}
function Get-Int($obj, $name) {
    $v = Get-Node $obj $name
    if ($null -eq $v) { return 0 }
    try { return [int][math]::Floor([double]$v) } catch { return 0 }
}

$model     = Get-Str  (Get-Node $d 'model')  'display_name' '?'
$effort    = Get-Str  (Get-Node $d 'effort') 'level'        '-'
$ctx       = Get-Node $d 'context_window'
$used      = Get-Int  $ctx 'total_input_tokens'
$ctxPct    = Get-Int  $ctx 'used_percentage'
$ctxFree   = Get-Int  $ctx 'remaining_percentage'
$limits    = Get-Node $d 'rate_limits'
$rl5node   = Get-Node $limits 'five_hour'
$rl7node   = Get-Node $limits 'seven_day'
$rl5       = Get-Int  $rl5node 'used_percentage'
$rl5Reset  = Get-Int  $rl5node 'resets_at'
$rl7       = Get-Int  $rl7node 'used_percentage'
$costNode  = Get-Node $d 'cost'
$cost      = 0.0
try { $cost = [double](Get-Node $costNode 'total_cost_usd') } catch { $cost = 0.0 }
$transcript = Get-Str $d 'transcript_path' ''
$dir        = Get-Str (Get-Node $d 'workspace') 'current_dir' (Get-Str $d 'cwd' '')

$e     = [char]27
$RESET = "${e}[0m"
$BOLD  = "${e}[1m"
$DIM   = "${e}[2m"
$TEAL  = "${e}[38;5;79m"
$GREEN = "${e}[38;5;71m"
$YELLOW= "${e}[38;5;179m"
$RED   = "${e}[38;5;167m"
$GREY  = "${e}[38;5;245m"
$DARK  = "${e}[38;5;238m"
$WHITE = "${e}[38;5;252m"
$BLUE  = "${e}[38;5;110m"
$PALETTE = @("${e}[38;5;140m", "${e}[38;5;173m", "${e}[38;5;79m", "${e}[38;5;110m", "${e}[38;5;179m", "${e}[38;5;71m")

$ascii = ($env:CLAUDE_STATUSLINE_STYLE -eq 'ascii')
if ($ascii) {
    $I_DOT = '*'; $I_BOLT = '!'; $I_DIR = '~'; $I_BRANCH = '@'; $I_CTX = 'ctx'; $I_CLOCK = '->'
    $BAR_FULL = '#'; $BAR_EMPTY = '-'; $SEP_CHAR = '|'
} else {
    $I_DOT    = [char]0x25CF
    $I_BOLT   = [char]0x26A1
    $I_DIR    = [char]::ConvertFromUtf32(0x1F4C1)
    $I_BRANCH = [char]0x2387
    $I_CTX    = [char]::ConvertFromUtf32(0x1F9E0)
    $I_CLOCK  = [char]0x21BB
    $BAR_FULL = [char]0x2588; $BAR_EMPTY = [char]0x2591; $SEP_CHAR = [char]0x2502
}

# Rótulo de conta: só aparece quando o config dir NÃO é o .claude padrão.
$label = $env:CLAUDE_STATUSLINE_LABEL
if ([string]::IsNullOrWhiteSpace($label)) {
    $cfg = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrWhiteSpace($cfg) -and $transcript -match '^(.*)[\\/]projects[\\/]') { $cfg = $Matches[1] }
    if (-not [string]::IsNullOrWhiteSpace($cfg)) {
        $base = (Split-Path -Leaf $cfg) -replace '^\.', ''
        if ($base -eq 'claude' -or $base -eq '') { $label = '' }
        elseif ($base -like 'claude-*') { $label = $base.Substring(7) }
        else { $label = $base }
    }
}

function Get-LabelColor($text) {
    $sum = 0
    foreach ($c in $text.ToCharArray()) { $sum += [int]$c }
    return $PALETTE[$sum % $PALETTE.Length]
}
function Get-PctColor($pct) {
    if ($pct -ge 80) { return $RED } elseif ($pct -ge 50) { return $YELLOW } else { return $GREEN }
}

$BAR_WIDTH = 10
function New-Bar($pct, $color) {
    $filled = [math]::Ceiling($pct * $BAR_WIDTH / 100.0)
    if ($filled -gt $BAR_WIDTH) { $filled = $BAR_WIDTH }
    if ($filled -lt 0) { $filled = 0 }
    $out = ''
    for ($i = 0; $i -lt $BAR_WIDTH; $i++) {
        if ($i -lt $filled) { $out += "$color$BAR_FULL" } else { $out += "$DARK$BAR_EMPTY" }
    }
    return "$out$RESET"
}
function Format-Tokens($n) {
    if ($n -ge 1000) { return "$([math]::Floor($n / 1000))K" }
    return "$n"
}
function Format-Eta($epoch) {
    $secs = $epoch - [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($secs -le 0) { return '0m' }
    $h = [math]::Floor($secs / 3600); $m = [math]::Floor(($secs % 3600) / 60)
    if ($h -gt 0) { return ('{0}h{1:d2}m' -f $h, $m) }
    return "${m}m"
}

# Largura visível: emojis fora do BMP ocupam 2 colunas (e já contam 2 em .Length);
# o raio (U+26A1) ocupa 2 mas conta 1, então recebe +1.
function Get-VisibleWidth($text) {
    $w = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ([char]::IsHighSurrogate($ch)) { $w += 2; $i++ }
        elseif ([int]$ch -eq 0x26A1) { $w += 2 }
        else { $w += 1 }
    }
    return $w
}

$P = New-Object System.Collections.ArrayList
$C = New-Object System.Collections.ArrayList
function Add-Segment($plain, $colored) { [void]$P.Add($plain); [void]$C.Add($colored) }

if (-not [string]::IsNullOrWhiteSpace($label)) {
    $lc = Get-LabelColor $label
    Add-Segment "$I_DOT $label" "$BOLD$lc$I_DOT $label$RESET"
}
Add-Segment "$model" "$BOLD$TEAL$model$RESET"
Add-Segment "$effort $I_BOLT" "$GREY$effort$RESET $YELLOW$I_BOLT$RESET"

$leaf = if ([string]::IsNullOrWhiteSpace($dir)) { '' } else { Split-Path -Leaf $dir }
$placeP = "$I_DIR $leaf"
$placeC = "$GREY$I_DIR$RESET $WHITE$leaf$RESET"
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $dir)) {
    $inRepo = (& git -C $dir rev-parse --git-dir 2>$null)
    if ($LASTEXITCODE -eq 0 -and $inRepo) {
        $branch = (& git -C $dir branch --show-current 2>$null)
        if ([string]::IsNullOrWhiteSpace($branch)) { $branch = (& git -C $dir rev-parse --short HEAD 2>$null) }
        $status = (& git -C $dir status --porcelain 2>$null)
        $dirtyP = ''; $dirtyC = ''
        if (-not [string]::IsNullOrWhiteSpace($status)) { $dirtyP = '*'; $dirtyC = "$YELLOW*$RESET" }
        $placeP = "$placeP $I_BRANCH $branch$dirtyP"
        $placeC = "$placeC $BLUE$I_BRANCH $branch$RESET$dirtyC"
    }
}
Add-Segment $placeP $placeC
$identityCount = $P.Count

$barPlain = '#' * $BAR_WIDTH
$ctxColor = Get-PctColor $ctxPct
$rl5Color = Get-PctColor $rl5
$rl7Color = Get-PctColor $rl7
$tok = Format-Tokens $used

Add-Segment "$I_CTX $tok $barPlain $ctxPct% ($ctxFree% livre)" `
            "$GREY$I_CTX$RESET $ctxColor$tok$RESET $(New-Bar $ctxPct $ctxColor) $ctxColor$ctxPct%$RESET $DIM$ctxColor($ctxFree% livre)$RESET"

$rl5P = "5h $barPlain $rl5%"
$rl5C = "$BOLD${WHITE}5h$RESET $(New-Bar $rl5 $rl5Color) $rl5Color$rl5%$RESET"
if ($rl5Reset -gt 0) {
    $eta = Format-Eta $rl5Reset
    $rl5P = "$rl5P $I_CLOCK $eta"
    $rl5C = "$rl5C $GREY$I_CLOCK $eta$RESET"
}
Add-Segment $rl5P $rl5C
Add-Segment "7d $rl7%" "$BOLD${WHITE}7d$RESET $rl7Color$rl7%$RESET"
$costStr = '$' + ('{0:F2}' -f $cost)
Add-Segment $costStr "$GREEN$costStr$RESET"

$SEP = "$DARK $SEP_CHAR $RESET"
$SEP_W = 3

$width = 0
if ($env:COLUMNS -match '^\d+$') { $width = [int]$env:COLUMNS }
if ($width -le 0) { try { $width = $Host.UI.RawUI.WindowSize.Width } catch { $width = 0 } }
if ($width -le 0) { $width = 1000 }
$margin = 4
if ($env:CLAUDE_STATUSLINE_MARGIN -match '^\d+$') { $margin = [int]$env:CLAUDE_STATUSLINE_MARGIN }
$avail = $width - $margin
if ($avail -lt 20) { $avail = 20 }

function Write-Segments($indexes) {
    $parts = @()
    foreach ($i in $indexes) { $parts += $C[$i] }
    Write-Output ($parts -join $SEP)
}
function Write-Group($indexes) {
    $cur = @(); $w = 0
    foreach ($i in $indexes) {
        $lw = Get-VisibleWidth $P[$i]
        if ($cur.Count -eq 0) { $cur = @($i); $w = $lw }
        elseif (($w + $SEP_W + $lw) -le $avail) { $cur += $i; $w = $w + $SEP_W + $lw }
        else { Write-Segments $cur; $cur = @($i); $w = $lw }
    }
    if ($cur.Count -gt 0) { Write-Segments $cur }
}

$n = $P.Count
$total = $SEP_W * ($n - 1)
for ($i = 0; $i -lt $n; $i++) { $total += Get-VisibleWidth $P[$i] }

if ($total -le $avail) {
    Write-Segments (0..($n - 1))
} else {
    Write-Group (0..($identityCount - 1))
    Write-Group ($identityCount..($n - 1))
}
