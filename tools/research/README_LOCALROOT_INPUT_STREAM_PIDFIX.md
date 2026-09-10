# localRoot input-stream capture PowerShell PID compatibility

The initial `AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE.ps1` used `$pid` as a normal PowerShell variable. PowerShell variable names are case-insensitive and `$PID` is a built-in read-only automatic variable, so the script fails on assignment before instrumentation is installed.

`AOTR_WOTR_LOCALROOT_INPUT_STREAM_CAPTURE_PIDFIX_RUNNER.ps1` pins the original capture source at commit `d9c786a74a305f15dac2c6ebb2d9785196c55f0c`, replaces only PowerShell `$pid` tokens with `$gamePid` in a temporary copy, verifies no `$pid` token remains, executes the corrected temporary copy, and removes it afterward. The repository source file and `game.dat` on disk are not modified.
