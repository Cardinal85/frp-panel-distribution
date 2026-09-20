#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Require PowerShell 5 or newer."
    exit 1
}

$clientRepo = "Cardinal85/frp-panel-distribution"
$version = "latest"
$downloadBase = ""
$serviceArgs = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '--version' {
            if ($i + 1 -ge $args.Count) { throw '--version requires a value.' }
            $version = $args[++$i]
        }
        '--download-base' {
            if ($i + 1 -ge $args.Count) { throw '--download-base requires a URL.' }
            $downloadBase = $args[++$i]
        }
        default { [void]$serviceArgs.Add([string]$args[$i]) }
    }
}

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
switch ($architecture) {
    'x64' { $file = 'frp-panel-windows-amd64.exe'; $releaseArch = 'amd64' }
    'arm64' { $file = 'frp-panel-windows-arm64.exe'; $releaseArch = 'arm64' }
    default { throw "Unsupported Windows architecture: $architecture" }
}

function Resolve-DownloadUrl([string]$Base, [string]$VersionValue, [string]$FileName) {
    if ([string]::IsNullOrWhiteSpace($Base)) {
        if ($VersionValue -eq 'latest') {
            return "https://github.com/$clientRepo/releases/latest/download/$FileName"
        }
        return "https://github.com/$clientRepo/releases/download/$VersionValue/$FileName"
    }

    $url = $Base.TrimEnd('/')
    if ($url -match '\{version\}|\{file\}|\{platform\}|\{arch\}') {
        return $url.Replace('{version}', $VersionValue).Replace('{file}', $FileName).Replace('{platform}', 'windows').Replace('{arch}', $releaseArch)
    }
    return "$url/$FileName"
}

$download = Resolve-DownloadUrl $downloadBase $version $file
if ([string]::IsNullOrWhiteSpace($downloadBase)) {
    $networkAvailable = Test-Connection -ComputerName google.com -Count 1 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($networkAvailable)) {
        $download = "https://ghfast.top/$download"
        Write-Host "Location: CN, using mirror address"
    }
}

Write-Host "Downloading $file ($version)"
Write-Host "Location: $download"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installDir = 'C:\frpp'
$tempPath = Join-Path $env:TEMP 'frp-panel.exe.download'
try {
    Invoke-WebRequest -UseBasicParsing $download -OutFile $tempPath
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null

    $target = Join-Path $installDir 'frpp.exe'
    if (Test-Path $target) {
        & $target stop 2>$null
        & $target uninstall 2>$null
        Start-Sleep -Seconds 2
    }
    Move-Item -Path $tempPath -Destination $target -Force
    & $target install @serviceArgs
    & $target start
    Write-Host "frp-panel $version installed successfully."
} finally {
    if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
}
