Param(
  [string]$Version = $env:STAC_VERSION
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log { param([string]$m) Write-Host "[stac_cli] $m" }
function Write-Err { param([string]$m) Write-Error "[stac_cli] $m" }

$Repo = if ($env:STAC_RELEASES_REPO) { $env:STAC_RELEASES_REPO } else { 'stac-app/releases' }
if (-not $Version -or $Version -eq '') { $Version = 'latest' }

function Get-Arch {
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'arm64' }
  return 'x64'
}

function Download-File([string]$Url, [string]$Dest) {
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    curl.exe -fsSL $Url -o $Dest | Out-Null
  } elseif (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing | Out-Null
  } else {
    throw 'curl or Invoke-WebRequest required'
  }
}

function Get-LatestTag {
  $api = "https://api.github.com/repos/$Repo/releases/latest"
  $res = Invoke-RestMethod -UseBasicParsing -Uri $api -Method GET
  return $res.tag_name
}

try {
  $arch = Get-Arch
  $os = 'windows'
  $tag = if ($Version -eq 'latest') { Get-LatestTag } else { "stac-cli-v$Version" }
  if (-not $tag) { throw 'Failed to resolve latest tag' }
  $resolved = $tag -replace '^stac-cli-v',''
  $asset = "stac_cli_${resolved}_${os}_${arch}.zip"
  $url = "https://github.com/$Repo/releases/download/$tag/$asset"

  $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()) -Force
  $zip = Join-Path $tmp.FullName $asset
  Write-Log "Downloading $asset from $Repo ($tag)"
  Download-File $url $zip

  Write-Log 'Extracting'
  Expand-Archive -Path $zip -DestinationPath $tmp.FullName -Force

  $installDir = if ($env:STAC_INSTALL_DIR) { $env:STAC_INSTALL_DIR } else { "$env:USERPROFILE\\.stac\\bin" }
  New-Item -ItemType Directory -Path $installDir -Force | Out-Null
  Copy-Item (Join-Path $tmp.FullName 'stac.exe') (Join-Path $installDir 'stac.exe') -Force

  $bin = $installDir
  $path = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $path.ToLower().Contains($bin.ToLower())) {
    [System.Environment]::SetEnvironmentVariable('Path', "$bin;$path", 'User')
    Write-Log "Added $bin to PATH for current user. Restart your terminal."
  }

  Write-Log "Installed to $bin\\stac.exe"
  Write-Log 'Run: stac --help'
} catch {
  Write-Err $_.Exception.Message
  exit 1
}


