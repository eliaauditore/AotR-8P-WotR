<#
Read-only recursive audit for nested launcher source embedded inside V17 builder templates.
Decoded content is never executed and never written to disk.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuilderPath,
    [ValidateRange(1,5)][int]$MaxDepth = 3,
    [ValidateRange(80,4096)][int]$MinBase64Chars = 160,
    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$terms = @(
    'FromBase64String','ToBase64String','GZipStream','DeflateStream','Compression','Decompress',
    'PowerShell','pwsh','powershell.exe','ScriptBlock','ProcessStartInfo','cmd.exe','Resource','payload',
    'launcher_gui','engine','gui','AgeoftheRing','Age of the Ring','rotwk','lotrbfme2ep1.exe',
    'game.dat','zGameDats','_AotR8P_WotR_Runtime','AOTR_HOME','repair-manifest','reset_install','retry_launch'
)

function Get-Hash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-OuterTemplate([string]$Path) {
    $raw = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@''\s*(?<b64>[A-Za-z0-9+/=\r\n]+?)\s*''@\)\)'
    $m = [regex]::Match($raw,$pattern)
    if (-not $m.Success) { throw 'Outer $template Base64 block not found.' }
    $b64 = $m.Groups['b64'].Value -replace '\s',''
    $bytes = [Convert]::FromBase64String($b64)
    [pscustomobject]@{ Bytes=$bytes; Text=[Text.Encoding]::UTF8.GetString($bytes) }
}

function Get-Evidence([string]$Text) {
    $lines = @($Text -split "`r?`n")
    $hits = @()
    foreach ($term in $terms) {
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += [pscustomobject]@{ Term=$term; Line=$i+1; Text=$lines[$i].Trim() }
            }
        }
    }
    @($hits)
}

