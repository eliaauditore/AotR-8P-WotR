from pathlib import Path
import argparse
import hashlib

EXPECTED_INPUT = "201B90D474AE39EE7776159A79AC025C80C6E95BB263D1CBF53152B3784895EF"

OLD_BLOCK = '''        Write-RepairLog ("AUTO REPAIR actions completed for " + $info.Code)
        $script:RepairMode = $false
        $script:RepairStage = "NONE"
        Hide-Error

        # From this point onward, any preflight or engine failure is the ONE automatic
        # post-repair retry failing. Enter-RepairMode will therefore expose REPORT ERROR
        # instead of starting the same repair cycle again.
        $script:AutoRepairRetryInProgress = $true
        $script:LastRetryAt = Get-Date
        Set-OverallStatus "AUTO REPAIR COMPLETE — RECHECKING..." $RepairText
        Invoke-Preflight

        if ($script:ReportReady) { return }
        if ($LaunchHit.IsHitTestVisible -and $LaunchText.Text -match '^LAUNCH') {
            Write-RepairLog "AUTO REPAIR retrying launch automatically."
            Start-AotR8PLaunch -FromRepair
        } else {
            throw "Repair completed, but preflight is still not launchable."
        }
'''

NEW_BLOCK = '''        Write-RepairLog ("AUTO REPAIR actions completed for " + $info.Code)
        $script:RepairMode = $false
        $script:RepairStage = "NONE"
        Hide-Error

        # Issue #43: repair completion alone is never permission to launch.
        # First perform a full health re-check with normal repair semantics. If the
        # re-check discovers another repairable problem, remain in AUTO REPAIR instead
        # of escalating to REPORT ERROR. Only a clean re-check may auto-launch.
        $script:AutoRepairRetryInProgress = $false
        $script:LastRetryAt = Get-Date
        Set-OverallStatus "AUTO REPAIR COMPLETE — VERIFYING..." $RepairText
        Invoke-Preflight

        if ($script:ReportReady) { return }
        if ($script:RepairMode) {
            Write-RepairLog ("AUTO REPAIR health re-check found another issue: " + $script:LastErrorCode + "; staying in repair mode.")
            return
        }
        if ($LaunchHit.IsHitTestVisible -and $LaunchText.Text -match '^LAUNCH') {
            Write-RepairLog "AUTO REPAIR health re-check clean; launching automatically."
            $script:AutoRepairRetryInProgress = $true
            Start-AotR8PLaunch -FromRepair
            return
        }

        throw "Repair completed, but health re-check returned neither repair nor launchable state."
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    parser.add_argument("--expected-output", default="")
    args = parser.parse_args()

    path = Path(args.gui_path)
    if sha256(path) != EXPECTED_INPUT:
        raise SystemExit(f"Issue43 input GUI hash mismatch: {sha256(path)}")

    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    count = text.count(OLD_BLOCK)
    if count != 1:
        raise SystemExit(f"Issue43 source block count={count}; expected exactly 1")

    text = text.replace(OLD_BLOCK, NEW_BLOCK, 1)

    required = (
        '$script:AutoRepairRetryInProgress = $false\n        $script:LastRetryAt = Get-Date\n        Set-OverallStatus "AUTO REPAIR COMPLETE — VERIFYING..."',
        'Invoke-Preflight\n\n        if ($script:ReportReady) { return }\n        if ($script:RepairMode)',
        'AUTO REPAIR health re-check clean; launching automatically.',
        '$script:AutoRepairRetryInProgress = $true\n            Start-AotR8PLaunch -FromRepair',
    )
    forbidden = (
        'AUTO REPAIR retrying launch automatically.',
        'Repair completed, but preflight is still not launchable.',
    )
    for token in required:
        if token not in text:
            raise SystemExit("Issue43 required token missing: " + token)
    for token in forbidden:
        if token in text:
            raise SystemExit("Issue43 stale token remains: " + token)

    path.write_text(text, encoding="utf-8-sig", newline="\n")
    output_hash = sha256(path)
    print("ISSUE43_GUI_SHA256=" + output_hash)
    print("ISSUE43_RECHECK_FLOW_GATE=PASS")

    expected = args.expected_output.strip().upper()
    if expected and output_hash != expected:
        raise SystemExit(f"Issue43 output GUI hash mismatch: expected {expected}, got {output_hash}")


if __name__ == "__main__":
    main()
