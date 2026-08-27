param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Host','Client')]
    [string]$Mode,

    [string]$HostIP = '127.0.0.1',
    [string]$PlayerName = 'Player',

    [ValidateRange(3,8)]
    [int]$RequestedSlot = 3,

    [ValidateRange(1024,65535)]
    [int]$Port = 42888,

    [ValidateRange(1,6)]
    [int]$ExpectedClients = 2,

    [string]$LobbyName = 'AotR 8P WotR START-ACK POC',
    [string]$Build = 'START_ACK_POC_V1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ProtocolText {
    param(
        [string]$Value,
        [string]$Name,
        [switch]$AllowSpaces
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must not be empty."
    }

    if ($Value.Contains('|') -or $Value.Contains(';') -or $Value.Contains('=')) {
        throw "$Name contains a reserved protocol character (| ; =)."
    }

    if (-not $AllowSpaces -and $Value -notmatch '^[A-Za-z0-9_.-]{1,32}$') {
        throw "$Name may contain only A-Z, a-z, 0-9, underscore, dot, and dash (max 32 chars)."
    }
}

function New-A8PConnectionIO {
    param([System.Net.Sockets.TcpClient]$TcpClient)

    $stream = $TcpClient.GetStream()
    $stream.ReadTimeout = 10000
    $stream.WriteTimeout = 10000

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $reader = New-Object System.IO.StreamReader($stream, $utf8, $false, 2048, $true)
    $writer = New-Object System.IO.StreamWriter($stream, $utf8, 2048, $true)
    $writer.AutoFlush = $true

    [pscustomobject]@{
        Stream = $stream
        Reader = $reader
        Writer = $writer
    }
}

function Write-Header {
    param([string]$Title)
    Write-Host ''
    Write-Host '============================================================'
    Write-Host (' ' + $Title)
    Write-Host '============================================================'
}

