@echo off
setlocal
set "LAUNCHER_EXE=%~dp0.launcher\app\VSCode-Codex-Launcher.exe"
set "VSCODE_LAUNCHER_SELF_PATH=%~f0"
set "VSCODE_LAUNCHER_REPO_ROOT=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$selfPath = $env:VSCODE_LAUNCHER_SELF_PATH;" ^
  "$allLines = Get-Content -LiteralPath $selfPath;" ^
  "$marker = ':__EMBEDDED_BOOTSTRAP_PS1__';" ^
  "$startIndex = [Array]::IndexOf($allLines, $marker);" ^
  "if ($startIndex -lt 0) { Write-Host '[launcher] Embedded bootstrap script is missing.'; exit 1 }" ^
  "$scriptLines = $allLines[($startIndex + 1)..($allLines.Length - 1)];" ^
  "$tempPath = Join-Path $env:TEMP ('vscode-codex-launcher-bootstrap-' + [Guid]::NewGuid().ToString('N') + '.ps1');" ^
  "$utf8 = New-Object System.Text.UTF8Encoding($false);" ^
  "[System.IO.File]::WriteAllText($tempPath, ($scriptLines -join [Environment]::NewLine), $utf8);" ^
  "try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempPath } finally { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }"

if errorlevel 1 (
    echo Launcher install or update could not be completed. See the message above.
    pause
    exit /b 1
)

if not exist "%LAUNCHER_EXE%" (
    echo Launcher executable not found:
    echo %LAUNCHER_EXE%
    pause
    exit /b 1
)

pushd "%~dp0" >nul
start "" "%LAUNCHER_EXE%" %*
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%

:__EMBEDDED_BOOTSTRAP_PS1__
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LAUNCHER_REPO_ROOT)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    [System.IO.Path]::GetFullPath($env:VSCODE_LAUNCHER_REPO_ROOT)
}
$launcherRoot = Join-Path $repoRoot ".launcher"
$launcherAppRoot = Join-Path $launcherRoot "app"
$launcherExePath = Join-Path $launcherAppRoot "VSCode-Codex-Launcher.exe"
$statePath = Join-Path $launcherAppRoot "install-state.json"
$tempRoot = Join-Path $launcherRoot ".update-tmp"

$repoOwner = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LAUNCHER_GITHUB_OWNER)) { "naspenang" } else { $env:VSCODE_LAUNCHER_GITHUB_OWNER.Trim() }
$repoName = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LAUNCHER_GITHUB_REPO)) { "VSCode-Codex-Launcer" } else { $env:VSCODE_LAUNCHER_GITHUB_REPO.Trim() }
$releaseAssetName = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LAUNCHER_RELEASE_ASSET)) { "VSCode-Codex-Launcher-Portable-Release-x64.zip" } else { $env:VSCODE_LAUNCHER_RELEASE_ASSET.Trim() }
$latestReleaseApiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
$gitHubApiVersion = "2022-11-28"

function Write-Info {
    param([string]$Message)
    Write-Host "[launcher] $Message"
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-GitHubToken {
    foreach ($variableName in @(
        "VSCODE_LAUNCHER_GITHUB_TOKEN",
        "GITHUB_TOKEN",
        "GH_TOKEN"
    )) {
        $value = [Environment]::GetEnvironmentVariable($variableName)

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return @{
                Name = $variableName
                Value = $value.Trim()
            }
        }
    }

    return $null
}

function Get-GitHubCliPath {
    $command = Get-Command gh -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Invoke-GitHubCli {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $repoRoot
    )

    $ghPath = Get-GitHubCliPath

    if ([string]::IsNullOrWhiteSpace($ghPath)) {
        throw "GitHub CLI is not available."
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ghPath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $escapedArguments = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_.Replace('"', '\"')) + '"'
        }
        else {
            $_
        }
    }
    $startInfo.Arguments = [string]::Join(' ', $escapedArguments)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return @{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Test-GitHubCliAuthenticated {
    if ([string]::IsNullOrWhiteSpace((Get-GitHubCliPath))) {
        return $false
    }

    $result = Invoke-GitHubCli -Arguments @("auth", "status")
    return $result.ExitCode -eq 0
}

function Get-GitHubJsonHeaders {
    $headers = @{
        "User-Agent" = "VSCode-Codex-Launcher"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = $gitHubApiVersion
    }

    $token = Get-GitHubToken
    if ($null -ne $token) {
        $headers["Authorization"] = "Bearer $($token.Value)"
    }

    return $headers
}

function Get-GitHubBinaryHeaders {
    $headers = @{
        "User-Agent" = "VSCode-Codex-Launcher"
        "Accept" = "application/octet-stream"
        "X-GitHub-Api-Version" = $gitHubApiVersion
    }

    $token = Get-GitHubToken
    if ($null -ne $token) {
        $headers["Authorization"] = "Bearer $($token.Value)"
    }

    return $headers
}

function Get-LatestRelease {
    $token = Get-GitHubToken

    if ($null -ne $token) {
        try {
            return Invoke-RestMethod -Uri $latestReleaseApiUrl -Headers (Get-GitHubJsonHeaders)
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match "404" -or ($_.ErrorDetails -and $_.ErrorDetails.Message -match '"status"\s*:\s*"404"|Not Found')) {
                throw "No GitHub release has been published yet for $repoOwner/$repoName."
            }

            throw
        }
    }

    if (Test-GitHubCliAuthenticated) {
        $result = Invoke-GitHubCli -Arguments @("api", "repos/$repoOwner/$repoName/releases/latest")

        if ($result.ExitCode -ne 0) {
            $ghMessage = ($result.StdErr | Out-String).Trim()

            if ($ghMessage -match "release not found" -or $ghMessage -match "404") {
                throw "No GitHub release has been published yet for $repoOwner/$repoName."
            }

            throw "GitHub CLI could not read the latest release."
        }

        return ($result.StdOut | Out-String) | ConvertFrom-Json
    }

    try {
        return Invoke-RestMethod -Uri $latestReleaseApiUrl -Headers (Get-GitHubJsonHeaders)
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match "404" -or ($_.ErrorDetails -and $_.ErrorDetails.Message -match '"status"\s*:\s*"404"|Not Found')) {
            throw "No GitHub release has been published yet for $repoOwner/$repoName."
        }

        throw
    }
}

