param(
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AssetRoot = Join-Path $ProjectRoot 'assets'
$FrameRoot = Join-Path $AssetRoot 'frames'
$LinesPath = Join-Path $ProjectRoot 'data\lines.json'
$RunLog = Join-Path $ProjectRoot 'run.log'
$ErrorLog = Join-Path $ProjectRoot 'error.log'

function Write-RunLog {
    param([string]$Message)
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $RunLog -Value $line -Encoding UTF8
    Write-Output $line
}

function Write-ErrorLog {
    param([System.Management.Automation.ErrorRecord]$Record)
    $text = "`r`n[{0:yyyy-MM-dd HH:mm:ss}] Windows 原生版启动失败`r`n{1}`r`n" -f (Get-Date), $Record
    Add-Content -LiteralPath $ErrorLog -Value $text -Encoding UTF8
}

try {
    Set-Content -LiteralPath $RunLog -Value '' -Encoding UTF8
    Write-RunLog '加载 WinForms'
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    Write-RunLog '读取台词库'
    $lineData = Get-Content -LiteralPath $LinesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Categories = $lineData.categories
    $script:Recent = @{}

    function Get-RandomLine {
        param([string]$Category)
        $property = $script:Categories.PSObject.Properties[$Category]
        if ($null -eq $property) {
            return $null
        }
        $pool = @($property.Value)
        if ($pool.Count -eq 0) {
            return $null
        }
        $recent = @()
        if ($script:Recent.ContainsKey($Category)) {
            $recent = @($script:Recent[$Category])
        }
        $choices = @($pool | Where-Object { $recent -notcontains $_ })
        if ($choices.Count -eq 0) {
            $choices = $pool
        }
        $line = $choices | Get-Random
        $script:Recent[$Category] = @($recent + $line | Select-Object -Last 5)
        return [string]$line
    }

    Write-RunLog '加载动画帧'
    $script:Frames = @()
    for ($i = 0; $i -lt 6; $i++) {
        $path = Join-Path $FrameRoot ("frame_{0}.png" -f $i)
        if (-not (Test-Path -LiteralPath $path)) {
            throw "缺少动画帧：$path"
        }
        $source = [System.Drawing.Image]::FromFile($path)
        try {
            $script:Frames += New-Object System.Drawing.Bitmap $source
        } finally {
            $source.Dispose()
        }
    }

    $petHeight = 170
    $petWidth = [Math]::Max(100, [int]($script:Frames[0].Width * $petHeight / $script:Frames[0].Height))
    $transparentColor = [System.Drawing.Color]::FromArgb(1, 2, 3)

    Write-RunLog '创建桌宠窗口'
    $petForm = New-Object System.Windows.Forms.Form
    $petForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $petForm.ShowInTaskbar = $false
    $petForm.TopMost = $true
    $petForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $petForm.BackColor = $transparentColor
    $petForm.TransparencyKey = $transparentColor
    $petForm.ClientSize = New-Object System.Drawing.Size($petWidth, $petHeight)

    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Dock = [System.Windows.Forms.DockStyle]::Fill
    $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $picture.BackColor = $transparentColor
    $picture.Image = $script:Frames[0]
    $petForm.Controls.Add($picture)

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $petForm.Location = New-Object System.Drawing.Point(
        ($workingArea.Right - $petWidth - 40),
        ($workingArea.Bottom - $petHeight - 40)
    )

    Write-RunLog '创建气泡窗口'
    $bubbleForm = New-Object System.Windows.Forms.Form
    $bubbleForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $bubbleForm.ShowInTaskbar = $false
    $bubbleForm.TopMost = $true
    $bubbleForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $bubbleForm.BackColor = [System.Drawing.Color]::FromArgb(244, 248, 252)

    $bubbleLabel = New-Object System.Windows.Forms.Label
    $bubbleLabel.AutoSize = $true
    $bubbleLabel.MaximumSize = New-Object System.Drawing.Size(300, 0)
    $bubbleLabel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $bubbleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
    $bubbleLabel.ForeColor = [System.Drawing.Color]::FromArgb(64, 79, 97)
    $bubbleLabel.BackColor = $bubbleForm.BackColor
    $bubbleForm.Controls.Add($bubbleLabel)

    function Set-RoundedRegion {
        param([System.Windows.Forms.Form]$Form, [int]$Radius)
        $diameter = $Radius * 2
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($Form.Width - 1), ($Form.Height - 1))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        try {
            $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
            $path.AddArc(($rect.Right - $diameter), $rect.Top, $diameter, $diameter, 270, 90)
            $path.AddArc(($rect.Right - $diameter), ($rect.Bottom - $diameter), $diameter, $diameter, 0, 90)
            $path.AddArc($rect.Left, ($rect.Bottom - $diameter), $diameter, $diameter, 90, 90)
            $path.CloseFigure()
            if ($null -ne $Form.Region) {
                $Form.Region.Dispose()
            }
            $Form.Region = New-Object System.Drawing.Region $path
        } finally {
            $path.Dispose()
        }
    }

    function Move-Bubble {
        if (-not $bubbleForm.Visible) {
            return
        }
        $area = [System.Windows.Forms.Screen]::FromControl($petForm).WorkingArea
        $x = [int]($petForm.Left + (($petForm.Width - $bubbleForm.Width) / 2))
        $y = $petForm.Top - $bubbleForm.Height - 8
        $x = [Math]::Max($area.Left, [Math]::Min($x, $area.Right - $bubbleForm.Width))
        $y = [Math]::Max($area.Top, $y)
        $bubbleForm.Location = New-Object System.Drawing.Point($x, $y)
    }

    $bubbleTimer = New-Object System.Windows.Forms.Timer
    $bubbleTimer.Interval = 8000
    $bubbleTimer.Add_Tick({
        $bubbleTimer.Stop()
        $bubbleForm.Hide()
    })

    function Show-Bubble {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) {
            return
        }
        $bubbleLabel.Text = $Text
        $preferred = $bubbleLabel.PreferredSize
        $bubbleLabel.Location = New-Object System.Drawing.Point(0, 0)
        $bubbleLabel.Size = $preferred
        $bubbleForm.ClientSize = $preferred
        Set-RoundedRegion -Form $bubbleForm -Radius 18
        Move-Bubble
        $bubbleForm.Show()
        Move-Bubble
        $bubbleForm.BringToFront()
        $bubbleTimer.Stop()
        $bubbleTimer.Start()
    }

    Write-RunLog '创建系统托盘'
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = [System.Drawing.SystemIcons]::Information
    $tray.Text = '黎深桌宠'
    $tray.Visible = $true

    function Speak-Category {
        param([string]$Category)
        $line = Get-RandomLine -Category $Category
        if ([string]::IsNullOrWhiteSpace($line)) {
            return
        }
        if (-not $petForm.Visible) {
            $petForm.Show()
        }
        Show-Bubble -Text $line
        $tray.BalloonTipTitle = '黎深'
        $tray.BalloonTipText = $line
        $tray.ShowBalloonTip(6000)
    }

    function Speak-Now {
        $hour = (Get-Date).Hour
        if ($hour -eq 11) {
            Speak-Category 'lunch'
        } elseif ($hour -eq 18) {
            Speak-Category 'dinner'
        } elseif ($hour -ge 23 -or $hour -lt 6) {
            Speak-Category 'night'
        } else {
            Speak-Category (@('daily', 'miss', 'cheer') | Get-Random)
        }
    }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $sayItem = $menu.Items.Add('让黎深说句话')
    $toggleItem = $menu.Items.Add('显示 / 隐藏桌宠')
    $reminderItem = $menu.Items.Add('暂停提醒')
    [void]$menu.Items.Add('-')
    $quitItem = $menu.Items.Add('退出')
    $tray.ContextMenuStrip = $menu
    $script:RemindersOn = $true

    $sayItem.Add_Click({ Speak-Now })
    $toggleItem.Add_Click({
        if ($petForm.Visible) {
            $petForm.Hide()
            $bubbleForm.Hide()
        } else {
            $petForm.Show()
        }
    })
    $reminderItem.Add_Click({
        $script:RemindersOn = -not $script:RemindersOn
        $reminderItem.Text = if ($script:RemindersOn) { '暂停提醒' } else { '恢复提醒' }
    })
    $quitItem.Add_Click({
        $tray.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    $tray.Add_MouseClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Speak-Now
        }
    })

    $script:Dragging = $false
    $script:Moved = $false
    $script:DragOffset = New-Object System.Drawing.Point(0, 0)
    $picture.Add_MouseDown({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:Dragging = $true
            $script:Moved = $false
            $script:DragOffset = $eventArgs.Location
        }
    })
    $picture.Add_MouseMove({
        if ($script:Dragging) {
            $cursor = [System.Windows.Forms.Cursor]::Position
            $next = New-Object System.Drawing.Point(
                ($cursor.X - $script:DragOffset.X),
                ($cursor.Y - $script:DragOffset.Y)
            )
            if ([Math]::Abs($next.X - $petForm.Left) + [Math]::Abs($next.Y - $petForm.Top) -gt 3) {
                $script:Moved = $true
            }
            $petForm.Location = $next
            Move-Bubble
        }
    })
    $picture.Add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if (-not $script:Moved) {
                Speak-Category 'poke'
            }
            $script:Dragging = $false
        }
    })

    $animationSequence = @(0, 0, 1, 3, 2, 4, 5, 0)
    $animationDurations = @(1400, 200, 500, 700, 900, 700, 600, 400)
    $script:AnimationIndex = 0
    $animationTimer = New-Object System.Windows.Forms.Timer
    $animationTimer.Interval = $animationDurations[0]
    $animationTimer.Add_Tick({
        $script:AnimationIndex = ($script:AnimationIndex + 1) % $animationSequence.Count
        $picture.Image = $script:Frames[$animationSequence[$script:AnimationIndex]]
        $animationTimer.Interval = $animationDurations[$script:AnimationIndex]
    })
    $animationTimer.Start()

    function Get-NextHourlyTime {
        $now = Get-Date
        $next = $now.Date.AddHours($now.Hour + 1)
        return $next.AddMinutes((Get-Random -Minimum -12 -Maximum 13))
    }

    $script:Fired = @{}
    $script:NextHourly = Get-NextHourlyTime
    $scheduleTimer = New-Object System.Windows.Forms.Timer
    $scheduleTimer.Interval = 30000
    $scheduleTimer.Add_Tick({
        if (-not $script:RemindersOn) {
            return
        }
        $now = Get-Date
        $day = $now.ToString('yyyyMMdd')
        $key = "$day-lunch"
        if ($now.Hour -eq 11 -and $now.Minute -lt 30 -and -not $script:Fired.ContainsKey($key)) {
            $script:Fired[$key] = $true
            Speak-Category 'lunch'
            return
        }
        $key = "$day-dinner"
        if ($now.Hour -eq 18 -and $now.Minute -lt 30 -and -not $script:Fired.ContainsKey($key)) {
            $script:Fired[$key] = $true
            Speak-Category 'dinner'
            return
        }
        $key = "$day-night"
        if ($now.Hour -eq 23 -and $now.Minute -ge 30 -and -not $script:Fired.ContainsKey($key)) {
            $script:Fired[$key] = $true
            Speak-Category 'night'
            return
        }
        if ($now -ge $script:NextHourly) {
            $script:NextHourly = Get-NextHourlyTime
            if ($now.Hour -ge 7 -and $now.Hour -le 23) {
                Speak-Category (@('daily', 'miss', 'cheer', 'weather') | Get-Random)
            }
        }
    })
    $scheduleTimer.Start()

    $greetingTimer = New-Object System.Windows.Forms.Timer
    $greetingTimer.Interval = 1500
    $greetingTimer.Add_Tick({
        $greetingTimer.Stop()
        Speak-Category 'greeting'
    })

    $petForm.Show()
    $greetingTimer.Start()

    if ($SelfTest -or $env:LISHEN_SELFTEST) {
        Write-RunLog '自检模式：3 秒后退出'
        $selfTestTimer = New-Object System.Windows.Forms.Timer
        $selfTestTimer.Interval = 3000
        $selfTestTimer.Add_Tick({
            $selfTestTimer.Stop()
            [System.Windows.Forms.Application]::Exit()
        })
        $selfTestTimer.Start()
    }

    Write-RunLog '进入 WinForms 消息循环'
    [System.Windows.Forms.Application]::Run()
    Write-RunLog 'Windows 原生版已退出'
} catch {
    Write-ErrorLog -Record $_
    Write-Error $_
    exit 1
} finally {
    if ($null -ne (Get-Variable tray -ValueOnly -ErrorAction SilentlyContinue)) {
        $tray.Visible = $false
        $tray.Dispose()
    }
    if ($null -ne (Get-Variable bubbleForm -ValueOnly -ErrorAction SilentlyContinue)) {
        $bubbleForm.Dispose()
    }
    if ($null -ne (Get-Variable petForm -ValueOnly -ErrorAction SilentlyContinue)) {
        $petForm.Dispose()
    }
    if ($null -ne (Get-Variable Frames -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        foreach ($frame in $script:Frames) {
            $frame.Dispose()
        }
    }
}
