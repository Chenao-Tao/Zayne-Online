param(
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AssetRoot = Join-Path $ProjectRoot 'assets'
$FrameRoot = Join-Path $AssetRoot 'frames'
$StarRoot = Join-Path $AssetRoot 'star'
$LinesPath = Join-Path $ProjectRoot 'data\lines.json'
$IsSelfTest = $SelfTest -or [bool]$env:LISHEN_SELFTEST
$RunLog = if ($IsSelfTest) { Join-Path $env:TEMP "lishen-pet-selftest-$PID.log" } else { Join-Path $ProjectRoot 'run.log' }
$ErrorLog = if ($IsSelfTest) { Join-Path $env:TEMP "lishen-pet-selftest-error-$PID.log" } else { Join-Path $ProjectRoot 'error.log' }
$ThrowSpeedPx = 1450
$ThrowWaitSec = 4
$AngrySec = 12
$ThrowTickMs = 16
$ThrowPadPx = 180
$FeedSec = 8
$ThrowSensitivityLevels = @(
    @{ Label = '高灵敏度'; Speed = 1100 }
    @{ Label = '标准'; Speed = 1450 }
    @{ Label = '低灵敏度'; Speed = 1800 }
)
$script:NotifyToo = $false

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
    if (-not ('NativeIconMethods' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeIconMethods {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr handle, int index);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr handle, int index, int value);
}
'@
    }
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Write-RunLog ("线程单元：{0}" -f [System.Threading.Thread]::CurrentThread.ApartmentState)

    Write-RunLog '读取台词库'
    $lineData = Get-Content -LiteralPath $LinesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:CharacterCategories = @{
        lishen = $lineData.categories
        star = $lineData.categories
    }
    $charactersProperty = $lineData.PSObject.Properties['characters']
    if ($null -ne $charactersProperty) {
        $starProperty = $charactersProperty.Value.PSObject.Properties['star']
        if ($null -ne $starProperty) {
            $starCategoriesProperty = $starProperty.Value.PSObject.Properties['categories']
            if ($null -ne $starCategoriesProperty) {
                $script:CharacterCategories['star'] = $starCategoriesProperty.Value
            }
        }
    }
    $script:Recent = @{}

    function Get-RandomLine {
        param([string]$Category)
        $categories = $script:CharacterCategories[$script:CurrentCharacter]
        if ($null -eq $categories) {
            $categories = $script:CharacterCategories['lishen']
        }
        $property = $categories.PSObject.Properties[$Category]
        if ($null -eq $property) {
            return $null
        }
        $pool = @($property.Value)
        if ($pool.Count -eq 0) {
            return $null
        }
        $recent = @()
        $recentKey = "{0}:{1}" -f $script:CurrentCharacter, $Category
        if ($script:Recent.ContainsKey($recentKey)) {
            $recent = @($script:Recent[$recentKey])
        }
        $choices = @($pool | Where-Object { $recent -notcontains $_ })
        if ($choices.Count -eq 0) {
            $choices = $pool
        }
        $line = $choices | Get-Random
        $script:Recent[$recentKey] = @($recent + $line | Select-Object -Last 5)
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

    Write-RunLog '加载星星角色素材'
    $script:StarActionMap = @{
        idle = @('沈星回喵：嗨.gif', '沈星回喵：呆.gif', '沈星回喵：右摇摆.gif', '沈星回喵：左摇摆.gif')
        greeting = @('沈星回喵：嗨.gif', '沈星回喵：兔叽咪.gif')
        poke = @('沈星回喵：玩.gif', '沈星回喵：兔叽咪.gif', '沈星回喵：糟糕.gif')
        lunch = @('沈星回喵：饿了.gif', '沈星回喵：嚼嚼嚼.gif', '沈星回喵：吃撑了.gif')
        dinner = @('沈星回喵：饿了.gif', '沈星回喵：嚼嚼嚼.gif', '沈星回喵：吃撑了.gif')
        night = @('沈星回喵：打瞌睡.gif', '沈星回喵：躺平.gif')
        cheer = @('沈星回喵：热舞正面.gif', '沈星回喵：热舞转身.gif')
        feed = @('沈星回喵：饿了.gif', '沈星回喵：嚼嚼嚼.gif', '沈星回喵：吃撑了.gif')
        angry = @('沈星回喵：糟糕.gif')
        miss = @('沈星回喵：兔叽咪.gif', '沈星回喵：玩.gif')
        weather = @('沈星回喵：左摇摆.gif', '沈星回喵：右摇摆.gif')
    }
    $script:StarImages = @{}
    $starFiles = @($script:StarActionMap.Values | ForEach-Object { $_ } | Select-Object -Unique)
    foreach ($fileName in $starFiles) {
        $path = Join-Path $StarRoot $fileName
        if (-not (Test-Path -LiteralPath $path)) {
            throw "缺少星星动作素材：$path"
        }
        $script:StarImages[$fileName] = [System.Drawing.Image]::FromFile($path)
    }
    $dragImagePaths = @{
        left = Join-Path $StarRoot '沈星回喵：左拎喵喵.gif'
        right = Join-Path $StarRoot '沈星回喵：右拎喵喵.gif'
    }
    $script:DragImages = @{}
    foreach ($direction in @('left', 'right')) {
        $path = $dragImagePaths[$direction]
        if (-not (Test-Path -LiteralPath $path)) {
            throw "缺少拖拽动作素材：$path"
        }
        $script:DragImages[$direction] = [System.Drawing.Image]::FromFile($path)
    }
    Write-RunLog '拖拽动作素材已独立加载'

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
    $trayIconPath = Join-Path $AssetRoot 'icon_256.png'
    if (Test-Path -LiteralPath $trayIconPath) {
        $trayBitmap = New-Object System.Drawing.Bitmap $trayIconPath
        $trayHandle = $trayBitmap.GetHicon()
        $temporaryIcon = [System.Drawing.Icon]::FromHandle($trayHandle)
        $tray.Icon = $temporaryIcon.Clone()
        $temporaryIcon.Dispose()
        [void][NativeIconMethods]::DestroyIcon($trayHandle)
        $trayBitmap.Dispose()
    } else {
        $tray.Icon = [System.Drawing.SystemIcons]::Information
    }
    $tray.Text = '星星桌宠'
    $tray.Visible = $true

    $script:CurrentCharacter = 'star'
    $script:CurrentCharacterName = '星星'
    $script:PetState = 'normal'
    $script:StateAction = $null
    $script:StateUntil = $null
    $script:LastInteraction = Get-Date
    $script:ClickCount = 0
    $script:LastClickAt = [datetime]::MinValue
    $script:ClickThrough = $false
    $script:ThrowOrigin = $null
    $script:ThrowMotion = $null
    $script:ThrowTimer = $null
    $script:AngryTimer = $null
    $script:DragStartAt = $null
    $script:DragStartPos = $null
    $script:DragLastAt = $null
    $script:DragLastPos = $null

    function Resize-PetForImage {
        param([System.Drawing.Image]$Image)
        $centerX = $petForm.Left + [int]($petForm.Width / 2)
        $bottom = $petForm.Bottom
        $width = [Math]::Max(100, [int]($Image.Width * $petHeight / $Image.Height))
        $petForm.ClientSize = New-Object System.Drawing.Size($width, $petHeight)
        $petForm.Location = New-Object System.Drawing.Point(
            ($centerX - [int]($width / 2)),
            ($bottom - $petHeight)
        )
        Move-Bubble
    }

    function Set-CharacterAction {
        param([string]$Category)
        if ($script:CurrentCharacter -ne 'star') {
            return
        }
        if (-not $script:Dragging -and $script:AttachedEdge -in @('left', 'right')) {
            Set-DragImage -Direction $script:AttachedEdge
            return
        }
        if ($null -ne $script:StateAction -and $Category -ne $script:StateAction) {
            return
        }
        $files = $script:StarActionMap[$Category]
        if ($null -eq $files) {
            $files = $script:StarActionMap['idle']
        }
        $fileName = @($files) | Get-Random
        $image = $script:StarImages[$fileName]
        $script:DragDirection = $null
        $picture.Image = $image
        Resize-PetForImage -Image $image
    }

    function Test-IsHanging {
        return $script:CurrentCharacter -eq 'star' -and $script:AttachedEdge -in @('left', 'right')
    }

    function Update-StateMenu {
        if ($null -eq (Get-Variable stateMenu -ValueOnly -ErrorAction SilentlyContinue)) {
            return
        }
        $stateNames = @{
            normal = '普通'
            focus = '专注中'
            idle = '陪你发呆'
            celebrate = '庆祝'
            feed = '喂食中'
            angry = '生气中'
            thrown = '飞出去'
        }
        $name = $stateNames[$script:PetState]
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = $script:PetState
        }
        $stateMenu.Text = "状态：$name"
    }

    function Set-PetState {
        param(
            [ValidateSet('normal', 'focus', 'idle', 'celebrate', 'feed', 'angry', 'thrown')][string]$State,
            [string]$Action = 'idle',
            [Nullable[datetime]]$Until = $null
        )
        if (Test-IsHanging -or $script:PetState -eq 'thrown') {
            return $false
        }
        $script:PetState = $State
        $script:StateAction = if ($State -eq 'normal') { $null } else { $Action }
        $script:StateUntil = $Until
        $script:LastInteraction = Get-Date
        Set-CharacterAction -Category $Action
        Update-StateMenu
        Write-RunLog "桌宠状态：$State"
        return $true
    }

    function Set-ThrowSensitivity {
        param([int]$SpeedPx)
        $allowed = @($ThrowSensitivityLevels | ForEach-Object { $_.Speed })
        if ($allowed -notcontains $SpeedPx) {
            return
        }
        $script:ThrowSpeedPx = $SpeedPx
        foreach ($entry in $throwSensitivityItems.GetEnumerator()) {
            $entry.Value.Checked = ([int]$entry.Key -eq $SpeedPx)
        }
        Write-RunLog "触发门槛：$SpeedPx"
    }

    function Clamp-Number {
        param([double]$Value, [double]$Min, [double]$Max)
        if ($Value -lt $Min) { return $Min }
        if ($Value -gt $Max) { return $Max }
        return $Value
    }

    function Get-ThrowEaseOut {
        param([double]$Value)
        return 1.0 - [Math]::Pow(1.0 - $Value, 2)
    }

    function Get-ThrowEaseIn {
        param([double]$Value)
        return [Math]::Pow($Value, 2)
    }

    function Get-CubicPoint {
        param(
            [double[]]$P0,
            [double[]]$P1,
            [double[]]$P2,
            [double[]]$P3,
            [double]$T
        )
        $u = 1.0 - $T
        $uu = $u * $u
        $tt = $T * $T
        $uuu = $uu * $u
        $ttt = $tt * $T
        $x = ($uuu * $P0[0]) + (3 * $uu * $T * $P1[0]) + (3 * $u * $tt * $P2[0]) + ($ttt * $P3[0])
        $y = ($uuu * $P0[1]) + (3 * $uu * $T * $P1[1]) + (3 * $u * $tt * $P2[1]) + ($ttt * $P3[1])
        return ,@($x, $y)
    }

    function Set-PetCenter {
        param([double[]]$Center)
        $x = [int][Math]::Round($Center[0] - ($petForm.Width / 2))
        $y = [int][Math]::Round($Center[1] - ($petForm.Height / 2))
        $petForm.Location = New-Object System.Drawing.Point($x, $y)
        Move-Bubble
    }

    function Build-ThrowMotion {
        param(
            [ValidateSet('left', 'right')][string]$Direction,
            [System.Drawing.Point]$StartPos,
            [System.Drawing.Point]$ReleasePos,
            [double]$Speed
        )
        $screen = [System.Windows.Forms.Screen]::FromPoint($ReleasePos)
        $area = $screen.WorkingArea
        $origin = $petForm.Location
        $startCenter = @(
            [double]($origin.X + ($petForm.Width / 2)),
            [double]($origin.Y + ($petForm.Height / 2))
        )
        $deltaX = [double]($ReleasePos.X - $StartPos.X)
        $deltaY = [double]($ReleasePos.Y - $StartPos.Y)
        $dragLen = [Math]::Max([Math]::Sqrt(($deltaX * $deltaX) + ($deltaY * $deltaY)), 1.0)
        $force = Clamp-Number -Value (($Speed - $ThrowSpeedPx) / 1800.0) -Min 0.0 -Max 1.0
        $exitPad = $ThrowPadPx + [Math]::Min(130, 30 + ($dragLen * 0.06) + ($force * 90))
        $targetX = if ($Direction -eq 'left') { $area.Left - $petForm.Width - $exitPad } else { $area.Right + $petForm.Width + $exitPad }
        $targetY = Clamp-Number -Value ($startCenter[1] + ($deltaY * 0.36) - ($force * 35)) -Min ($area.Top + ($petForm.Height / 2)) -Max ($area.Bottom - ($petForm.Height / 2))
        $arc = 70 + ($force * 95) + [Math]::Min(64, $dragLen * 0.07)
        $dx = $targetX - $startCenter[0]
        $p0 = @($startCenter[0], $startCenter[1])
        $p3 = @($targetX, $targetY)
        $p1 = @(($startCenter[0] + ($dx * 0.26)), ($startCenter[1] - $arc))
        $p2 = @(($startCenter[0] + ($dx * 0.72)), ($targetY - ($arc * 0.48)))
        $launchMs = [int](Clamp-Number -Value (560 - ($force * 150) - ([Math]::Min(120, $dragLen * 0.05))) -Min 300 -Max 560)
        return @{
            Origin = @([double]$origin.X, [double]$origin.Y)
            StartCenter = $p0
            Target = $p3
            Control1 = $p1
            Control2 = $p2
            LaunchMs = $launchMs
            ReturnMs = [Math]::Max(($launchMs + 120), [int]($launchMs * 1.22))
            WaitUntil = (Get-Date).AddSeconds($ThrowWaitSec)
            Phase = 'launch'
            StartAt = Get-Date
        }
    }

    function Update-ThrowMotion {
        if ($null -eq $script:ThrowMotion) {
            if ($null -ne $script:ThrowTimer) {
                $script:ThrowTimer.Stop()
            }
            return
        }
        $motion = $script:ThrowMotion
        $now = Get-Date
        switch ($motion.Phase) {
            'launch' {
                $elapsed = (($now - $motion.StartAt).TotalMilliseconds)
                $linearT = [Math]::Max(0.0, [Math]::Min(1.0, ($elapsed / $motion.LaunchMs)))
                $t = Get-ThrowEaseOut -Value $linearT
                $point = Get-CubicPoint -P0 $motion.StartCenter -P1 $motion.Control1 -P2 $motion.Control2 -P3 $motion.Target -T $t
                Set-PetCenter -Center $point
                if ($linearT -ge 1.0) {
                    $motion.Phase = 'wait'
                    $motion.WaitUntil = (Get-Date).AddSeconds($ThrowWaitSec)
                    $script:ThrowMotion = $motion
                }
            }
            'wait' {
                if ($now -lt $motion.WaitUntil) {
                    return
                }
                $motion.Phase = 'return'
                $motion.StartAt = Get-Date
                $motion.ReturnStart = $motion.Target
                $motion.ReturnControl1 = $motion.Control2
                $motion.ReturnControl2 = $motion.Control1
                $script:ThrowMotion = $motion
                $petForm.Show()
            }
            'return' {
                $elapsed = (($now - $motion.StartAt).TotalMilliseconds)
                $linearT = [Math]::Max(0.0, [Math]::Min(1.0, ($elapsed / $motion.ReturnMs)))
                $t = Get-ThrowEaseIn -Value $linearT
                $point = Get-CubicPoint -P0 $motion.Target -P1 $motion.ReturnControl1 -P2 $motion.ReturnControl2 -P3 $motion.StartCenter -T $t
                Set-PetCenter -Center $point
                if ($linearT -ge 1.0) {
                    $script:ThrowMotion = $null
                    if ($null -ne $script:ThrowTimer) {
                        $script:ThrowTimer.Stop()
                    }
                    Finish-ThrowReturn
                }
            }
        }
    }

    function Stop-ThrowTimers {
        foreach ($timerName in @('ThrowTimer', 'AngryTimer')) {
            $timer = Get-Variable -Name $timerName -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $timer) {
                $timer.Stop()
                $timer.Dispose()
                Set-Variable -Scope Script -Name $timerName -Value $null
            }
        }
    }

    function Start-ThrowMotionTimer {
        Stop-ThrowTimers
        $script:ThrowTimer = New-Object System.Windows.Forms.Timer
        $script:ThrowTimer.Interval = $ThrowTickMs
        $script:ThrowTimer.Add_Tick({ Update-ThrowMotion })
        $script:ThrowTimer.Start()
    }

    function Start-AngryTimer {
        Stop-ThrowTimers
        $script:AngryTimer = New-Object System.Windows.Forms.Timer
        $script:AngryTimer.Interval = [Math]::Max(500, [int]($AngrySec * 1000))
        $script:AngryTimer.Add_Tick({
            Stop-ThrowTimers
            if ($script:PetState -eq 'angry') {
                Restore-NormalState
            }
        })
        $script:AngryTimer.Start()
    }

    function Throw-Pet {
        param(
            [ValidateSet('left', 'right')][string]$Direction,
            [System.Drawing.Point]$StartPos,
            [System.Drawing.Point]$ReleasePos,
            [double]$Speed
        )
        if ($null -eq $StartPos -or $null -eq $ReleasePos) {
            return $false
        }
        if (Test-IsHanging -or $script:PetState -in @('thrown', 'angry', 'feed')) {
            return $false
        }
        $script:ThrowOrigin = New-Object System.Drawing.Point($petForm.Left, $petForm.Top)
        $script:PetState = 'thrown'
        $script:StateAction = $null
        $script:StateUntil = (Get-Date).AddSeconds($ThrowWaitSec)
        $script:LastInteraction = Get-Date
        $script:ClickCount = 0
        $script:ThrowMotion = Build-ThrowMotion -Direction $Direction -StartPos $StartPos -ReleasePos $ReleasePos -Speed $Speed
        $script:ThrowMotion.Origin = @([double]$script:ThrowOrigin.X, [double]$script:ThrowOrigin.Y)
        $script:ThrowMotion.StartCenter = @(
            [double]($script:ThrowOrigin.X + ($petForm.Width / 2)),
            [double]($script:ThrowOrigin.Y + ($petForm.Height / 2))
        )
        $bubbleForm.Hide()
        Update-StateMenu
        Write-RunLog ("甩飞：{0}" -f $Direction)
        $petForm.Show()
        $petForm.BringToFront()
        Start-ThrowMotionTimer
        return $true
    }

    function Finish-ThrowReturn {
        if ($script:PetState -ne 'thrown') {
            return
        }
        if ($null -ne $script:ThrowOrigin) {
            $petForm.Location = $script:ThrowOrigin
        }
        if (-not $petForm.Visible) {
            $petForm.Show()
        }
        $script:PetState = 'angry'
        $script:StateAction = 'angry'
        $script:StateUntil = (Get-Date).AddSeconds($AngrySec)
        $script:LastInteraction = Get-Date
        Set-CharacterAction -Category 'angry'
        if ($null -ne $script:ThrowOrigin) {
            $petForm.Location = $script:ThrowOrigin
        }
        Show-Bubble -Text '哼，刚才那一下我记住了。'
        Update-StateMenu
        Write-RunLog '甩飞后返回：生气中'
        Start-AngryTimer
        $script:ThrowOrigin = $null
    }

    function Restore-NormalState {
        if (Test-IsHanging) {
            return
        }
        Stop-ThrowTimers
        $script:ThrowOrigin = $null
        $script:ThrowMotion = $null
        $script:DragLastAt = $null
        $script:DragLastPos = $null
        [void](Set-PetState -State 'normal' -Action 'idle')
    }

    function Set-PetOpacity {
        param([ValidateSet(100, 80, 60, 40)][int]$Percent)
        $petForm.Opacity = $Percent / 100.0
        foreach ($item in $opacityItems.Values) {
            $item.Checked = [int]$item.Tag -eq $Percent
        }
        Write-RunLog "透明度：$Percent%"
    }

    function Set-PetClickThrough {
        param([bool]$Enabled)
        $handle = $petForm.Handle
        $style = [NativeIconMethods]::GetWindowLong($handle, -20)
        if ($Enabled) {
            $style = $style -bor 0x20
        } else {
            $style = $style -band (-bnot 0x20)
        }
        [void][NativeIconMethods]::SetWindowLong($handle, -20, $style)
        $script:ClickThrough = $Enabled
        $clickThroughItem.Checked = $Enabled
        Write-RunLog "鼠标穿透：$Enabled"
    }

    function Feed-Pet {
        if (Test-IsHanging -or $script:PetState -in @('thrown', 'angry', 'feed')) {
            return $false
        }
        if (-not (Set-PetState -State 'feed' -Action 'feed' -Until (Get-Date).AddSeconds($FeedSec))) {
            return $false
        }
        Speak-Category 'feed'
        return $true
    }

    function Set-DragImage {
        param([ValidateSet('left', 'right')][string]$Direction)
        if ($script:CurrentCharacter -ne 'star') {
            return
        }
        if ($script:DragDirection -eq $Direction) {
            return
        }
        $image = $script:DragImages[$Direction]
        if ($null -ne $image) {
            $picture.Image = $image
            $script:DragDirection = $Direction
            Resize-PetForImage -Image $image
        }
    }

    function Get-ScreenWorkingArea {
        $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
        return $screen.WorkingArea
    }

    function Snap-PetToEdge {
        param([System.Drawing.Rectangle]$Area)
        $nearLeft = $petForm.Left -le ($Area.Left + 32)
        $nearRight = $petForm.Right -ge ($Area.Right - 32)
        if (-not $nearLeft -and -not $nearRight) {
            return $false
        }
        $petCenterX = $petForm.Left + [int]($petForm.Width / 2)
        if ($nearLeft -and (-not $nearRight -or $petCenterX -le ($Area.Left + [int]($Area.Width / 2)))) {
            Set-DragImage -Direction 'left'
            $petForm.Left = $Area.Left
            $script:AttachedEdge = 'left'
        } else {
            Set-DragImage -Direction 'right'
            $petForm.Left = $Area.Right - $petForm.Width
            $script:AttachedEdge = 'right'
        }
        $petForm.Top = [Math]::Max($Area.Top, [Math]::Min($petForm.Top, $Area.Bottom - $petForm.Height))
        Move-Bubble
        return $true
    }

    function Get-ClickCategory {
        if ($script:PetState -eq 'angry') {
            return 'angry'
        }
        if ($script:PetState -eq 'feed') {
            return 'feed'
        }
        if ($script:CurrentCharacter -eq 'star' -and $script:AttachedEdge -in @('left', 'right')) {
            return 'hanging'
        }
        return 'poke'
    }

    function Get-DragCategory {
        if ($script:CurrentCharacter -ne 'star') {
            return $null
        }
        if ($script:DragDirection -eq 'left') {
            return 'drag_left'
        }
        if ($script:DragDirection -eq 'right') {
            return 'drag_right'
        }
        return $null
    }

    function Set-Character {
        param([ValidateSet('star', 'lishen')][string]$Character)
        $script:CurrentCharacter = $Character
        $script:AttachedEdge = $null
        $script:DragDirection = $null
        $script:PetState = 'normal'
        $script:StateAction = $null
        $script:StateUntil = $null
        $script:ThrowOrigin = $null
        $script:ThrowMotion = $null
        $script:DragLastAt = $null
        $script:DragLastPos = $null
        Stop-ThrowTimers
        if ($Character -eq 'star') {
            $script:CurrentCharacterName = '星星'
            $animationTimer.Stop()
            Set-CharacterAction -Category 'idle'
        } else {
            $script:CurrentCharacterName = '黎深'
            $picture.Image = $script:Frames[0]
            Resize-PetForImage -Image $script:Frames[0]
            $script:AnimationIndex = 0
            $animationTimer.Interval = $animationDurations[0]
            $animationTimer.Start()
        }
        $feedItem.Enabled = $Character -eq 'star'
        $throwSensitivityMenu.Enabled = $Character -eq 'star'
        $tray.Text = "$($script:CurrentCharacterName)桌宠"
        if ($null -ne (Get-Variable starItem -ValueOnly -ErrorAction SilentlyContinue)) {
            $starItem.Checked = $Character -eq 'star'
            $lishenItem.Checked = $Character -eq 'lishen'
        }
        Write-RunLog "切换角色：$($script:CurrentCharacterName)"
        Update-StateMenu
    }

    function Speak-Category {
        param(
            [string]$Category,
            [switch]$Notify
        )
        if ($script:PetState -eq 'thrown') {
            return
        }
        if ($script:PetState -eq 'feed') {
            $Category = 'feed'
        }
        if ($script:PetState -eq 'angry' -and $Category -ne 'angry') {
            $Category = 'angry'
        }
        $line = Get-RandomLine -Category $Category
        if ([string]::IsNullOrWhiteSpace($line)) {
            return
        }
        if (-not $petForm.Visible) {
            $petForm.Show()
        }
        Set-CharacterAction -Category $Category
        Show-Bubble -Text $line
        if ($Notify -and $script:NotifyToo) {
            $tray.BalloonTipTitle = $script:CurrentCharacterName
            $tray.BalloonTipText = $line
            $tray.ShowBalloonTip(6000)
        }
    }

    function Speak-Now {
        $hour = (Get-Date).Hour
        if ($script:PetState -eq 'feed') {
            Speak-Category 'feed'
        } elseif ($hour -eq 11) {
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
    $characterMenu = New-Object System.Windows.Forms.ToolStripMenuItem('切换角色')
    $starItem = $characterMenu.DropDownItems.Add('星星（默认）')
    $lishenItem = $characterMenu.DropDownItems.Add('黎深')
    [void]$menu.Items.Add($characterMenu)
    [void]$menu.Items.Add('-')
    $sayItem = $menu.Items.Add('让角色说句话')
    $stateMenu = New-Object System.Windows.Forms.ToolStripMenuItem('状态：普通')
    $focusItem = $stateMenu.DropDownItems.Add('开始专注（25 分钟）')
    $completeItem = $stateMenu.DropDownItems.Add('完成一件事')
    $idleItem = $stateMenu.DropDownItems.Add('陪我发呆')
    $feedItem = $stateMenu.DropDownItems.Add('喂食')
    [void]$stateMenu.DropDownItems.Add('-')
    $normalItem = $stateMenu.DropDownItems.Add('恢复普通状态')
    [void]$menu.Items.Add($stateMenu)
    $opacityMenu = New-Object System.Windows.Forms.ToolStripMenuItem('透明度')
    $opacityItems = @{}
    foreach ($percent in @(100, 80, 60, 40)) {
        $item = $opacityMenu.DropDownItems.Add("$percent%")
        $item.Tag = $percent
        $opacityItems[$percent] = $item
    }
    $opacityItems[100].Checked = $true
    [void]$menu.Items.Add($opacityMenu)
    $throwSensitivityMenu = New-Object System.Windows.Forms.ToolStripMenuItem('触发门槛')
    $throwSensitivityItems = @{}
    foreach ($itemDef in $ThrowSensitivityLevels) {
        $item = $throwSensitivityMenu.DropDownItems.Add($itemDef.Label)
        $item.Tag = $itemDef.Speed
        $throwSensitivityItems[[int]$itemDef.Speed] = $item
    }
    $throwSensitivityItems[$ThrowSpeedPx].Checked = $true
    [void]$menu.Items.Add($throwSensitivityMenu)
    $clickThroughItem = $menu.Items.Add('鼠标穿透（从托盘关闭）')
    $clickThroughItem.CheckOnClick = $true
    $toggleItem = $menu.Items.Add('显示 / 隐藏桌宠')
    $reminderItem = $menu.Items.Add('暂停提醒')
    [void]$menu.Items.Add('-')
    $restartItem = $menu.Items.Add('重启桌宠')
    $quitItem = $menu.Items.Add('退出')
    $restartLauncher = Join-Path $PSScriptRoot 'launch-native.vbs'
    $restartWscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $tray.ContextMenuStrip = $menu
    $picture.ContextMenuStrip = $menu
    $script:RemindersOn = $true
    Write-RunLog ("功能菜单：{0}" -f $sayItem.Text)
    Write-RunLog ("重启入口：Menu={0}; Launcher={1}" -f ($null -ne $restartItem), (Test-Path -LiteralPath $restartLauncher))
    Write-RunLog ("托盘状态：Visible={0}; Menu={1}; PetMenu={2}" -f $tray.Visible, ($null -ne $tray.ContextMenuStrip), ($null -ne $picture.ContextMenuStrip))

    $starItem.Checked = $true
    $starItem.Add_Click({ Set-Character -Character 'star' })
    $lishenItem.Add_Click({ Set-Character -Character 'lishen' })
    $sayItem.Add_Click({ Speak-Now })
    $focusItem.Add_Click({
        if (Set-PetState -State 'focus' -Action 'idle' -Until (Get-Date).AddMinutes(25)) {
            Show-Bubble -Text '开始专注。我会安静陪着你。'
        }
    })
    $completeItem.Add_Click({
        if (Set-PetState -State 'celebrate' -Action 'cheer' -Until (Get-Date).AddSeconds(12)) {
            Show-Bubble -Text '完成得很好。这次值得庆祝一下。'
        }
    })
    $idleItem.Add_Click({
        if (Set-PetState -State 'idle' -Action 'idle') {
            Show-Bubble -Text '好，我们一起安静待一会儿。'
        }
    })
    $feedItem.Add_Click({
        if (Feed-Pet) {
            Show-Bubble -Text '先吃点东西，再继续忙。'
        }
    })
    $normalItem.Add_Click({ Restore-NormalState })
    foreach ($entry in $opacityItems.GetEnumerator()) {
        $entry.Value.Add_Click({
            param($sender, $eventArgs)
            Set-PetOpacity -Percent ([int]$sender.Tag)
        })
    }
    foreach ($entry in $throwSensitivityItems.GetEnumerator()) {
        $entry.Value.Add_Click({
            param($sender, $eventArgs)
            Set-ThrowSensitivity -SpeedPx ([int]$sender.Tag)
        })
    }
    $clickThroughItem.Add_Click({ Set-PetClickThrough -Enabled $clickThroughItem.Checked })
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
    $restartItem.Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $restartLauncher)) {
                throw "缺少无窗口启动器：$restartLauncher"
            }
            Start-Process -FilePath $restartWscript -ArgumentList ('"' + $restartLauncher + '"') -WorkingDirectory $ProjectRoot
            $tray.Visible = $false
            [System.Windows.Forms.Application]::Exit()
        } catch {
            Write-ErrorLog -Record $_
            [System.Windows.Forms.MessageBox]::Show(
                "重启失败：$($_.Exception.Message)",
                '星星桌宠',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
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
    $script:DragDirection = $null
    $script:AttachedEdge = $null
    $script:LastCursorX = 0
    $script:DragOffset = New-Object System.Drawing.Point(0, 0)
    $picture.Add_MouseDown({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:LastInteraction = Get-Date
            $script:Dragging = $true
            $script:Moved = $false
            $script:DragOffset = $eventArgs.Location
            $script:LastCursorX = [System.Windows.Forms.Cursor]::Position.X
            $script:DragStartAt = Get-Date
            $script:DragStartPos = [System.Windows.Forms.Cursor]::Position
            $script:DragLastAt = $script:DragStartAt
            $script:DragLastPos = $script:DragStartPos
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
                $script:AttachedEdge = $null
            }
            $petForm.Location = $next
            if ($script:CurrentCharacter -eq 'star' -and $cursor.X -ne $script:LastCursorX) {
                Set-DragImage -Direction $(if ($cursor.X -lt $script:LastCursorX) { 'left' } else { 'right' })
                $script:LastCursorX = $cursor.X
            }
            $script:DragLastAt = Get-Date
            $script:DragLastPos = $cursor
            Move-Bubble
        }
    })
    $picture.Add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:Dragging = $false
            if (-not $script:Moved) {
                $now = Get-Date
                if (($now - $script:LastClickAt).TotalSeconds -le 4) {
                    $script:ClickCount++
                } else {
                    $script:ClickCount = 1
                }
                $script:LastClickAt = $now
                if (-not (Test-IsHanging) -and $script:ClickCount -ge 5) {
                    [void](Set-PetState -State 'celebrate' -Action 'cheer' -Until $now.AddSeconds(10))
                    Show-Bubble -Text '今天很有精神嘛。奖励一段舞。'
                    $script:ClickCount = 0
                    $script:DragStartAt = $null
                    $script:DragStartPos = $null
                    $script:DragLastAt = $null
                    $script:DragLastPos = $null
                    return
                }
                Speak-Category -Category (Get-ClickCategory)
            } elseif ($script:CurrentCharacter -eq 'star') {
                $releasePos = [System.Windows.Forms.Cursor]::Position
                if ($null -ne $script:DragStartAt -and $null -ne $script:DragStartPos) {
                    $dragStartPos = $script:DragStartPos
                    $samplePos = if ($null -ne $script:DragLastPos) { $script:DragLastPos } else { $dragStartPos }
                    $sampleAt = if ($null -ne $script:DragLastAt) { $script:DragLastAt } else { $script:DragStartAt }
                    $elapsed = [Math]::Max(0.001, ((Get-Date) - $sampleAt).TotalSeconds)
                    $dx = $releasePos.X - $dragStartPos.X
                    $dy = $releasePos.Y - $dragStartPos.Y
                    $recentDx = $releasePos.X - $samplePos.X
                    $recentDy = $releasePos.Y - $samplePos.Y
                    $dragDistance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
                    $recentDistance = [Math]::Sqrt(($recentDx * $recentDx) + ($recentDy * $recentDy))
                    $averageSpeed = $dragDistance / [Math]::Max(0.001, ((Get-Date) - $script:DragStartAt).TotalSeconds)
                    $recentSpeed = $recentDistance / $elapsed
                    $speed = [Math]::Max($recentSpeed, ($averageSpeed * 0.7))
                    if (-not (Test-IsHanging) -and $speed -ge $ThrowSpeedPx -and $dragDistance -ge 160 -and $recentDistance -ge 40) {
                        $direction = if ($dx -lt 0) { 'left' } else { 'right' }
                        $script:DragStartAt = $null
                        $script:DragStartPos = $null
                        $script:DragLastAt = $null
                        $script:DragLastPos = $null
                        if (Throw-Pet -Direction $direction -StartPos $dragStartPos -ReleasePos $releasePos -Speed $speed) {
                            return
                        }
                    }
                }
                $dragCategory = Get-DragCategory
                $snapped = Snap-PetToEdge -Area (Get-ScreenWorkingArea)
                if (-not $snapped) {
                    $script:AttachedEdge = $null
                    $script:DragDirection = $null
                    $resumeAction = if ($null -ne $script:StateAction) { $script:StateAction } else { 'idle' }
                    Set-CharacterAction -Category $resumeAction
                }
                if ($null -ne $dragCategory) {
                    Speak-Category -Category $dragCategory
                }
            }
        }
    })

    $animationSequence = @(0, 0, 1, 3, 2, 4, 5, 0)
    $animationDurations = @(1400, 200, 500, 700, 900, 700, 600, 400)
    $script:AnimationIndex = 0
    $animationTimer = New-Object System.Windows.Forms.Timer
    $animationTimer.Interval = $animationDurations[0]
    $animationTimer.Add_Tick({
        if ($script:CurrentCharacter -ne 'lishen') {
            return
        }
        $script:AnimationIndex = ($script:AnimationIndex + 1) % $animationSequence.Count
        $picture.Image = $script:Frames[$animationSequence[$script:AnimationIndex]]
        $animationTimer.Interval = $animationDurations[$script:AnimationIndex]
    })
    $animationTimer.Start()
    Set-Character -Character 'star'

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
            Speak-Category -Category 'lunch' -Notify
            return
        }
        $key = "$day-dinner"
        if ($now.Hour -eq 18 -and $now.Minute -lt 30 -and -not $script:Fired.ContainsKey($key)) {
            $script:Fired[$key] = $true
            Speak-Category -Category 'dinner' -Notify
            return
        }
        $key = "$day-night"
        if ($now.Hour -eq 23 -and $now.Minute -ge 30 -and -not $script:Fired.ContainsKey($key)) {
            $script:Fired[$key] = $true
            Speak-Category -Category 'night' -Notify
            return
        }
        if ($now -ge $script:NextHourly) {
            $script:NextHourly = Get-NextHourlyTime
            if ($now.Hour -ge 7 -and $now.Hour -le 23) {
                Speak-Category -Category (@('daily', 'miss', 'cheer', 'weather') | Get-Random) -Notify
            }
        }
    })
    $scheduleTimer.Start()

    $stateTimer = New-Object System.Windows.Forms.Timer
    $stateTimer.Interval = 30000
    $stateTimer.Add_Tick({
        if (Test-IsHanging) {
            return
        }
        if ($script:PetState -in @('thrown', 'angry')) {
            return
        }
        $now = Get-Date
        if ($null -ne $script:StateUntil -and $now -ge $script:StateUntil) {
            if ($script:PetState -eq 'focus') {
                [void](Set-PetState -State 'celebrate' -Action 'cheer' -Until $now.AddSeconds(12))
                Show-Bubble -Text '专注结束。完成得很好。'
            } else {
                Restore-NormalState
            }
            return
        }
        if ($script:PetState -ne 'normal') {
            return
        }
        $idleMinutes = ($now - $script:LastInteraction).TotalMinutes
        if ($idleMinutes -ge 20) {
            Set-CharacterAction -Category 'night'
        } elseif ($idleMinutes -ge 10) {
            Set-CharacterAction -Category 'idle'
        }
    })
    $stateTimer.Start()

    $greetingTimer = New-Object System.Windows.Forms.Timer
    $greetingTimer.Interval = 1500
    $greetingTimer.Add_Tick({
        $greetingTimer.Stop()
        Speak-Category 'greeting'
    })

    $petForm.Show()
    $greetingTimer.Start()

    if ($IsSelfTest) {
        Set-Character -Character 'lishen'
        $lishenLine = Get-RandomLine -Category 'greeting'
        $lishenGreetingPool = @($script:CharacterCategories['lishen'].PSObject.Properties['greeting'].Value)
        $lishenLineSeparated = $lishenGreetingPool -contains $lishenLine
        Set-Character -Character 'star'
        $starLine = Get-RandomLine -Category 'greeting'
        $starGreetingPool = @($script:CharacterCategories['star'].PSObject.Properties['greeting'].Value)
        $starLineSeparated = $starGreetingPool -contains $starLine -and $lishenGreetingPool -notcontains $starLine
        Write-RunLog ("角色台词分离：Lishen={0}; Star={1}" -f $lishenLineSeparated, $starLineSeparated)
        $selfTestArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $petForm.Left = $selfTestArea.Left - [int]($petForm.Width / 2)
        $leftSnapped = Snap-PetToEdge -Area $selfTestArea
        $leftAttached = $leftSnapped -and $script:AttachedEdge -eq 'left' -and $petForm.Left -eq $selfTestArea.Left
        $petForm.Left = $selfTestArea.Right - [int]($petForm.Width / 2)
        $rightSnapped = Snap-PetToEdge -Area $selfTestArea
        $rightAttached = $rightSnapped -and $script:AttachedEdge -eq 'right' -and $petForm.Right -eq $selfTestArea.Right
        Write-RunLog ("贴边悬挂：Left={0}; Right={1}" -f $leftAttached, $rightAttached)
        Set-CharacterAction -Category 'idle'
        $hangingPreserved = $script:AttachedEdge -eq 'right' -and $picture.Image -eq $script:DragImages['right'] -and $petForm.Right -eq $selfTestArea.Right
        Write-RunLog ("悬挂状态保持：{0}" -f $hangingPreserved)
        $hangingLine = Get-RandomLine -Category 'hanging'
        Write-RunLog ("悬挂台词库：{0}" -f (-not [string]::IsNullOrWhiteSpace($hangingLine)))
        Write-RunLog ("悬挂点击分类：{0}" -f (Get-ClickCategory))
        Write-RunLog ("拖拽点击分类：{0}" -f (Get-DragCategory))
        Write-RunLog ("重启入口自检：{0}" -f ($null -ne $restartItem -and (Test-Path -LiteralPath $restartLauncher)))
        Write-RunLog ("状态入口：{0}" -f ($stateMenu.DropDownItems.Count -eq 6))
        Set-PetOpacity -Percent 80
        Set-PetOpacity -Percent 100
        Set-PetClickThrough -Enabled $true
        $clickThroughEnabled = $script:ClickThrough -and $clickThroughItem.Checked
        Set-PetClickThrough -Enabled $false
        Write-RunLog ("显示控制：Opacity={0}; ClickThrough={1}" -f ([int]($petForm.Opacity * 100)), ($clickThroughEnabled -and -not $script:ClickThrough))
        Write-RunLog ("系统通知默认关闭：{0}" -f (-not $script:NotifyToo))
        Write-RunLog ("生气台词库：{0}" -f (-not [string]::IsNullOrWhiteSpace((Get-RandomLine -Category 'angry'))))
        Write-RunLog ("甩飞功能：{0}" -f ($null -ne (Get-Command Throw-Pet -CommandType Function -ErrorAction SilentlyContinue)))
        $script:AttachedEdge = $null
        $script:DragDirection = $null
        [void](Set-PetState -State 'focus' -Action 'idle' -Until (Get-Date).AddMinutes(25))
        $focusImage = $picture.Image
        Set-CharacterAction -Category 'cheer'
        Write-RunLog ("状态动作锁：{0}" -f ($script:PetState -eq 'focus' -and $picture.Image -eq $focusImage))
        Restore-NormalState
        Set-DragImage -Direction 'right'
        $script:AttachedEdge = 'right'
        $stateBeforeHang = $script:PetState
        [void](Set-PetState -State 'focus' -Action 'idle' -Until (Get-Date).AddMinutes(25))
        Write-RunLog ("悬挂状态锁：{0}" -f ($script:PetState -eq $stateBeforeHang -and $picture.Image -eq $script:DragImages['right']))
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
        if ($null -ne $tray.Icon) {
            $tray.Icon.Dispose()
        }
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
    if ($null -ne (Get-Variable StarImages -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        foreach ($image in $script:StarImages.Values) {
            $image.Dispose()
        }
    }
    if ($null -ne (Get-Variable DragImages -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        foreach ($image in $script:DragImages.Values) {
            $image.Dispose()
        }
    }
}