function Invoke-A8PHost {
    Assert-ProtocolText -Value $LobbyName -Name 'LobbyName' -AllowSpaces
    Assert-ProtocolText -Value $Build -Name 'Build'

    $roomId = [Guid]::NewGuid().ToString('N')
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
    $clients = New-Object System.Collections.ArrayList

    try {
        $listener.Start()

        Write-Header 'AOTR OWN_MP START/ACK HOST'
        Write-Host ("Lobby            : {0}" -f $LobbyName)
        Write-Host ("Room ID          : {0}" -f $roomId)
        Write-Host ("TCP Port         : {0}" -f $Port)
        Write-Host ("Expected clients : {0}" -f $ExpectedClients)
        Write-Host 'Strategic map    : P1=HOST, P2=AI, remote clients request P3-P8'
        Write-Host ''
        Write-Host 'Waiting for clients...'

        while ($clients.Count -lt $ExpectedClients) {
            $tcp = $listener.AcceptTcpClient()
            $tcp.NoDelay = $true
            $tcp.ReceiveTimeout = 10000
            $tcp.SendTimeout = 10000

            $io = New-A8PConnectionIO -TcpClient $tcp
            $keep = $false

            try {
                $hello = $io.Reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($hello)) {
                    throw 'Client sent an empty JOIN frame.'
                }

                $parts = $hello.Split('|')
                if ($parts.Count -ne 5 -or $parts[0] -ne 'A8P_JOIN' -or $parts[1] -ne '1') {
                    $io.Writer.WriteLine('A8P_REJECT|1|BAD_JOIN_FRAME')
                    throw ("Invalid JOIN frame: {0}" -f $hello)
                }

                $name = [string]$parts[2]
                $clientBuild = [string]$parts[3]
                [int]$slot = 0

                Assert-ProtocolText -Value $name -Name 'Remote PlayerName'
                Assert-ProtocolText -Value $clientBuild -Name 'Remote Build'

                if (-not [int]::TryParse($parts[4], [ref]$slot) -or $slot -lt 3 -or $slot -gt 8) {
                    $io.Writer.WriteLine('A8P_REJECT|1|INVALID_SLOT')
                    throw ("Client {0} requested invalid strategic slot: {1}" -f $name, $parts[4])
                }

                if ($clientBuild -ne $Build) {
                    $io.Writer.WriteLine(('A8P_REJECT|1|BUILD_MISMATCH|{0}' -f $Build))
                    throw ("Client {0} build mismatch: remote={1}, host={2}" -f $name, $clientBuild, $Build)
                }

                $duplicateSlot = @($clients | Where-Object { $_.Slot -eq $slot }).Count -gt 0
                if ($duplicateSlot) {
                    $io.Writer.WriteLine(('A8P_REJECT|1|SLOT_IN_USE|P{0}' -f $slot))
                    throw ("Strategic slot P{0} is already in use." -f $slot)
                }

                $duplicateName = @($clients | Where-Object { $_.Name -eq $name }).Count -gt 0
                if ($duplicateName) {
                    $io.Writer.WriteLine('A8P_REJECT|1|NAME_IN_USE')
                    throw ("Player name {0} is already in use." -f $name)
                }

                $endpoint = [string]$tcp.Client.RemoteEndPoint
                $io.Writer.WriteLine(('A8P_ACCEPT|1|{0}|{1}|{2}|{3}' -f $roomId, $LobbyName, $slot, $Build))

                $entry = [pscustomobject]@{
                    Tcp = $tcp
                    Stream = $io.Stream
                    Reader = $io.Reader
                    Writer = $io.Writer
                    Name = $name
                    Build = $clientBuild
                    Slot = $slot
                    Endpoint = $endpoint
                }
                [void]$clients.Add($entry)
                $keep = $true

                Write-Host ("JOIN ACCEPTED    : {0} -> P{1} ({2})" -f $name, $slot, $endpoint)
                Write-Host ("Connected        : {0}/{1}" -f $clients.Count, $ExpectedClients)
            }
            catch {
                Write-Host ("JOIN REJECTED    : {0}" -f $_.Exception.Message)
            }
            finally {
                if (-not $keep) {
                    try { $io.Writer.Dispose() } catch {}
                    try { $io.Reader.Dispose() } catch {}
                    try { $io.Stream.Dispose() } catch {}
                    try { $tcp.Close() } catch {}
                }
            }
        }

        $slotEntries = New-Object System.Collections.Generic.List[string]
        [void]$slotEntries.Add('P1=HOST')
        [void]$slotEntries.Add('P2=AI')
        foreach ($client in @($clients | Sort-Object Slot)) {
            [void]$slotEntries.Add(("P{0}={1}" -f $client.Slot, $client.Name))
        }
        $slotMap = $slotEntries -join ';'
        $nonce = [Guid]::NewGuid().ToString('N')

        Write-Host ''
        Write-Host 'All requested clients connected.'
        Write-Host ("SLOT MAP          : {0}" -f $slotMap)
        Write-Host ("START NONCE       : {0}" -f $nonce)
        Write-Host ''
        Write-Host 'Sending A8P_START...'

        foreach ($client in $clients) {
            $client.Writer.WriteLine(('A8P_START|1|{0}|{1}|{2}' -f $roomId, $nonce, $slotMap))
        }

        $ackedSlots = @{}
        $allAcked = $true

        foreach ($client in @($clients | Sort-Object Slot)) {
            try {
                $ack = $client.Reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($ack)) {
                    throw 'Empty ACK frame.'
                }

                $parts = $ack.Split('|')
                if ($parts.Count -ne 7 -or $parts[0] -ne 'A8P_START_ACK' -or $parts[1] -ne '1') {
                    throw ("Invalid ACK frame: {0}" -f $ack)
                }

                [int]$ackSlot = 0
                if (-not [int]::TryParse($parts[4], [ref]$ackSlot)) {
                    throw 'ACK slot is not numeric.'
                }

                $valid = (
                    $parts[2] -eq $roomId -and
                    $parts[3] -eq $nonce -and
                    $ackSlot -eq $client.Slot -and
                    $parts[5] -eq $client.Name -and
                    $parts[6] -eq $Build
                )

                if (-not $valid) {
                    throw ("ACK identity mismatch: {0}" -f $ack)
                }

                if ($ackedSlots.ContainsKey($ackSlot)) {
                    throw ("Duplicate ACK for P{0}." -f $ackSlot)
                }

                $ackedSlots[$ackSlot] = $client.Name
                Write-Host ("ACK OK           : P{0} {1}" -f $ackSlot, $client.Name)
            }
            catch {
                $allAcked = $false
                Write-Host ("ACK FAILED       : P{0} {1} - {2}" -f $client.Slot, $client.Name, $_.Exception.Message)
            }
        }

        if (-not $allAcked -or $ackedSlots.Count -ne $clients.Count) {
            foreach ($client in $clients) {
                try { $client.Writer.WriteLine(('A8P_START_ABORT|1|{0}|{1}' -f $roomId, $nonce)) } catch {}
            }
            throw ("START barrier failed. ACKs={0}/{1}" -f $ackedSlots.Count, $clients.Count)
        }

        foreach ($client in $clients) {
            $client.Writer.WriteLine(('A8P_START_COMMIT|1|{0}|{1}' -f $roomId, $nonce))
        }

        Write-Host ''
        Write-Host '============================================================'
        Write-Host ' START/ACK BARRIER: PASS'
        Write-Host (" Room ID  : {0}" -f $roomId)
        Write-Host (" Nonce    : {0}" -f $nonce)
        Write-Host (" Slot map : {0}" -f $slotMap)
        Write-Host (" ACKs     : {0}/{1}" -f $ackedSlots.Count, $clients.Count)
        Write-Host '============================================================'
    }
    finally {
        foreach ($client in $clients) {
            try { $client.Writer.Dispose() } catch {}
            try { $client.Reader.Dispose() } catch {}
            try { $client.Stream.Dispose() } catch {}
            try { $client.Tcp.Close() } catch {}
        }
        try { $listener.Stop() } catch {}
    }
}

