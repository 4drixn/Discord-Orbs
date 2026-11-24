@echo off
chcp 65001 >nul 2>&1
title Discord Orbs ^>:D
set "SCRIPT_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = (Get-Content -LiteralPath $env:SCRIPT_PATH -Raw -Encoding UTF8) -replace '(?s).*::PS_START::\r?\n',''; Invoke-Command -ScriptBlock ([ScriptBlock]::Create($s))"
pause
exit /b
::PS_START::
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$API_BASE = 'https://discord.com/api/v9'
$POLL_INTERVAL = 60
$HEARTBEAT_INTERVAL = 20
$SUPPORTED_TASKS = @('WATCH_VIDEO','PLAY_ON_DESKTOP','STREAM_ON_DESKTOP','PLAY_ACTIVITY','WATCH_VIDEO_ON_MOBILE','ACHIEVEMENT_IN_ACTIVITY')
$FALLBACK_BUILD = 504649
$ESC = [char]27
$PINK = "$ESC[38;2;255;105;180m"
$RESET = "$ESC[0m"

try {
    $code = '[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int mode); [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int handle);'
    $type = Add-Type -MemberDefinition $code -Name 'Console' -Namespace 'Win32' -PassThru
    $handle = $type::GetStdHandle(-11)
    $type::SetConsoleMode($handle, 7) | Out-Null
} catch {}

function Write-Log($msg, $level='info') {
    $ts = Get-Date -Format 'HH:mm:ss'
    $pad = ' ' * 20
    switch ($level) {
        'info'  { Write-Host "`r$ts [INFO] $msg$pad" -ForegroundColor Cyan }
        'ok'    { Write-Host "`r$ts [ OK ] $msg$pad" -ForegroundColor Green }
        'warn'  { Write-Host "`r$ts [WARN] $msg$pad" -ForegroundColor Yellow }
        'error' { Write-Host "`r$ts [ERR ] $msg$pad" -ForegroundColor Red }
        'debug' { Write-Host "`r$ts [DBG ] $msg$pad" -ForegroundColor DarkGray }
        default { Write-Host "`r$ts [$level] $msg$pad" }
    }
}

function Show-Banner {
    Clear-Host
    Write-Host "`n$PINK╔══════════════════════════════════════════════════════════════╗"
    Write-Host "║                Discord Obs >:D by 92tif                      ║"
    Write-Host "║                https://github.com/4drixn                     ║"
    Write-Host "║           Auto scan · Auto accept · Auto complete            ║"
    Write-Host "║                https://github.com/4drixn                     ║"
    Write-Host "╚══════════════════════════════════════════════════════════════╝$RESET`n"
}

function Draw-ProgressBar($label, $current, $total, $width=30) {
    if ($total -le 0) { $total = 1 }
    if ($current -gt $total) { $current = $total }
    $percent = [math]::Round(($current / $total) * 100)
    $filled = [math]::Floor(($current / $total) * $width)
    $empty = $width - $filled
    $bar = ('█' * $filled) + ('-' * $empty)
    Write-Host "`r    [$bar] $percent% ($([math]::Round($current))/${total}s) - $label   " -NoNewline -ForegroundColor Gray
}

function Get-Prop($d, [string[]]$keys) {
    try {
        if ($null -eq $d) { return $null }
        foreach ($k in $keys) {
            try {
                if ($d.PSObject -and $d.PSObject.Properties -and $d.PSObject.Properties.Name -contains $k) { return $d.$k }
            } catch {}
            try {
                if ($d -is [hashtable] -and $d.ContainsKey($k)) { return $d[$k] }
            } catch {}
        }
    } catch {}
    return $null
}

function Get-BuildNumber {
    Write-Log 'Fetching Discord build number...' 'info'
    try {
        $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
        $r = Invoke-WebRequest -Uri 'https://discord.com/app' -Headers @{'User-Agent'=$ua} -TimeoutSec 15 -UseBasicParsing
        if ($r.StatusCode -ne 200) { return $FALLBACK_BUILD }
        $hashes = [regex]::Matches($r.Content, '/assets/([a-f0-9]+)\.js') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        if (-not $hashes) { return $FALLBACK_BUILD }
        $last = $hashes | Select-Object -Last 5
        foreach ($h in $last) {
            try {
                $js = Invoke-WebRequest -Uri "https://discord.com/assets/$h.js" -Headers @{'User-Agent'=$ua} -TimeoutSec 15 -UseBasicParsing
                $m = [regex]::Match($js.Content, 'buildNumber["\s:]+["\s]*(\d{5,7})')
                if ($m.Success) { return [int]$m.Groups[1].Value }
            } catch { continue }
        }
        return $FALLBACK_BUILD
    } catch {
        return $FALLBACK_BUILD
    }
}

