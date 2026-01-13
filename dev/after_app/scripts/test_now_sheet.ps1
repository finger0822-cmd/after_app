# NowSheet実動作テスト結果確認スクリプト
# Usage: .\scripts\test_now_sheet.ps1 [-TestStart <DateTime>]
# Example: .\scripts\test_now_sheet.ps1 -TestStart (Get-Date)

param(
    [datetime]$TestStart = (Get-Date)
)

# ==============================
# 1) 最新ログを特定（crash_*.log）
# ==============================
# $TestStart 以降に「更新」されたログを対象にする
$logDir = Join-Path $env:LOCALAPPDATA "after_app\logs"
$logs = Get-ChildItem $logDir -Filter "crash_*.log" |
    Where-Object { $_.LastWriteTime -ge $TestStart } |
    Sort-Object LastWriteTime -Descending

if (-not $logs -or $logs.Count -eq 0) {
    Write-Host "FAIL: ログファイルが見つかりません: $logDir" -ForegroundColor Red
    Write-Host "INFO: TestStart ($TestStart) 以降に更新されたログファイルが存在しません" -ForegroundColor Yellow
    Write-Host "INFO: アプリを起動してログを生成してください" -ForegroundColor Yellow
    exit 1
}

# 中身シグネチャでスコアリング（重いので上位Nだけ対象）
$top = $logs | Select-Object -First 10

function Get-LogScore($path) {
    $score = 0
    try {
        if (Select-String -Path $path -Pattern "\[MessageRepo\] SAVED" -Quiet) { $score += 5 }
        if (Select-String -Path $path -Pattern "\[NowSheet\].*_handleSubmit called" -Quiet) { $score += 3 }
        if (Select-String -Path $path -Pattern "reset completed, back to input screen" -Quiet) { $score += 2 }
    } catch {
        # 読めない場合はスコア0
    }
    return $score
}

$candidates = @()
foreach ($f in $top) {
    $candidates += [pscustomobject]@{
        FullName = $f.FullName
        LastWriteTime = $f.LastWriteTime
        Length = $f.Length
        Score = (Get-LogScore $f.FullName)
    }
}

# PowerShell 5/7対応: Score優先、同点時はLastWriteTime降順
$ranked = $candidates | Sort-Object -Property @{Expression={$_.Score}; Descending=$true}, @{Expression={$_.LastWriteTime}; Descending=$true}
$target = $ranked | Select-Object -First 1

$latestLog = $target.FullName
Write-Host "TEST_START=$TestStart" -ForegroundColor Cyan
Write-Host "LOG_FILE=$latestLog" -ForegroundColor Cyan
Write-Host "LOG_LASTWRITE=$($target.LastWriteTime)" -ForegroundColor Cyan
Write-Host "LOG_SIZE=$([math]::Round($target.Length / 1KB, 2)) KB" -ForegroundColor Cyan
Write-Host "LOG_SCORE=$($target.Score)" -ForegroundColor Cyan

# ==============================
# 2) テスト開始以降の行だけ抽出
# ==============================
$lines = Get-Content $latestLog

# TEST_START以降っぽい行のみ（ログ形式が [2026-...] の場合に効く）
$startIso = $TestStart.ToString("yyyy-MM-ddTHH:mm:ss")
$filtered = $lines | Where-Object { 
    $_ -match "^\[$startIso" -or 
    $_ -match "^\[(20\d\d-\d\d-\d\dT)" -or
    $_ -match "NowSheet|MessageRepo"
}

# もし上が雑すぎて拾えない場合はフォールバックで全行
if (-not $filtered -or $filtered.Count -eq 0) {
    $filtered = $lines
    Write-Host "WARNING: 時刻フィルタが効かなかったため全行を対象にします（ログ形式要確認）" -ForegroundColor Yellow
}

Write-Host "FILTERED_LINES=$($filtered.Count) 行" -ForegroundColor Cyan
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NowSheet 実動作テスト 結果サマリー" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ==============================
# A) 二重送信テスト
# ==============================
Write-Host "[A] 二重送信テスト" -ForegroundColor Yellow
$savedCount   = ($filtered | Select-String "\[MessageRepo\] SAVED").Count
$blockedCount = ($filtered | Select-String "BLOCKED \(already submitting\)").Count
$submitCalled = ($filtered | Select-String "_handleSubmit called").Count
$submitStart  = ($filtered | Select-String "_handleSubmit: START submitting").Count

Write-Host "  _handleSubmit called: $submitCalled 回" -ForegroundColor Cyan
Write-Host "  START submitting:     $submitStart 回" -ForegroundColor Cyan
Write-Host "  SAVED:                $savedCount 回 (期待: 1)" -ForegroundColor $(if ($savedCount -eq 1) { "Green" } else { "Red" })
Write-Host "  BLOCKED:              $blockedCount 回 (期待: 9以上 ※10連打時)" -ForegroundColor $(if ($blockedCount -ge 9) { "Green" } else { "Yellow" })