function Invoke-A8PClient {
    Assert-ProtocolText -Value $PlayerName -Name 'PlayerName'
    Assert-ProtocolText -Value $Build -Name 'Build'

    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        Write-Header 'AOTR OWN_MP START/ACK CLIENT'
        Write-Host ("Player           : {0}" -f $PlayerName)
        Write-Host ("Requested slot   : P{0}" -f $RequestedSlot)
        Write-Host ("Host             : {0}:{1}" -f $HostIP, $Port)
        Write-Host ("Build            : {0}" -f $Build)
        Write-Host ''
        Write-Host 'Connecting...'

        $tcp.NoDelay = $true
        $tcp.ReceiveTimeout = 10000
        $tcp.SendTimeout = 10000

        $async = $tcp.BeginConnect($HostIP, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(5000)) {
            throw 'TCP connection timed out.'
        }
        $tcp.EndConnect($async)

        $io = New-A8PConnectionIO -TcpClient $tcp
        $io.Writer.WriteLine(('A8P_JOIN|1|{0}|{1}|{2}' -f $PlayerName, $Build, $RequestedSlot))

        $accept = $io.Reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($accept)) {
            throw 'Host returned an empty JOIN response.'
        }

        $parts = $accept.Split('|')
        if ($parts[0] -eq 'A8P_REJECT') {
            throw ("Host rejected JOIN: {0}" -f $accept)
        }

        if ($parts.Count -ne 6 -or $parts[0] -ne 'A8P_ACCEPT' -or $parts[1] -ne '1') {
            throw ("Invalid ACCEPT frame: {0}" -f $accept)
        }

        $roomId = [string]$parts[2]
        $remoteLobby = [string]$parts[3]
        [int]$assignedSlot = 0
        if (-not [int]::TryParse($parts[4], [ref]$assignedSlot)) {
            throw 'Host returned a non-numeric slot.'
        }

        if ($assignedSlot -ne $RequestedSlot) {
            throw ("Host assigned P{0}, but client requested P{1}." -f $assignedSlot, $RequestedSlot)
        }

        if ($parts[5] -ne $Build) {
            throw ("Host build differs after ACCEPT: {0}" -f $parts[5])
        }

        Write-Host ("JOIN ACCEPTED     : {0}" -f $remoteLobby)
        Write-Host ("Room ID           : {0}" -f $roomId)
        Write-Host ("Assigned slot     : P{0}" -f $assignedSlot)
        Write-Host ''
        Write-Host 'Waiting for A8P_START...'

        $start = $io.Reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($start)) {
            throw 'Host closed before A8P_START.'
        }

        $parts = $start.Split('|')
        if ($parts.Count -ne 5 -or $parts[0] -ne 'A8P_START' -or $parts[1] -ne '1') {
            throw ("Invalid START frame: {0}" -f $start)
        }

        if ($parts[2] -ne $roomId) {
            throw 'A8P_START room ID mismatch.'
        }

        $nonce = [string]$parts[3]
        $slotMap = [string]$parts[4]
        $expectedMapEntry = ("P{0}={1}" -f $assignedSlot, $PlayerName)
        $mapEntries = $slotMap.Split(';')

        if (-not ($mapEntries -contains 'P1=HOST')) {
            throw 'A8P_START slot map does not contain P1=HOST.'
        }
        if (-not ($mapEntries -contains 'P2=AI')) {
            throw 'A8P_START slot map does not contain P2=AI.'
        }
        if (-not ($mapEntries -contains $expectedMapEntry)) {
            throw ("A8P_START slot map does not contain local assignment {0}." -f $expectedMapEntry)
        }

        Write-Host ("START RECEIVED    : nonce={0}" -f $nonce)
        Write-Host ("SLOT MAP          : {0}" -f $slotMap)

        $io.Writer.WriteLine(('A8P_START_ACK|1|{0}|{1}|{2}|{3}|{4}' -f $roomId, $nonce, $assignedSlot, $PlayerName, $Build))
        Write-Host ("ACK SENT          : P{0} {1}" -f $assignedSlot, $PlayerName)
        Write-Host 'Waiting for A8P_START_COMMIT...'

        $commit = $io.Reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($commit)) {
            throw 'Host closed before START COMMIT.'
        }

        $parts = $commit.Split('|')
        if ($parts[0] -eq 'A8P_START_ABORT') {
            throw ("Host aborted START barrier: {0}" -f $commit)
        }

        if ($parts.Count -ne 4 -or $parts[0] -ne 'A8P_START_COMMIT' -or $parts[1] -ne '1' -or $parts[2] -ne $roomId -or $parts[3] -ne $nonce) {
            throw ("Invalid START COMMIT frame: {0}" -f $commit)
        }

        Write-Host ''
        Write-Host '============================================================'
        Write-Host ' START/ACK CLIENT: PASS'
        Write-Host (" Player   : {0}" -f $PlayerName)
        Write-Host (" Slot     : P{0}" -f $assignedSlot)
        Write-Host (" Room ID  : {0}" -f $roomId)
        Write-Host (" Nonce    : {0}" -f $nonce)
        Write-Host '============================================================'
    }
    finally {
        try { if ($io) { $io.Writer.Dispose() } } catch {}
        try { if ($io) { $io.Reader.Dispose() } } catch {}
        try { if ($io) { $io.Stream.Dispose() } } catch {}
        try { $tcp.Close() } catch {}
    }
}

if ($Mode -eq 'Host') {
    Invoke-A8PHost
}
else {
    Invoke-A8PClient
}
