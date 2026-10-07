$ErrorActionPreference = 'Stop'
$taskGh = 'C:/Users/DELL/AppData/Local/CodexTools/github-cli/bin/gh.exe'
$taskRepo = 'Czp14408/game'
$taskRecord = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'publication.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
$taskDrafts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'issues') -File -Filter '*.md' | Sort-Object Name)
$taskExpectedBlocks = @(@(), @(1), @(2), @(2), @(3,4), @(5), @(6), @(7))
$taskChildrenRaw = & $taskGh api "repos/$taskRepo/issues/$($taskRecord.parent.number)/sub_issues"
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify parent sub-issues' }
$taskChildren = $taskChildrenRaw | ConvertFrom-Json
if ($taskChildren.Count -ne 8) { throw 'Expected eight native sub-issues' }
$taskSummary = @('# 第一阶段原型发布记录', '', '状态：用户已确认，规格与8项任务已发布。', '', ('规格：' + $taskRecord.parent.url), '', '| 原编号 | GitHub任务 | 阻塞任务 |', '| --- | --- | --- |')
for ($taskIndex = 1; $taskIndex -le 8; $taskIndex++) {
    $taskTicket = $taskRecord.tickets[[string]$taskIndex]
    $taskEdgesRaw = & $taskGh api "repos/$taskRepo/issues/$($taskTicket.number)/dependencies/blocked_by"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify native blockers' }
    $taskEdges = @($taskEdgesRaw | ConvertFrom-Json)
    $taskExpectedNumbers = @($taskExpectedBlocks[$taskIndex - 1] | ForEach-Object { $taskRecord.tickets[[string]$_].number })
    if ($taskEdges.Count -ne $taskExpectedNumbers.Count) { throw ('Unexpected blocker count for ' + $taskIndex) }
    foreach ($taskEdge in $taskEdges) { if ($taskEdge.number -notin $taskExpectedNumbers) { throw 'Unexpected blocking edge' } }
    $taskBodyPath = Join-Path $PSScriptRoot ('ticket-' + $taskIndex + '-published-body.md')
    $taskBody = Get-Content -LiteralPath $taskBodyPath -Raw -Encoding utf8
    $taskBody = ($taskBody -split '## Blocked by', 2)[0].TrimEnd() + "`n"
    if ($taskIndex -eq 1) { $taskBody += "`n## Blocked by`n`nNone (can start immediately)`n" }
    Set-Content -LiteralPath $taskBodyPath -Value $taskBody -Encoding utf8
    & $taskGh issue edit $taskTicket.number -R $taskRepo --body-file $taskBodyPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot finalize ticket body' }
    $taskCheckRaw = & $taskGh issue view $taskTicket.number -R $taskRepo --json number,title,state,labels,body,url
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read published ticket' }
    $taskCheck = $taskCheckRaw | ConvertFrom-Json
    if ($taskCheck.state -ne 'OPEN' -or 'ready-for-agent' -notin $taskCheck.labels.name -or $taskCheck.body -notmatch '## Acceptance criteria') { throw 'Published ticket validation failed' }
    $taskDraft = Get-Content -LiteralPath $taskDrafts[$taskIndex - 1].FullName -Raw -Encoding utf8
    $taskDraft = $taskDraft -replace '\*\*Status:\*\* draft；用户确认后发布到GitHub并标记ready-for-agent。', ('**Status:** ready-for-agent；已发布：' + $taskTicket.url)
    Set-Content -LiteralPath $taskDrafts[$taskIndex - 1].FullName -Value $taskDraft -Encoding utf8
    $taskBlockDisplay = if ($taskExpectedNumbers.Count) { ($taskExpectedNumbers | ForEach-Object { '#' + $_ }) -join '、' } else { '无' }
    $taskSummary += ('| ' + $taskIndex.ToString('00') + ' | [' + $taskTicket.title + '](' + $taskTicket.url + ') | ' + $taskBlockDisplay + ' |')
    Write-Output ('Verified #' + $taskTicket.number + ', blockers: ' + $taskBlockDisplay)
}
$taskParentRaw = & $taskGh issue view $taskRecord.parent.number -R $taskRepo --json state,labels,body
if ($LASTEXITCODE -ne 0) { throw 'Cannot read published spec' }
$taskParent = $taskParentRaw | ConvertFrom-Json
if ($taskParent.state -ne 'OPEN' -or 'ready-for-agent' -notin $taskParent.labels.name -or $taskParent.body -notmatch '## Testing Decisions') { throw 'Published spec validation failed' }
$taskSummary += @('', '已核对：8项原生子任务、8条原生阻塞边、规格及所有任务的ready-for-agent标签和开放状态、验收正文。当前可直接开始原型01；未开始游戏实现。')
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'publication.md') -Value ($taskSummary -join "`n") -Encoding utf8
$taskSpecPath = Join-Path $PSScriptRoot 'spec.md'
$taskSpec = Get-Content -LiteralPath $taskSpecPath -Raw -Encoding utf8
$taskSpec = $taskSpec -replace '状态：完整草案；需求已确认，测试边界与任务拆分待本轮审阅。目标发布到 Czp14408/game 的 GitHub Issues，标记 ready-for-agent；当前尚未发布。', ('状态：需求、测试边界与任务拆分已获用户确认；已发布并标记ready-for-agent：' + $taskRecord.parent.url)
$taskSpec = $taskSpec -replace '待用户确认的主测试边界：', '用户已确认的主测试边界：'
$taskSpec = $taskSpec -replace '确认测试边界与拆分后发布父规格及子任务；不关闭父规格。', '测试边界与拆分已确认，父规格与子任务已发布；父规格保持开放。'
Set-Content -LiteralPath $taskSpecPath -Value $taskSpec -Encoding utf8
$taskBreakdownPath = Join-Path $PSScriptRoot 'breakdown.md'
$taskBreakdown = Get-Content -LiteralPath $taskBreakdownPath -Raw -Encoding utf8
$taskBreakdown = $taskBreakdown -replace '状态：待用户确认；尚未发布GitHub。父规格为本目录spec.md。所有任务目标发布标签为ready-for-agent，但有阻塞的任务需等阻塞解除后开工。', '状态：用户已确认；规格与8项任务已发布GitHub，实际链接见publication.md。所有任务已标记ready-for-agent，有阻塞的任务需等阻塞解除后开工。'
Set-Content -LiteralPath $taskBreakdownPath -Value $taskBreakdown -Encoding utf8