function Get-TextCandidates([byte[]]$Bytes) {
    $out = @()
    foreach ($enc in @([Text.Encoding]::UTF8,[Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode,[Text.Encoding]::ASCII)) {
        try {
            $text = $enc.GetString($Bytes)
            $n = [Math]::Min($text.Length,4000)
            if ($n -eq 0) { continue }
            $ok = 0
            for ($i=0; $i -lt $n; $i++) {
                $c = [int][char]$text[$i]
                if (($c -ge 9 -and $c -le 13) -or ($c -ge 32 -and $c -le 126) -or $c -ge 160) { $ok++ }
            }
            if (($ok / [double]$n) -ge 0.75) {
                $out += [pscustomobject]@{ Encoding=$enc.WebName; Text=$text }
            }
        } catch { }
    }
    @($out)
}

function Get-Decompressed([byte[]]$Bytes) {
    $out = @()
    foreach ($kind in @('GZip','Deflate')) {
        try {
            $input = [IO.MemoryStream]::new($Bytes,$false)
            try {
                if ($kind -eq 'GZip') {
                    $stream = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
                } else {
                    $stream = [IO.Compression.DeflateStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
                }
                try {
                    $output = [IO.MemoryStream]::new()
                    try {
                        $stream.CopyTo($output)
                        $expanded = $output.ToArray()
                        if ($expanded.Length -gt 0) { $out += [pscustomobject]@{ Kind=$kind; Bytes=$expanded } }
                    } finally { $output.Dispose() }
                } finally { $stream.Dispose() }
            } finally { $input.Dispose() }
        } catch { }
    }
    @($out)
}

$visited = @{}
$nodes = [Collections.ArrayList]::new()
$b64Pattern = '(?<![A-Za-z0-9+/=])([A-Za-z0-9+/]{{{0},}}={{0,2}})(?![A-Za-z0-9+/=])' -f $MinBase64Chars

function Add-Node([string]$Label,[string]$Text,[int]$Depth,[string]$Parent,[string]$DecodeKind) {
    if ($Depth -gt $MaxDepth) { return }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = Get-Hash $bytes
    if ($visited.ContainsKey($hash)) { return }
    $visited[$hash] = $true
    $evidence = @(Get-Evidence $Text)
    [void]$nodes.Add([pscustomobject]@{
        Depth=$Depth; Label=$Label; Parent=$Parent; DecodeKind=$DecodeKind;
        Bytes=$bytes.Length; Lines=@($Text -split "`r?`n").Count; SHA256=$hash; Evidence=$evidence
    })
    if ($Depth -ge $MaxDepth) { return }

    $matches = [regex]::Matches($Text,$b64Pattern)
    $i = 0
    foreach ($m in $matches) {
        $i++
        $candidate = $m.Groups[1].Value
        if (($candidate.Length % 4) -ne 0) { continue }
        try { $decoded = [Convert]::FromBase64String($candidate) } catch { continue }
        if ($decoded.Length -lt 32) { continue }
        $base = "$Label/base64#$i"
        foreach ($t in @(Get-TextCandidates $decoded)) {
            Add-Node "$base/$($t.Encoding)" $t.Text ($Depth+1) $Label 'Base64Text'
        }
        foreach ($d in @(Get-Decompressed $decoded)) {
            foreach ($t in @(Get-TextCandidates $d.Bytes)) {
                Add-Node "$base/$($d.Kind)/$($t.Encoding)" $t.Text ($Depth+1) $Label ("Base64+"+$d.Kind)
            }
        }
    }
}

$full = [IO.Path]::GetFullPath($BuilderPath)
if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Builder not found: $full" }
$builderHash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
$outer = Get-OuterTemplate $full
Add-Node 'outer-template' $outer.Text 0 '' 'BuilderBase64'

$result = [pscustomobject]@{
    Tool='AOTR_8P_RECURSIVE_EMBEDDED_AUDIT_V2'; ReadOnly=$true;
    BuilderPath=$full; BuilderSHA256=$builderHash; OuterDecodedBytes=$outer.Bytes.Length;
    Nodes=@($nodes); Safety=[pscustomobject]@{ ExecutesDecodedContent=$false; WritesFiles=$false; WritesRegistry=$false; ModifiesGame=$false; ModifiesLauncher=$false; ModifiesGit=$false }
}

if ($AsJson) { $result | ConvertTo-Json -Depth 10; return }

Write-Host ''
Write-Host '=== AOTR 8P RECURSIVE EMBEDDED AUDIT V2 / READ ONLY ==='
Write-Host ("Builder : {0}" -f $full)
Write-Host ("SHA256  : {0}" -f $builderHash)
Write-Host ("Outer   : {0} bytes" -f $outer.Bytes.Length)
Write-Host ("Nodes   : {0}" -f $nodes.Count)
Write-Host ''
Write-Host '=== NESTED NODE INVENTORY ==='
$nodes | Select-Object Depth,Label,DecodeKind,Bytes,Lines,@{N='EvidenceHits';E={$_.Evidence.Count}},SHA256 | Format-Table -Wrap -AutoSize
Write-Host ''
Write-Host '=== ENCODING / COMPRESSION / HOSTING EVIDENCE ==='
$nodes | ForEach-Object {
    $node=$_
    $node.Evidence | Where-Object { $_.Term -in @('FromBase64String','ToBase64String','GZipStream','DeflateStream','Compression','Decompress','PowerShell','pwsh','powershell.exe','ScriptBlock','ProcessStartInfo','cmd.exe','Resource','payload','launcher_gui','engine','gui') } | ForEach-Object {
        [pscustomobject]@{ Node=$node.Label; Term=$_.Term; Line=$_.Line; Text=$_.Text }
    }
} | Format-Table -Wrap -AutoSize
Write-Host ''
Write-Host '=== AOTR / RESOLVER / REPAIR EVIDENCE ==='
$nodes | ForEach-Object {
    $node=$_
    $node.Evidence | Where-Object { $_.Term -in @('AgeoftheRing','Age of the Ring','rotwk','lotrbfme2ep1.exe','game.dat','zGameDats','_AotR8P_WotR_Runtime','AOTR_HOME','repair-manifest','reset_install','retry_launch') } | ForEach-Object {
        [pscustomobject]@{ Node=$node.Label; Term=$_.Term; Line=$_.Line; Text=$_.Text }
    }
} | Format-Table -Wrap -AutoSize
