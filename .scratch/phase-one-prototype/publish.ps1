$ErrorActionPreference = 'Stop'
$taskGh = 'C:/Users/DELL/AppData/Local/CodexTools/github-cli/bin/gh.exe'
$taskRepo = 'Czp14408/game'
$taskRoot = $PSScriptRoot
$taskRecordPath = Join-Path $taskRoot 'publication.json'

function Invoke-TaskGh {
    param([string[]]$Arguments)
    $taskResult = & $taskGh @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('GitHub operation failed: ' + ($Arguments[0..([Math]::Min(2, $Arguments.Length - 1))] -join ' ')) }
    return ($taskResult -join "`n")
}

function Save-TaskRecord {
    $script:taskRecord | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $taskRecordPath -Encoding utf8
}

Invoke-TaskGh -Arguments @('auth', 'status') | Write-Output
Invoke-TaskGh -Arguments @('repo', 'view', $taskRepo, '--json', 'nameWithOwner,viewerPermission') | Write-Output
$taskLabels = Invoke-TaskGh -Arguments @('label', 'list', '-R', $taskRepo, '--limit', '100', '--json', 'name') | ConvertFrom-Json
if ('ready-for-agent' -notin $taskLabels.name) {
    Invoke-TaskGh -Arguments @('label', 'create', 'ready-for-agent', '-R', $taskRepo, '--color', '0E8A16', '--description', 'Fully specified, ready for an agent') | Write-Output
}

if (Test-Path -LiteralPath $taskRecordPath) {
    $script:taskRecord = Get-Content -LiteralPath $taskRecordPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
} else {
    $script:taskRecord = @{ repository = $taskRepo; parent = $null; tickets = @{} }
}

if (-not $taskRecord.parent) {
    $taskSpec = Get-Content -LiteralPath (Join-Path $taskRoot 'spec.md') -Raw -Encoding utf8
    $taskSpec = $taskSpec -replace '状态：完整草案；需求已确认，测试边界与任务拆分待本轮审阅。目标发布到 Czp14408/game 的 GitHub Issues，标记 ready-for-agent；当前尚未发布。', '状态：需求、测试边界与任务拆分已获用户确认。第一阶段规格；实现与试玩验证尚未完成。'
    $taskSpecBody = Join-Path $taskRoot 'spec-published-body.md'
    Set-Content -LiteralPath $taskSpecBody -Value $taskSpec -Encoding utf8
    $taskUrl = Invoke-TaskGh -Arguments @('issue', 'create', '-R', $taskRepo, '--title', '第一阶段武道世界可玩原型：规格与验收', '--body-file', $taskSpecBody, '--label', 'ready-for-agent')
    $taskNumber = [int]($taskUrl.Trim().Split('/')[-1])
    $taskId = Invoke-TaskGh -Arguments @('api', "repos/$taskRepo/issues/$taskNumber", '--jq', '.id')
    $taskRecord.parent = @{ number = $taskNumber; id = [long]$taskId; url = $taskUrl.Trim() }
    Save-TaskRecord
    Write-Output ('Published spec: ' + $taskUrl)
}

$taskTitles = @(
    '开局并完成首场武器战斗',
    '搜刮交易并装备合成战利品',
    '组建完整机制构筑并理解战斗结果',
    '付费探索路线并处理守路遭遇',
    '打听并完成武道主线与支线',
    '回归整备并完成第一阶段挑战',
    '验证三条复演和不同构筑取舍',
    '导出并验收Windows试玩包'
)
$taskBlocks = @(@(), @(1), @(2), @(2), @(3,4), @(5), @(6), @(7))
$taskFiles = @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'issues') -File -Filter '*.md' | Sort-Object Name)
if ($taskFiles.Count -ne 8) { throw 'Expected eight approved tickets' }

for ($taskIndex = 0; $taskIndex -lt 8; $taskIndex++) {
    $taskKey = [string]($taskIndex + 1)
    if (-not $taskRecord.tickets.ContainsKey($taskKey)) {
        $taskDraft = Get-Content -LiteralPath $taskFiles[$taskIndex].FullName -Raw -Encoding utf8
        $taskWhat = [regex]::Match($taskDraft, '(?m)^\*\*What to build:\*\* (.+)$').Groups[1].Value.Trim()
        $taskCriteria = ($taskDraft -split '## Acceptance criteria', 2)[1].Trim()
        $taskBlockText = if ($taskBlocks[$taskIndex].Count -eq 0) { 'None (can start immediately)' } else {
            ($taskBlocks[$taskIndex] | ForEach-Object { '- #' + $taskRecord.tickets[[string]$_].number }) -join "`n"
        }
        $taskBody = "## Parent`n`n#$($taskRecord.parent.number)`n`n## What to build`n`n$taskWhat`n`n## Acceptance criteria`n`n$taskCriteria`n`n## Blocked by`n`n$taskBlockText`n"
        $taskBodyPath = Join-Path $taskRoot ('ticket-' + $taskKey + '-published-body.md')
        Set-Content -LiteralPath $taskBodyPath -Value $taskBody -Encoding utf8
        $taskUrl = Invoke-TaskGh -Arguments @('issue', 'create', '-R', $taskRepo, '--title', ('原型 ' + $taskKey.PadLeft(2,'0') + '：' + $taskTitles[$taskIndex]), '--body-file', $taskBodyPath, '--label', 'ready-for-agent')
        $taskNumber = [int]($taskUrl.Trim().Split('/')[-1])
        $taskId = Invoke-TaskGh -Arguments @('api', "repos/$taskRepo/issues/$taskNumber", '--jq', '.id')
        $taskRecord.tickets[$taskKey] = @{ number = $taskNumber; id = [long]$taskId; url = $taskUrl.Trim(); title = $taskTitles[$taskIndex]; parentLinked = $false; blockersLinked = @() }
        Save-TaskRecord
        Write-Output ('Published ticket ' + $taskKey + ': ' + $taskUrl)
    }
    $taskTicket = $taskRecord.tickets[$taskKey]
    if (-not $taskTicket.parentLinked) {
        Invoke-TaskGh -Arguments @('api', '--method', 'POST', "repos/$taskRepo/issues/$($taskRecord.parent.number)/sub_issues", '-F', "sub_issue_id=$($taskTicket.id)") | Out-Null
        $taskTicket.parentLinked = $true
        Save-TaskRecord
    }
    foreach ($taskBlock in $taskBlocks[$taskIndex]) {
        if ($taskBlock -notin $taskTicket.blockersLinked) {
            $taskBlocker = $taskRecord.tickets[[string]$taskBlock]
            Invoke-TaskGh -Arguments @('api', '--method', 'POST', "repos/$taskRepo/issues/$($taskTicket.number)/dependencies/blocked_by", '-F', "issue_id=$($taskBlocker.id)") | Out-Null
            $taskTicket.blockersLinked = @($taskTicket.blockersLinked) + $taskBlock
            Save-TaskRecord
        }
    }
}

Invoke-TaskGh -Arguments @('api', "repos/$taskRepo/issues/$($taskRecord.parent.number)/sub_issues", '--jq', '.[] | {number,title,state}') | Write-Output
foreach ($taskIndex in 1..8) {
    $taskTicket = $taskRecord.tickets[[string]$taskIndex]
    Invoke-TaskGh -Arguments @('api', "repos/$taskRepo/issues/$($taskTicket.number)", '--jq', '{number,title,state,labels:[.labels[].name],issue_dependencies_summary}') | Write-Output
}