function New-SuperProperties($build) {
    $obj = @{
        os = 'Windows'
        browser = 'Discord Client'
        release_channel = 'stable'
        client_version = '1.0.9175'
        os_version = '10.0.26100'
        os_arch = 'x64'
        app_arch = 'x64'
        system_locale = 'en-US'
        browser_user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9175 Chrome/128.0.6613.186 Electron/32.2.7 Safari/537.36'
        browser_version = '32.2.7'
        client_build_number = $build
        native_build_number = 59498
        client_event_source = $null
    }
    $json = $obj | ConvertTo-Json -Compress
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

function New-ApiHeaders($token, $superProps) {
    return @{
        'Authorization' = $token
        'Content-Type' = 'application/json'
        'Accept' = '*/*'
        'Accept-Language' = 'en-US,en;q=0.9'
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9175 Chrome/128.0.6613.186 Electron/32.2.7 Safari/537.36'
        'X-Super-Properties' = $superProps
        'X-Discord-Locale' = 'en-US'
        'X-Discord-Timezone' = 'Asia/Ho_Chi_Minh'
        'Origin' = 'https://discord.com'
        'Referer' = 'https://discord.com/channels/@me'
    }
}

function Invoke-Discord($method, $path, $headers, $body=$null) {
    $url = "$API_BASE$path"
    $params = @{ Uri = $url; Headers = $headers; Method = $method; ContentType = 'application/json'; TimeoutSec = 20 }
    if ($body -ne $null) { $params.Body = ($body | ConvertTo-Json -Compress -Depth 10) }
    try {
        return Invoke-RestMethod @params
    } catch {
        $statusCode = $null
        try {
            $resp = $_.Exception.Response
            if ($resp -ne $null) {
                if ($resp.StatusCode -ne $null) { $statusCode = [int]$resp.StatusCode }
                elseif ($resp.Status -ne $null) { $statusCode = [int]$resp.Status }
            }
            if (-not $statusCode -and $_.Exception.StatusCode) { $statusCode = [int]$_.Exception.StatusCode }
        } catch {}
        if ($statusCode -eq 429) {
            $retry = 6
            try {
                $txt = $null
                try { $reader = New-Object IO.StreamReader($resp.GetResponseStream()); $txt = $reader.ReadToEnd(); $reader.Close() } catch {
                    try { $txt = $_.ErrorDetails.Message } catch {}
                }
                if ($txt) {
                    $j = $txt | ConvertFrom-Json -ErrorAction Stop
                    if ($j.retry_after) { $retry = [math]::Ceiling([double]$j.retry_after) + 1 }
                }
            } catch {}
            if ($retry -lt 1) { $retry = 6 }
            if ($retry -gt 120) { $retry = 120 }
            Write-Log "Rate limited (429) - waiting ${retry}s..." 'warn'
            Start-Sleep -Seconds $retry
            return 'RETRY'
        }
        if (-not $statusCode) {
            $msg = 'No network response'
            try { $msg = $_.Exception.Message } catch {}
            Write-Log "Network error on ${method} ${path}: $msg (will retry)" 'warn'
            Start-Sleep -Seconds 5
            return 'RETRY'
        }
        throw
    }
}

function Get-TaskConfig($quest) { return Get-Prop $quest.config @('taskConfig','task_config','taskConfigV2','task_config_v2') }
function Get-QuestName($quest) {
    $msgs = $quest.config.messages
    $n = Get-Prop $msgs @('questName','quest_name')
    if ($n) { return $n.Trim() }
    $g = Get-Prop $msgs @('gameTitle','game_title')
    if ($g) { return $g.Trim() }
    if ($quest.config.application -and $quest.config.application.name) { return $quest.config.application.name }
    return "Quest#$($quest.id)"
}
function Get-ExpiresAt($quest) { return Get-Prop $quest.config @('expiresAt','expires_at') }
function Get-UserStatus($quest) {
    $us = Get-Prop $quest @('userStatus','user_status')
    if ($us) { return $us } else { return @{} }
}
function Test-Completable($quest) {
    $exp = Get-ExpiresAt $quest
    if ($exp) {
        try {
            $dt = [DateTime]::Parse($exp).ToUniversalTime()
            if ($dt -le [DateTime]::UtcNow) { return $false }
        } catch {}
    }
    $tc = Get-TaskConfig $quest
    if (-not $tc -or -not (Get-Prop $tc @('tasks'))) { return $false }
    $tasks = Get-Prop $tc @('tasks')
    foreach ($t in $SUPPORTED_TASKS) {
        $v = Get-Prop $tasks @($t)
        if ($v -ne $null) { return $true }
    }
    return $false
}
function Test-Enrolled($quest) {
    $us = Get-UserStatus $quest
    $e = Get-Prop $us @('enrolledAt','enrolled_at')
    return [bool]$e
}
function Test-Completed($quest) {
    $us = Get-UserStatus $quest
    $c = Get-Prop $us @('completedAt','completed_at')
    return [bool]$c
}
function Get-TaskType($quest) {
    $tc = Get-TaskConfig $quest
    if (-not $tc) { return $null }
    $tasks = Get-Prop $tc @('tasks')
    if (-not $tasks) { return $null }
    foreach ($t in $SUPPORTED_TASKS) {
        if ((Get-Prop $tasks @($t)) -ne $null) { return $t }
    }
    return $null
}
function Get-SecondsNeeded($quest) {
    $tc = Get-TaskConfig $quest
    $tt = Get-TaskType $quest
    if (-not $tc -or -not $tt) { return 0 }
    $tasks = Get-Prop $tc @('tasks')
    $o = Get-Prop $tasks @($tt)
    if ($o -and (Get-Prop $o @('target')) -ne $null) { return [int](Get-Prop $o @('target')) }
    return 0
}
function Get-SecondsDone($quest) {
    $tt = Get-TaskType $quest
    if (-not $tt) { return 0 }
    $us = Get-UserStatus $quest
    $prog = Get-Prop $us @('progress')
    if (-not $prog) { return 0 }
    $node = Get-Prop $prog @($tt)
    if (-not $node) { return 0 }
    $v = Get-Prop $node @('value')
    if ($v -eq $null) { return 0 }
    return [double]$v
}
function Get-EnrolledAt($quest) {
    $us = Get-UserStatus $quest
    return Get-Prop $us @('enrolledAt','enrolled_at')
}
function Get-Quests($headers) {
    $attempts = 0
    while ($attempts -lt 5) {
        $attempts++
        try {
            $data = Invoke-Discord 'GET' '/quests/@me' $headers
            if ($data -eq 'RETRY') { continue }
            if ($data -eq $null) { Start-Sleep -Seconds 5; continue }
            if ($data.quests) { return @($data.quests) }
            if ($data -is [array]) { return $data }
            return @()
        } catch {
            $msg = 'unknown'
            try { $msg = $_.Exception.Message } catch {}
            Write-Log "Failed to fetch quests (attempt $attempts/5): $msg" 'warn'
            Start-Sleep -Seconds 5
        }
    }
    return @()
}
function Enroll-Quest($quest, $headers) {
    $name = Get-QuestName $quest
    $qid = $quest.id
    $body = @{
        location = 11
        is_targeted = $false
        metadata_raw = $null
        metadata_sealed = $null
        traffic_metadata_raw = Get-Prop $quest @('traffic_metadata_raw')
        traffic_metadata_sealed = Get-Prop $quest @('traffic_metadata_sealed')
    }
    for ($a=1; $a -le 3; $a++) {
        try {
            $r = Invoke-Discord 'POST' "/quests/$qid/enroll" $headers $body
            if ($r -eq 'RETRY') { continue }
            Write-Log "Enrolled: $name" 'ok'
            return $true
        } catch {
            $m = 'error'
            try { $m = $_.Exception.Message } catch {}
            if ($a -ge 3) { Write-Log "Enroll failed ($name): $m" 'warn'; return $false }
            try { Start-Sleep -Seconds 3 } catch {}
        }
    }
    return $false
}
function Complete-Video($quest, $headers) {
    try {
    $name = Get-QuestName $quest
    $qid = $quest.id
    if (-not $qid) { Write-Log 'Quest without id, skipped (video)' 'warn'; return $false }
    $need = Get-SecondsNeeded $quest
    $done = Get-SecondsDone $quest
    if ($need -le 0) { Write-Log "Video task with no time required: $name (skipped)" 'warn'; return $false }
    if ($done -ge $need) { Write-Log "Already completed: $name" 'ok'; return $true }
    $enrolledTs = 0
    try {
        $enrolledStr = Get-EnrolledAt $quest
        if ($enrolledStr) { $enrolledTs = ([DateTime]::Parse($enrolledStr).ToUniversalTime() - [DateTime]'1970-01-01').TotalSeconds }
        else { $enrolledTs = ([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds }
    } catch { $enrolledTs = ([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds }
    Write-Log "Video Task: $name" 'info'
    $maxFuture = 10; $speed = 7
    $iters = 0; $maxIters = ($need + 120) * 2
    if ($maxIters -lt 120) { $maxIters = 120 }
    while ($done -lt $need) {
        $iters++
        if ($iters -gt $maxIters) { Write-Log "Timeout on video $name, will retry on next scan" 'warn'; break }
        try {
            $nowTs = ([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds
            $maxAllowed = ($nowTs - $enrolledTs) + $maxFuture
            $diff = $maxAllowed - $done
            $timestamp = $done + $speed
            if ($diff -ge $speed) {
                try {
                    $ts = [math]::Min($need, $timestamp + (Get-Random -Minimum 0.0 -Maximum 1.0))
                    $r = Invoke-Discord 'POST' "/quests/$qid/video-progress" $headers @{ timestamp = $ts }
                    if ($r -eq 'RETRY') { Start-Sleep -Seconds 2; continue }
                    if ($r -ne $null -and (Get-Prop $r @('completed_at','completedAt'))) {
                        Write-Host ""
                        Write-Log "Completed: $name" 'ok'
                        return $true
                    }
                    if ($r -ne $null) { $done = [math]::Min($need, $timestamp) }
                } catch {
                    $m = 'error'; try { $m = $_.Exception.Message } catch {}
                    Write-Log "video-progress failed ($name): $m" 'warn'
                    Start-Sleep -Seconds 3
                }
            }
            Draw-ProgressBar $name $done $need
            if ($timestamp -ge $need) { break }
        } catch {
            $m = 'error'; try { $m = $_.Exception.Message } catch {}
            Write-Log "Internal video error ($name): $m" 'warn'
        }
        try { Start-Sleep -Seconds 1 } catch {}
    }
    try {
        $fin = Invoke-Discord 'POST' "/quests/$qid/video-progress" $headers @{ timestamp = $need }
        if ($fin -ne 'RETRY') { Write-Host ""; Write-Log "Completed: $name" 'ok'; return $true }
        else { Write-Host ""; Write-Log "Progress sent, check on next scan: $name" 'info'; return $false }
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        Write-Log "Video close ($name): $m" 'warn'
        return $false
    }
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        try { Write-Log "Complete-Video general failure: $m" 'error' } catch {}
        return $false
    }
}
function Complete-Heartbeat($quest, $headers, $mode) {
    $skey = $null
    try {
    $name = Get-QuestName $quest
    $qid = $quest.id
    if (-not $qid) { Write-Log 'Quest without id, skipped (heartbeat)' 'warn'; return $false }
    $tt = Get-TaskType $quest
    $need = Get-SecondsNeeded $quest
    $done = Get-SecondsDone $quest
    if ($need -le 0) { Write-Log "Heartbeat with no time required: $name (skipped)" 'warn'; return $false }
    if ($done -ge $need) { Write-Log "Already completed: $name" 'ok'; return $true }
    $remain = [math]::Max(0, $need - $done)
    Write-Log "$mode Task: $name (~$([math]::Floor($remain/60)) min remaining)" 'info'
    if ($mode -eq 'Activity') { $skey = 'call:0:1' } else { $streamPid = Get-Random -Minimum 1000 -Maximum 30000; $skey = "call:0:$streamPid" }
    $iters = 0; $maxIters = [math]::Ceiling($need / $HEARTBEAT_INTERVAL) + 30
    if ($maxIters -lt 30) { $maxIters = 30 }
    $shown = $done
    Draw-ProgressBar $name $shown $need
    while ($done -lt $need) {
        $iters++
        if ($iters -gt $maxIters) { Write-Log "Timeout on $mode $name, will retry on next scan" 'warn'; break }
        try {
            $r = Invoke-Discord 'POST' "/quests/$qid/heartbeat" $headers @{ stream_key = $skey; terminal = $false }
            if ($r -eq 'RETRY') {
                for ($k = 0; $k -lt 3; $k++) {
                    if ($shown -lt $need) { $shown = [math]::Min($need, $shown + 1); $cap = $done + $HEARTBEAT_INTERVAL; if ($shown -gt $cap) { $shown = $cap } }
                    Draw-ProgressBar $name $shown $need
                    try { Start-Sleep -Seconds 1 } catch {}
                }
                continue
            }
            if ($r -ne $null) {
                $prog = Get-Prop $r @('progress')
                if ($prog) {
                    $key = $tt
                    if ($mode -eq 'Activity') { $key = 'PLAY_ACTIVITY' }
                    $node = Get-Prop $prog @($key)
                    if ($node) {
                        $v = Get-Prop $node @('value')
                        if ($v -ne $null) { $done = [double]$v }
                    }
                }
                if ($done -gt $shown) { $shown = $done }
                Draw-ProgressBar $name $shown $need
                if ((Get-Prop $r @('completed_at','completedAt')) -or ($done -ge $need)) {
                    Write-Host ""
                    Write-Log "Completed: $name" 'ok'
                    return $true
                }
            } else {
                Draw-ProgressBar $name $shown $need
            }
        } catch {
            $m = 'error'; try { $m = $_.Exception.Message } catch {}
            Write-Log "heartbeat failed ($name): $m" 'warn'
            Draw-ProgressBar $name $shown $need
        }
        try {
            for ($i = 0; $i -lt $HEARTBEAT_INTERVAL; $i++) {
                if ($done -ge $need) { break }
                if ($shown -lt $need) { $shown = [math]::Min($need, $shown + 1); $cap = $done + $HEARTBEAT_INTERVAL; if ($shown -gt $cap) { $shown = $cap } }
                Draw-ProgressBar $name $shown $need
                Start-Sleep -Seconds 1
            }
        } catch {}
    }
    if ($done -ge $need) { return $true }
    return $false
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        try { Write-Log "Complete-Heartbeat general failure: $m" 'error' } catch {}
        return $false
    } finally {
        if ($skey -and $qid) {
            try {
                $end = Invoke-Discord 'POST' "/quests/$qid/heartbeat" $headers @{ stream_key = $skey; terminal = $true }
                if ($done -ge $need) { try { [void]$end } catch {} }
                elseif ($end -ne 'RETRY') { Write-Host ""; Write-Log "Progress sent, check on next scan: $(Get-QuestName $quest)" 'info' }
                else { Write-Host ""; Write-Log "Final heartbeat pending, check on next scan" 'info' }
            } catch {
                $m = 'error'; try { $m = $_.Exception.Message } catch {}
                try { Write-Host ""; Write-Log "Heartbeat close: $m" 'warn' } catch {}
            }
        }
    }
}
function Get-AchievementAppId($quest) {
    try {
        $tc = Get-TaskConfig $quest
        $tasks = Get-Prop $tc @('tasks')
        $ao = Get-Prop $tasks @('ACHIEVEMENT_IN_ACTIVITY')
        if ($ao -ne $null) {
            $apps = Get-Prop $ao @('applications')
            if ($apps -ne $null) {
                $first = $null
                try { $first = @($apps)[0] } catch {}
                if ($first -ne $null) {
                    $aid = Get-Prop $first @('id','application_id')
                    if ($aid) { return [string]$aid }
                }
            }
        }
        if ($quest.config.application -and $quest.config.application.id) { return [string]$quest.config.application.id }
    } catch {}
    return $null
}
function Invoke-AchievementBypass($quest, $headers) {
    try {
    $qid = $quest.id
    $qname = Get-QuestName $quest
    $appId = Get-AchievementAppId $quest
    if (-not $appId -or $appId -notmatch '^\d+$') { Write-Log "Achievement bypass has no application id: $qname" 'warn'; return $false }
    $target = Get-SecondsNeeded $quest
    if ($target -le 0) { $target = 1 }
    $preIds = @{}
    try {
        $toks = Invoke-Discord 'GET' '/oauth2/tokens' $headers
        if ($toks -ne 'RETRY' -and $toks -ne $null) {
            foreach ($tk in @($toks)) {
                try {
                    $aid = $null
                    if ($tk.application -and $tk.application.id) { $aid = [string]$tk.application.id }
                    if ($aid -eq $appId) { $preIds[[string]$tk.id] = $true }
                } catch {}
            }
        }
    } catch {}
    Write-Log "Achievement bypass authorize: $qname" 'info'
    $authRes = $null
    try {
        $authRes = Invoke-Discord 'POST' "/oauth2/authorize?response_type=code&client_id=$appId&scope=identify%20applications.commands%20applications.entitlements" $headers @{ permissions = '0'; authorize = $true; integration_type = 1; location_context = @{ guild_id = '10000'; channel_id = '10000'; channel_type = 10000 } }
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        Write-Log "Achievement authorize failed ($qname): $m" 'warn'
        return $false
    }
    if ($authRes -eq 'RETRY' -or $authRes -eq $null) { Write-Log "Achievement authorize rate limited: $qname" 'warn'; return $false }
    $loc = Get-Prop $authRes @('location')
    $authCode = $null
    try {
        if ($loc) {
            $mm = [regex]::Match([string]$loc, '[?&]code=([^&]+)')
            if ($mm.Success) { $authCode = $mm.Groups[1].Value }
        }
    } catch {}
    if (-not $authCode) { Write-Log "Achievement authorize returned no code: $qname" 'warn'; return $false }
    $ticket = $null
    try {
        $tickRes = Invoke-Discord 'POST' "/applications/$appId/proxy-tickets" $headers @{}
        if ($tickRes -eq 'RETRY') { Write-Log "Achievement proxy ticket rate limited: $qname" 'warn'; return $false }
        $ticket = Get-Prop $tickRes @('ticket')
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        Write-Log "Achievement proxy ticket denied ($qname): $m" 'warn'
        return $false
    }
    if (-not $ticket) { Write-Log "Achievement proxy ticket missing: $qname" 'warn'; return $false }
    $ref = "https://$appId.discordsays.com/?instance_id=example-cl-instance&platform=desktop&discord_proxy_ticket=" + [uri]::EscapeDataString([string]$ticket)
    $dsToken = $null
    try {
        $dsAuth = Invoke-RestMethod -Uri "https://$appId.discordsays.com/.proxy/acf/authorize" -Method 'POST' -ContentType 'application/json' -Headers @{'X-Auth-Token' = ''; 'X-Discord-Quest-ID' = "$qid"; 'Referer' = $ref} -Body (@{ code = $authCode } | ConvertTo-Json -Compress -Depth 5) -TimeoutSec 20
        $dsToken = Get-Prop $dsAuth @('token')
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        Write-Log "Achievement backend authorize failed ($qname): $m" 'warn'
        return $false
    }
    if (-not $dsToken) { Write-Log "Achievement backend returned no token: $qname" 'warn'; return $false }
    try {
        $pbody = (@{ quest_id = "$qid"; progress = [int]$target } | ConvertTo-Json -Compress -Depth 5)
        [void](Invoke-RestMethod -Uri "https://$appId.discordsays.com/.proxy/acf/quest/progress" -Method 'POST' -ContentType 'application/json' -Headers @{'X-Auth-Token' = "$dsToken"; 'X-Discord-Quest-ID' = "$qid"; 'Referer' = $ref} -Body $pbody -TimeoutSec 20)
    } catch {
        $m = 'error'
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
            else { $m = $_.Exception.Message }
        } catch {}
        Write-Log "Achievement backend progress failed ($qname): $m" 'warn'
        return $false
    }
    try { Start-Sleep -Seconds 4 } catch {}
    $ok = $false
    for ($v = 1; $v -le 4; $v++) {
        try {
            $fresh = Get-Quests $headers
            foreach ($fq in @($fresh)) {
                try {
                    if ("$($fq.id)" -eq "$qid") {
                        if (Test-Completed $fq) { $ok = $true }
                        else {
                            $pp = Get-Prop (Get-UserStatus $fq) @('progress')
                            $vv = $null
                            if ($pp) {
                                $nn = Get-Prop $pp @('ACHIEVEMENT_IN_ACTIVITY')
                                if ($nn) { $vv = Get-Prop $nn @('value') }
                            }
                            if ($vv -ne $null -and [double]$vv -ge [double]$target) { $ok = $true }
                        }
                        break
                    }
                } catch {}
            }
        } catch {}
        if ($ok) { break }
        try { Start-Sleep -Seconds 5 } catch {}
    }
    try {
        $after = Invoke-Discord 'GET' '/oauth2/tokens' $headers
        if ($after -ne 'RETRY' -and $after -ne $null) {
            foreach ($tk in @($after)) {
                try {
                    $aid = $null
                    if ($tk.application -and $tk.application.id) { $aid = [string]$tk.application.id }
                    $tid = [string]$tk.id
                    if ($aid -eq $appId -and -not $preIds.ContainsKey($tid)) {
                        try { [void](Invoke-Discord 'DELETE' "/oauth2/tokens/$tid" $headers) } catch {}
                    }
                } catch {}
            }
        }
    } catch {}
    if ($ok) { Write-Host ""; Write-Log "Completed: $qname" 'ok'; return $true }
    Write-Log "Achievement bypass reported no completion: $qname" 'warn'
    return $false
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        try { Write-Log "Achievement bypass failed: $m" 'error' } catch {}
        return $false
    }
}
function Complete-Achievement($quest, $headers) {
    $skey = 'call:0:1'
    try {
    $name = Get-QuestName $quest
    $qid = $quest.id
    if (-not $qid) { Write-Log 'Quest without id, skipped (achievement)' 'warn'; return $false }
    $need = Get-SecondsNeeded $quest
    $done = Get-SecondsDone $quest
    if ($need -gt 0 -and $done -ge $need) { Write-Log "Already completed: $name" 'ok'; return $true }
    Write-Log "Achievement Task: $name" 'info'
    $probed = $false
    for ($p = 1; $p -le 3; $p++) {
        try {
            $r = Invoke-Discord 'POST' "/quests/$qid/heartbeat" $headers @{ stream_key = $skey; terminal = $false }
            if ($r -eq 'RETRY') { try { Start-Sleep -Seconds 3 } catch {}; continue }
            if ($r -ne $null) {
                if ((Get-Prop $r @('completed_at','completedAt'))) {
                    Write-Host ""
                    Write-Log "Completed: $name" 'ok'
                    return $true
                }
                $prog = Get-Prop $r @('progress')
                if ($prog) {
                    $node = Get-Prop $prog @('ACHIEVEMENT_IN_ACTIVITY')
                    if ($node) {
                        $v = Get-Prop $node @('value')
                        if ($v -ne $null) { $done = [double]$v; $probed = $true }
                    }
                }
                if ($probed) { break }
            }
        } catch {
            $m = 'error'; try { $m = $_.Exception.Message } catch {}
            if ($m -match '403' -or $m -match '401') { break }
            try { Start-Sleep -Seconds 3 } catch {}
        }
    }
    if (-not $probed) {
        Write-Log "Trying achievement bypass: $name" 'info'
        try {
            if (Invoke-AchievementBypass $quest $headers) { return $true }
        } catch {}
        Write-Log "Achievement quest needs manual play: $name" 'warn'
        return $false
    }
    if ($need -le 0) { $need = [math]::Max(1, $done) }
    if ($done -ge $need) { Write-Host ""; Write-Log "Completed: $name" 'ok'; return $true }
    $iters = 0; $maxIters = [math]::Ceiling($need / $HEARTBEAT_INTERVAL) + 30
    if ($maxIters -lt 30) { $maxIters = 30 }
    $shown = $done
    Draw-ProgressBar $name $shown $need
    while ($done -lt $need) {
        $iters++
        if ($iters -gt $maxIters) { Write-Log "Timeout on Achievement $name, will retry on next scan" 'warn'; break }
        try {
            $r = Invoke-Discord 'POST' "/quests/$qid/heartbeat" $headers @{ stream_key = $skey; terminal = $false }
            if ($r -eq 'RETRY') {
                for ($k = 0; $k -lt 3; $k++) {
                    if ($shown -lt $need) { $shown = [math]::Min($need, $shown + 1); $cap = $done + $HEARTBEAT_INTERVAL; if ($shown -gt $cap) { $shown = $cap } }
                    Draw-ProgressBar $name $shown $need
                    try { Start-Sleep -Seconds 1 } catch {}
                }
                continue
            }
            if ($r -ne $null) {
                $prog = Get-Prop $r @('progress')
                if ($prog) {
                    $node = Get-Prop $prog @('ACHIEVEMENT_IN_ACTIVITY')
                    if ($node) {
                        $v = Get-Prop $node @('value')
                        if ($v -ne $null) { $done = [double]$v }
                    }
                }
                if ($done -gt $shown) { $shown = $done }
                Draw-ProgressBar $name $shown $need
                if ((Get-Prop $r @('completed_at','completedAt')) -or ($done -ge $need)) {
                    Write-Host ""
                    Write-Log "Completed: $name" 'ok'
                    return $true
                }
            } else {
                Draw-ProgressBar $name $shown $need
            }
        } catch {
            $m = 'error'; try { $m = $_.Exception.Message } catch {}
            Write-Log "heartbeat failed ($name): $m" 'warn'
            Draw-ProgressBar $name $shown $need
        }
        try {
            for ($i = 0; $i -lt $HEARTBEAT_INTERVAL; $i++) {
                if ($done -ge $need) { break }
                if ($shown -lt $need) { $shown = [math]::Min($need, $shown + 1); $cap = $done + $HEARTBEAT_INTERVAL; if ($shown -gt $cap) { $shown = $cap } }
                Draw-ProgressBar $name $shown $need
                Start-Sleep -Seconds 1
            }
        } catch {}
    }
    if ($done -ge $need) { return $true }
    return $false
    } catch {
        $m = 'error'; try { $m = $_.Exception.Message } catch {}
        try { Write-Log "Complete-Achievement general failure: $m" 'error' } catch {}
        return $false
    } finally {
        if ($skey -and $qid) {
            try {
                $end = Invoke-Discord 'POST' "/quests/$qid/heartbeat" $headers @{ stream_key = $skey; terminal = $true }
                if ($done -ge $need) { try { [void]$end } catch {} }
                elseif ($end -ne 'RETRY') { Write-Host ""; Write-Log "Progress sent, check on next scan: $(Get-QuestName $quest)" 'info' }
                else { Write-Host ""; Write-Log "Final heartbeat pending, check on next scan" 'info' }
            } catch {}
        }
    }
}

Show-Banner

$token = $null
$headers = $null
while ($true) {
    try {
        $token = $null
        if (Test-Path '.token') {
            try { $token = (Get-Content '.token' -Raw -ErrorAction Stop).Trim().Trim('"') } catch {}
        }
        if (-not $token) {
            $token = Read-Host 'Enter Discord Token'
            if ($token) { $token = $token.Trim().Trim('"') }
        }
        if (-not $token) { Write-Log 'No token entered, try again' 'warn'; try { Start-Sleep -Seconds 2 } catch {}; continue }
        $build = Get-BuildNumber
        $headers = New-ApiHeaders $token (New-SuperProperties $build)
        $me = Invoke-Discord 'GET' '/users/@me' $headers
        if ($me -eq 'RETRY') { $me = Invoke-Discord 'GET' '/users/@me' $headers }
        if ($me -eq $null -or $me -eq 'RETRY' -or -not $me.username) { Write-Log 'Login retry, waiting...' 'warn'; try { Start-Sleep -Seconds 5 } catch {}; continue }
        Write-Log "Logged in as: $($me.username)" 'ok'
        break
    } catch {
        $m = 'error'
        try { $m = $_.Exception.Message } catch {}
        Write-Log "Invalid Token: $m" 'error'
        try { Remove-Item -LiteralPath '.token' -Force -ErrorAction SilentlyContinue } catch {}
        try { Start-Sleep -Seconds 3 } catch {}
    }
}

$completedIds = @{}
$cycle = 0

while ($true) {
    try {
        $cycle++
        Write-Log "---- Scan #$cycle ----" 'info'
        $quests = Get-Quests $headers
        if ($quests -eq $null) { $quests = @() }
        if ($quests.Count -gt 0) {
            $unaccepted = @($quests | Where-Object { (-not (Test-Enrolled $_)) -and (-not (Test-Completed $_)) -and (Test-Completable $_) })
            foreach ($q in $unaccepted) {
                try { Enroll-Quest $q $headers | Out-Null } catch {
                    $m = 'error'
                    try { $m = $_.Exception.Message } catch {}
                    Write-Log "Error during scan: $m" 'error'
                }
                try { Start-Sleep -Seconds 3 } catch {}
            }
            if ($unaccepted.Count -gt 0) { $quests = Get-Quests $headers; if ($quests -eq $null) { $quests = @() } }
            $expCount = 0; $unsupCount = 0
            foreach ($sq in $quests) {
                try {
                    if (Test-Completed $sq) { continue }
                    if (Test-Completable $sq) { continue }
                    $exp = Get-ExpiresAt $sq
                    $isExp = $false
                    try {
                        if ($exp) {
                            $edt = [DateTime]::Parse($exp).ToUniversalTime()
                            if ($edt -le [DateTime]::UtcNow) { $isExp = $true }
                        }
                    } catch {}
                    if ($isExp) { $expCount++; continue }
                    $unsupCount++
                } catch {}
            }
            if (($expCount -gt 0) -or ($unsupCount -gt 0)) {
                Write-Log "Skipped $expCount expired, $unsupCount unsupported" 'debug'
            }
            $actionable = @($quests | Where-Object { (Test-Enrolled $_) -and (-not (Test-Completed $_)) -and (Test-Completable $_) -and (-not $completedIds.ContainsKey($_.id)) })
            foreach ($q in $actionable) {
                try {
                    $tt = Get-TaskType $q
                    $doneOk = $false
                    if ($tt -in @('WATCH_VIDEO','WATCH_VIDEO_ON_MOBILE')) { $doneOk = Complete-Video $q $headers }
                    elseif ($tt -in @('PLAY_ON_DESKTOP','STREAM_ON_DESKTOP')) { $doneOk = Complete-Heartbeat $q $headers 'Game' }
                    elseif ($tt -eq 'PLAY_ACTIVITY') { $doneOk = Complete-Heartbeat $q $headers 'Activity' }
                    elseif ($tt -eq 'ACHIEVEMENT_IN_ACTIVITY') { $doneOk = Complete-Achievement $q $headers }
                    else { Write-Log "Unsupported task: $tt" 'warn' }
                    if ($doneOk) { $completedIds[$q.id] = $true }
                } catch {
                    $m = 'error'
                    try { $m = $_.Exception.Message } catch {}
                    Write-Log "Error during scan: $m" 'error'
                }
            }
            if (($unaccepted.Count -eq 0) -and ($actionable.Count -eq 0)) {
                Write-Log "All quests done, waiting for new quests..." 'ok'
            }
        } else {
            Write-Log "No quests available, waiting..." 'info'
        }
    } catch {
        $m = 'error'
        try { $m = $_.Exception.Message } catch {}
        try { $m = "$_`n$($_.ScriptStackTrace)" } catch {}
        Write-Log "Error during scan: $m" 'error'
    }
    try { Start-Sleep -Seconds $POLL_INTERVAL } catch {}
}