function Get-ReleaseAsset {
    param([object]$Release)

    $asset = $Release.assets | Where-Object { $_.name -eq $releaseAssetName } | Select-Object -First 1

    if ($null -eq $asset) {
        throw "Latest GitHub release does not contain asset '$releaseAssetName'."
    }

    return $asset
}

function Get-InstallState {
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Save-InstallState {
    param(
        [object]$Release,
        [object]$Asset
    )

    $state = [ordered]@{
        releaseId = $Release.id
        tagName = $Release.tag_name
        assetName = $Asset.name
        assetUpdatedAt = $Asset.updated_at
        installedAtUtc = [DateTime]::UtcNow.ToString("o")
        sourceRepository = "$repoOwner/$repoName"
    }

    $json = $state | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $statePath -Value $json -Encoding UTF8
}

function Remove-PathIfExists {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Install-ReleaseAsset {
    param(
        [object]$Release,
        [object]$Asset
    )

    Ensure-Directory $launcherRoot
    Remove-PathIfExists $tempRoot
    Ensure-Directory $tempRoot

    $zipPath = Join-Path $tempRoot $Asset.name
    $extractRoot = Join-Path $tempRoot "extract"

    Write-Info "Downloading $($Asset.name) from GitHub release $($Release.tag_name)..."

    $token = Get-GitHubToken

    if ($null -ne $token) {
        Invoke-WebRequest -Uri $Asset.url -OutFile $zipPath -Headers (Get-GitHubBinaryHeaders) -MaximumRedirection 5
    }
    elseif (Test-GitHubCliAuthenticated) {
        $result = Invoke-GitHubCli -Arguments @("release", "download", $Release.tag_name, "-R", "$repoOwner/$repoName", "-p", $Asset.name, "-D", $tempRoot, "--clobber")

        if ($result.ExitCode -ne 0) {
            $ghMessage = ($result.StdErr | Out-String).Trim()

            if ($ghMessage -match "404" -or $ghMessage -match "release not found") {
                throw "No GitHub release has been published yet for $repoOwner/$repoName."
            }

            throw "GitHub CLI could not download the release asset."
        }
    }
    else {
        Invoke-WebRequest -Uri $Asset.url -OutFile $zipPath -Headers (Get-GitHubBinaryHeaders) -MaximumRedirection 5
    }

    Write-Info "Extracting launcher package..."
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractRoot)

    $extractedAppRoot = Join-Path $extractRoot ".launcher\app"
    $extractedExePath = Join-Path $extractedAppRoot "VSCode-Codex-Launcher.exe"

    if (-not (Test-Path -LiteralPath $extractedExePath)) {
        throw "Downloaded package did not contain .launcher\app\VSCode-Codex-Launcher.exe."
    }

    Remove-PathIfExists $launcherAppRoot
    Ensure-Directory $launcherAppRoot
    Copy-Item -Path (Join-Path $extractedAppRoot "*") -Destination $launcherAppRoot -Recurse -Force
    Save-InstallState -Release $Release -Asset $Asset
    Remove-PathIfExists $tempRoot
}

function Ensure-LauncherInstalled {
    Ensure-Directory $launcherRoot

    $release = $null
    $asset = $null
    $state = Get-InstallState
    $appExists = Test-Path -LiteralPath $launcherExePath

    try {
        $release = Get-LatestRelease
        $asset = Get-ReleaseAsset -Release $release

        $needsInstall = -not $appExists
        $needsUpdate = $false

        if ($null -ne $state -and $null -ne $release) {
            $needsUpdate = [string]$state.releaseId -ne [string]$release.id
        }
        elseif ($appExists) {
            $needsUpdate = $true
        }

        if ($needsInstall) {
            Install-ReleaseAsset -Release $release -Asset $asset
            Write-Info "Launcher app installed."
            return
        }

        if ($needsUpdate) {
            Write-Info "New launcher release detected. Updating local app..."
            Install-ReleaseAsset -Release $release -Asset $asset
            Write-Info "Launcher app updated."
            return
        }

        Write-Info "Launcher app is already current."
    }
    catch {
        if ($appExists) {
            Write-Info "GitHub update check failed. Using the existing local launcher app."
            return
        }

        $token = Get-GitHubToken
        if ($null -eq $token -and -not (Test-GitHubCliAuthenticated)) {
            throw "GitHub release access failed and no auth is configured. Set VSCODE_LAUNCHER_GITHUB_TOKEN, GITHUB_TOKEN, or GH_TOKEN, or sign in with GitHub CLI (gh auth login) for the private repo $repoOwner/$repoName."
        }

        throw
    }
}

try {
    Ensure-LauncherInstalled
}
catch {
    $message = $_.Exception.Message

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "Launcher bootstrap failed."
    }

    Write-Host "[launcher] $message"
    exit 1
}
