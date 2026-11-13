param(
  [Parameter(Mandatory=$true)]
  [string] $IsolatedWorkdir
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $IsolatedWorkdir).Path
$config=Get-Content (Join-Path $root 'supabase/config.toml') -Raw
if($config -notmatch 'project_id = "xiaozhuwork_g_isolated_20261010"' -or $config -notmatch 'port = 55812'){
  throw "Refusing to use an unknown Supabase project"
}
$state=corepack pnpm exec supabase status --workdir $root --output json 2>$null|ConvertFrom-Json
if($state.API_URL -ne 'http://127.0.0.1:55811' -or !$state.SERVICE_ROLE_KEY){
  throw 'Dedicated isolated API not available'
}
$secret=[guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')
$envFile=Join-Path $root 'supabase/functions/.env.g-auth-revoke-test'
$out=Join-Path $root 'g-auth-revoke-stdout.log'
$err=Join-Path $root 'g-auth-revoke-stderr.log'
$result=Join-Path $root 'g-auth-revoke-result.log'
$proc=$null
try{
  [IO.File]::WriteAllText($envFile,
    "LIFECYCLE_SCHEDULER_SECRET=$secret`nLIFECYCLE_AUTH_REVOCATION_ENABLED=true`n")
  $command="corepack pnpm exec supabase functions serve --workdir `"$root`" --env-file `"$envFile`""
  $proc=Start-Process 'cmd.exe' -ArgumentList '/d','/c',$command -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $env:SUPABASE_URL=$state.API_URL
  $env:SUPABASE_SERVICE_ROLE_KEY=$state.SERVICE_ROLE_KEY
  $env:SUPABASE_DB_URL='postgresql://postgres:postgres@127.0.0.1:55812/postgres?sslmode=disable'
  $env:LIFECYCLE_SCHEDULER_SECRET=$secret
  $headers=@{Authorization="Bearer $($state.SERVICE_ROLE_KEY)";apikey=$state.SERVICE_ROLE_KEY;'x-lifecycle-scheduler-secret'='invalid'}
  $ready=$false
  for($i=0;$i -lt 15;$i++){
    try{
      $r=Invoke-WebRequest -Method Post -Uri "$($state.API_URL)/functions/v1/lifecycle-worker" -Headers $headers -ContentType 'application/json' -Body '{}' -SkipHttpErrorCheck -TimeoutSec 10
      if([int]$r.StatusCode -eq 403){$ready=$true;break}
    }catch{}
    Start-Sleep -Seconds 2
  }
  if(!$ready){throw 'Isolated lifecycle HTTP was not ready'}
  $output=& node tests/integration/g-auth-revocation-http.mjs 2>&1
  $code=$LASTEXITCODE
  [IO.File]::WriteAllText($result,($output|Out-String))
  $output|Select-Object -Last 20|ForEach-Object {Write-Output "$_"}
  if($code -ne 0){throw "GoTrue revocation failed (exit=$code)"}
  Write-Output 'ISOLATED_GOTRUE_REVOCATION_PASS'
}finally{
  if($proc){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}
  if(Test-Path $envFile){Remove-Item $envFile -Force}
  Remove-Item Env:LIFECYCLE_SCHEDULER_SECRET -ErrorAction SilentlyContinue
  Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}
