param(
    [Parameter(Mandatory = $true)][string]$ContentFile,
    [Parameter(Mandatory = $true)][string]$PositionFile
)

$ErrorActionPreference = 'Stop'

# ---------- read toast content ----------
try {
    $content = Get-Content -LiteralPath $ContentFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch { exit 1 }

$kind  = $content.kind
$title = [string]$content.title
$body  = if ($content.body) { [string]$content.body } else { $null }

# ---------- read saved position ----------
$left = $null; $top = $null
if (Test-Path -LiteralPath $PositionFile) {
    try {
        $pos = Get-Content -LiteralPath $PositionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $pos.left -and $null -ne $pos.top) {
            $left = [double]$pos.left
            $top  = [double]$pos.top
        }
    } catch {}
}

# ---------- accent color ----------
$accent = @{
    done     = '#22C55E'
    error    = '#EF4444'
    warn     = '#F59E0B'
    question = '#4F7CFF'
}
$accentColor = $accent[$kind]
if (-not $accentColor) { $accentColor = '#F59E0B' }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function New-Brush([string]$hex) {
    $hex = $hex -replace '^#', ''
    $a = [byte]255
    $r = [Convert]::ToByte($hex.Substring(0, 2), 16)
    $g = [Convert]::ToByte($hex.Substring(2, 2), 16)
    $b = [Convert]::ToByte($hex.Substring(4, 2), 16)
    $c = [System.Windows.Media.Color]::FromArgb($a, $r, $g, $b)
    return New-Object System.Windows.Media.SolidColorBrush($c)
}

# glyphs (ASCII-safe via code points)
$grip   = [char]0x283F
$dragW  = [char]0x62D6 + [char]0x52A8
$closeX = [char]0x00D7

# ---------- window ----------
$window = New-Object System.Windows.Window
$window.WindowStyle        = [System.Windows.WindowStyle]::None
$window.AllowsTransparency = $true
$window.Background         = [System.Windows.Media.Brushes]::Transparent
$window.Topmost            = $true
$window.ShowInTaskbar      = $false
$window.ResizeMode         = [System.Windows.ResizeMode]::NoResize
$window.Width              = 380
$window.SizeToContent      = [System.Windows.SizeToContent]::Height
$window.UseLayoutRounding  = $true

# ---------- card ----------
$border = New-Object System.Windows.Controls.Border
$border.CornerRadius    = New-Object System.Windows.CornerRadius(10)
$border.Background      = New-Brush '#FFFFFF'
$border.BorderBrush     = New-Brush '#E5E7EB'
$border.BorderThickness = New-Object System.Windows.Thickness(1)
$border.Margin          = New-Object System.Windows.Thickness(10)

$grid = New-Object System.Windows.Controls.Grid
$c0 = New-Object System.Windows.Controls.ColumnDefinition
$c0.Width = New-Object System.Windows.GridLength(4)
$c1 = New-Object System.Windows.Controls.ColumnDefinition
$c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$grid.ColumnDefinitions.Add($c0) | Out-Null
$grid.ColumnDefinitions.Add($c1) | Out-Null

# left accent
$accentBar = New-Object System.Windows.Controls.Border
$accentBar.Background   = New-Brush $accentColor
$accentBar.CornerRadius = New-Object System.Windows.CornerRadius(10, 0, 0, 10)
[System.Windows.Controls.Grid]::SetColumn($accentBar, 0)
$grid.Children.Add($accentBar) | Out-Null

# content column
$stack = New-Object System.Windows.Controls.StackPanel
$stack.Margin = New-Object System.Windows.Thickness(12, 8, 12, 12)
[System.Windows.Controls.Grid]::SetColumn($stack, 1)

# top row: drag handle (left) + close (right)
$topRow = New-Object System.Windows.Controls.Grid
$topRow.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

$dragHandle = New-Object System.Windows.Controls.Border
$dragHandle.Cursor     = [System.Windows.Input.Cursors]::Hand
$dragHandle.Padding    = New-Object System.Windows.Thickness(0, 2, 0, 2)
$dragHandle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$dragHandle.Add_MouseLeftButtonDown({
    try { $window.DragMove() } catch {}
})
$hint = New-Object System.Windows.Controls.TextBlock
$hint.Text = "$grip $dragW"
$hint.FontSize = 11
$hint.Foreground = New-Brush '#9CA3AF'
$dragHandle.Child = $hint
$topRow.Children.Add($dragHandle) | Out-Null

$closeBox = New-Object System.Windows.Controls.Border
$closeBox.Width               = 24
$closeBox.Height              = 24
$closeBox.Cursor              = [System.Windows.Input.Cursors]::Hand
$closeBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$closeBox.VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
$closeBox.Add_MouseLeftButtonUp({ $window.Close() })
$closeText = New-Object System.Windows.Controls.TextBlock
$closeText.Text                = $closeX
$closeText.FontSize            = 15
$closeText.Foreground          = New-Brush '#9CA3AF'
$closeText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$closeText.VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
$closeBox.Child = $closeText
$topRow.Children.Add($closeBox) | Out-Null
$stack.Children.Add($topRow) | Out-Null

# title
$titleText = New-Object System.Windows.Controls.TextBlock
$titleText.Text         = $title
$titleText.FontWeight   = [System.Windows.FontWeights]::SemiBold
$titleText.FontSize     = 14
$titleText.Foreground   = New-Brush '#111827'
$titleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$stack.Children.Add($titleText) | Out-Null

# body
if ($body) {
    $bodyText = New-Object System.Windows.Controls.TextBlock
    $bodyText.Text         = $body
    $bodyText.FontSize     = 13
    $bodyText.Foreground   = New-Brush '#4B5563'
    $bodyText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $bodyText.LineHeight   = 20
    $bodyText.Margin       = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $stack.Children.Add($bodyText) | Out-Null
}

$grid.Children.Add($stack) | Out-Null
$border.Child = $grid
$window.Content = $border

# ---------- position on load ----------
$window.Add_Loaded({
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($null -eq $left -or $null -eq $top) {
        $window.Left = $wa.Right  - $window.Width  - 12
        $window.Top  = $wa.Bottom - $window.Height - 12
    } else {
        $window.Left = [Math]::Max($wa.Left, [Math]::Min($left, $wa.Right - 60))
        $window.Top  = [Math]::Max($wa.Top,  [Math]::Min($top,  $wa.Bottom - 40))
    }
})

# ---------- save position + cleanup on close ----------
$window.Add_Closed({
    try {
        $p = @{ left = [Math]::Round($window.Left, 0); top = [Math]::Round($window.Top, 0) } | ConvertTo-Json
        $dir = Split-Path -Parent $PositionFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $PositionFile -Value $p -Encoding UTF8
    } catch {}
    try { Remove-Item -LiteralPath $ContentFile -Force -ErrorAction SilentlyContinue } catch {}
})

# ---------- show and run message loop ----------
$window.ShowDialog() | Out-Null
