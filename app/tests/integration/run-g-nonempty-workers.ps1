param(
  [Parameter(Mandatory=$true)]
  [string] $IsolatedWorkdir
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $IsolatedWorkdir).Path
$config = Get-Content (Join-Path $root 'supabase/config.toml') -Raw
if($config -notmatch 'project_id = "xiaozhuwork_g_isolated_20261010"' -or
   $config -notmatch 'port = 55812') {
  throw 'Refusing a non-G Supabase project'
}
$state = corepack pnpm exec supabase status --workdir $root --output json 2>$null | ConvertFrom-Json
if($state.API_URL -ne 'http://127.0.0.1:55811' -or !$state.SERVICE_ROLE_KEY) {
  throw 'Dedicated G local API is unavailable'
}
foreach($worker in @('task-deadline-reminders','dispatch-contribution-penalties')) {
  $target = Join-Path $root "supabase/functions/$worker"
  if(!(Test-Path -LiteralPath $target)) {
    Copy-Item -LiteralPath "supabase/functions/$worker" -Destination $target -Recurse
  } else {
    Copy-Item -LiteralPath "supabase/functions/$worker/index.ts" -Destination (Join-Path $target 'index.ts') -Force
  }
}
$reminder = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$penalty = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$envFile = Join-Path $root 'supabase/functions/.env.g-nonempty-worker-e2e'
$stdout = Join-Path $root 'g-nonempty-workers-stdout.log'
$stderr = Join-Path $root 'g-nonempty-workers-stderr.log'
$resultFile = Join-Path $root 'g-nonempty-workers-result.log'
$process = $null
try {
  [IO.File]::WriteAllText($envFile,
    "TASK_REMINDER_CRON_SECRET=$reminder`nCONTRIBUTION_PENALTY_CRON_SECRET=$penalty`n")
  $command = "corepack pnpm exec supabase functions serve --workdir `"$root`" --env-file `"$envFile`""
  $process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/c',$command -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $env:SUPABASE_URL=$state.API_URL
  $env:SUPABASE_SERVICE_ROLE_KEY=$state.SERVICE_ROLE_KEY
  $env:SUPABASE_DB_URL='postgresql://postgres:postgres@127.0.0.1:55812/postgres?sslmode=disable'
  $env:TASK_REMINDER_CRON_SECRET=$reminder
  $env:CONTRIBUTION_PENALTY_CRON_SECRET=$penalty

  $headers=@{
    Authorization="Bearer $($state.SERVICE_ROLE_KEY)"
    apikey=$state.SERVICE_ROLE_KEY
    'x-task-reminder-secret'='wrong'
  }
  $ready=$false
  for($i=0;$i -lt 15;$i++) {
    try {
      $response=Invoke-WebRequest -Method Post -Uri "$($state.API_URL)/functions/v1/task-deadline-reminders" -Headers $headers -ContentType 'application/json' -Body '{}' -SkipHttpErrorCheck -TimeoutSec 10
      if([int]$response.StatusCode -eq 403){$ready=$true;break}
    } catch {}
    Start-Sleep -Seconds 2
  }
  if(!$ready) { throw 'Isolated Edge runtime did not start' }

  $output=& node tests/integration/g-nonempty-worker-http.mjs 2>&1
  $status=$LASTEXITCODE
  [IO.File]::WriteAllText($resultFile,($output|Out-String))
  $output | Select-Object -Last 20 | ForEach-Object { Write-Output "$_" }
  if($status -ne 0) { throw "Nonempty Edge business worker test failed with exit $status" }
  Write-Output 'G_NONEMPTY_REMINDER_AND_PENALTY_EDGE_E2E_PASS'
} finally {
  if($process){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
  if(Test-Path $envFile){Remove-Item $envFile -Force}
  foreach($name in @('SUPABASE_SERVICE_ROLE_KEY','TASK_REMINDER_CRON_SECRET','CONTRIBUTION_PENALTY_CRON_SECRET')) {
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
  }
}
