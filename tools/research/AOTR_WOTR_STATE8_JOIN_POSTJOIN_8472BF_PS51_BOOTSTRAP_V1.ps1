param(
    [string]$GameDat = 'C:\AgeoftheRing\rotwk\game.dat',
    [string]$ExpectedRemoteIp = '192.168.0.224',
    [int]$ExpectedRemotePort = 8086,
    [int]$ObserveSeconds = 8,
    [string]$ResearchRoot = 'C:\AOTR_RESEARCH'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PinnedBodyRef = 'c6d80930237337c5eaa38cfde7db6ec4627f1dc8'
$BodyName = 'AOTR_WOTR_STATE8_JOIN_POSTJOIN_8472BF_V1.ps1'
$RepoRaw = 'https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR'

if ([Environment]::Is64BitProcess) {
    throw 'Run under 32-bit Windows PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
}

New-Item -ItemType Directory -Path $ResearchRoot -Force | Out-Null
$temp = Join-Path $env:TEMP ('AOTR_STATE8_JOIN_POST8472_PS51_' + [guid]::NewGuid().ToString('N') + '.ps1')

function Assert-PowerShellSyntax([string]$Path) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($null -ne $errors -and $errors.Count -gt 0) {
        $detail = ($errors | ForEach-Object { 'line {0}: {1}' -f $_.Extent.StartLineNumber,$_.Message }) -join "`n"
        throw "PS51_BODY_PARSER_FAILED - NOTHING EXECUTED.`n$detail"
    }
}

try {
    Write-Host '============================================================'
    Write-Host ' AOTR STATE8 + JOIN + POSTJOIN 0x8472BF - PS5.1 BOOTSTRAP'
    Write-Host '============================================================'
    Write-Host ("Pinned body : {0}" -f $PinnedBodyRef)
    Write-Host ''

    $url = "$RepoRaw/$PinnedBodyRef/tools/research/$BodyName"
    $src = [string](Invoke-WebRequest -UseBasicParsing -Uri $url).Content
    if ([string]::IsNullOrWhiteSpace($src) -or $src.Length -lt 12000) {
        throw "BODY_DOWNLOAD_INVALID length=$($src.Length) - NOTHING EXECUTED."
    }

    $patches = @(
        @('[UIntPtr]$count','[UIntPtr]::new([uint32]$count)'),
        @('[UIntPtr]$bytes.Length','[UIntPtr]::new([uint32]$bytes.Length)'),
        @('[UIntPtr]0x1000','[UIntPtr]::new([uint32]0x1000)'),
        @('[UIntPtr]$stubBytes.Length','[UIntPtr]::new([uint32]$stubBytes.Length)')
    )
    foreach($p in $patches){
        $count=([regex]::Matches($src,[regex]::Escape([string]$p[0]))).Count
        if($count-ne 1){throw "PS51_PATCH_CONTRACT_FAILED token [$($p[0])] count=$count - NOTHING EXECUTED."}
        $src=$src.Replace([string]$p[0],[string]$p[1])
    }

    foreach($required in @(
        '$PostJoinMethod     = [uint32]0x008472BF',
        'Write-U32 $stateAddr ([uint32]8)',
        'Add-Imm32 $stub $PostJoinMethod',
        'JOIN_AND_POSTJOIN_THREAD_RETURNED=YES',
        'POSTJOIN_CREATE_JOIN_BITS_0'
    )){
        if(-not $src.Contains($required)){throw "STATIC_CONTRACT_FAILED missing [$required] - NOTHING EXECUTED."}
    }
    foreach($forbidden in @(
        'Write-U32 $NetworkGlobal',
        'Write-U32 $flagsAddr',
        'Write-U32 $SessionGlobal',
        'Write-U32 $OwnerGlobal'
    )){
        if($src.Contains($forbidden)){throw "STATIC_CONTRACT_FAILED forbidden write [$forbidden] - NOTHING EXECUTED."}
    }

    Set-Content -LiteralPath $temp -Value $src -Encoding UTF8
    Assert-PowerShellSyntax $temp
    Write-Host 'PS51_PATCH_AND_PARSER_PASS' -ForegroundColor Green
    Write-Host 'STATIC_WRITE_CONTRACT_PASS' -ForegroundColor Green
    Write-Host 'Runtime process has not been touched by this bootstrap yet.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Entering controlled runtime experiment now...' -ForegroundColor Yellow
    Write-Host ''

    $invoke=@{
        GameDat=[string]$GameDat
        ExpectedRemoteIp=[string]$ExpectedRemoteIp
        ExpectedRemotePort=[int]$ExpectedRemotePort
        ObserveSeconds=[int]$ObserveSeconds
        ResearchRoot=[string]$ResearchRoot
    }
    & $temp @invoke
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