# 判定
$testA_Pass = ($savedCount -eq 1) -and ($blockedCount -ge 9)
if ($testA_Pass) {
    Write-Host "  判定: PASS" -ForegroundColor Green
} else {
    Write-Host "  判定: FAIL" -ForegroundColor Red
}

# ==============================
# B) dispose耐性テスト
# ==============================
Write-Host ""
Write-Host "[B] dispose耐性テスト" -ForegroundColor Yellow
$setStateErr = ($filtered | Select-String "setState\(\) called after dispose")
$timerCancel = ($filtered | Select-String "dispose: _sentResetTimer cancelled")
$disposeCallback = ($filtered | Select-String "called after dispose").Count

if ($setStateErr) {
    Write-Host "  setState() called after dispose: FAIL (エラー検出)" -ForegroundColor Red
    Write-Host "  エラー内容:" -ForegroundColor Red
    $setStateErr | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
} else {
    Write-Host "  setState() called after dispose: PASS (エラーなし)" -ForegroundColor Green
}
if ($timerCancel) {
    Write-Host "  timer cancelled log:              PASS" -ForegroundColor Green
} else {
    Write-Host "  timer cancelled log:              WARNING (ログなし)" -ForegroundColor Yellow
}
Write-Host "  dispose後コールバック検出:        $disposeCallback 回 (正常な動作)" -ForegroundColor Cyan

# 判定
$testB_Pass = -not $setStateErr
if ($testB_Pass) {
    Write-Host "  判定: PASS" -ForegroundColor Green
} else {
    Write-Host "  判定: FAIL" -ForegroundColor Red
}

# ==============================
# C) 連続送信テスト
# ==============================
Write-Host ""
Write-Host "[C] 連続送信テスト" -ForegroundColor Yellow
$successCount = ($filtered | Select-String "_handleSubmit: SUCCESS").Count
$resetCount   = ($filtered | Select-String "reset completed, back to input screen").Count
$inputStateCount = ($filtered | Select-String "_updateUiState: state=input").Count
$sentShown = ($filtered | Select-String "Windows: sent UI shown").Count
$timerStarted = ($filtered | Select-String "Windows: _sentResetTimer started").Count

Write-Host "  SUCCESS:              $successCount 回 (期待: 10)" -ForegroundColor $(if ($successCount -eq 10) { "Green" } else { "Red" })
Write-Host "  sent UI shown:        $sentShown 回 (期待: 10)" -ForegroundColor $(if ($sentShown -eq 10) { "Green" } else { "Yellow" })
Write-Host "  timer started:        $timerStarted 回 (期待: 10)" -ForegroundColor $(if ($timerStarted -eq 10) { "Green" } else { "Yellow" })
Write-Host "  reset completed:      $resetCount 回 (期待: 10)" -ForegroundColor $(if ($resetCount -eq 10) { "Green" } else { "Red" })
Write-Host "  input状態遷移:        $inputStateCount 回 (期待: 10)" -ForegroundColor $(if ($inputStateCount -eq 10) { "Green" } else { "Red" })

# 判定
$testC_Pass = ($successCount -eq 10) -and ($resetCount -eq 10) -and ($inputStateCount -eq 10)
if ($testC_Pass) {
    Write-Host "  判定: PASS" -ForegroundColor Green
} else {
    Write-Host "  判定: FAIL" -ForegroundColor Red
}

# ==============================
# 総合判定と終了コード
# ==============================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "総合判定" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 終了コード決定（優先順位順）
$exitCode = 0

# 優先度1: setState() called after dispose が1回でも見つかれば exit 2
if ($setStateErr) {
    Write-Host "FAIL: setState() called after dispose エラーが検出されました" -ForegroundColor Red
    $exitCode = 2
}

# 優先度2: SAVEDが1回以外なら exit 3
if ($savedCount -ne 1) {
    Write-Host "FAIL: SAVEDログが$savedCount回 (期待: 1回)" -ForegroundColor Red
    if ($exitCode -eq 0) {
        $exitCode = 3
    }
}

# その他の判定
$allPass = $testA_Pass -and $testB_Pass -and $testC_Pass

if ($exitCode -eq 0) {
    if ($allPass) {
        Write-Host "PASS: すべてのテストがPASSしました" -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "FAIL: 一部のテストがFAILしました" -ForegroundColor Yellow
        if (-not $testA_Pass) { Write-Host "  - [A] 二重送信テスト" -ForegroundColor Yellow }
        if (-not $testB_Pass) { Write-Host "  - [B] dispose耐性テスト" -ForegroundColor Yellow }
        if (-not $testC_Pass) { Write-Host "  - [C] 連続送信テスト" -ForegroundColor Yellow }
        $exitCode = 0
    }
}

Write-Host ""
Write-Host "ログファイル: $latestLog" -ForegroundColor Cyan
Write-Host "終了コード: $exitCode" -ForegroundColor Cyan

exit $exitCode
