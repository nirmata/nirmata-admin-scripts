#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Full cleanup of Nirmata Windows worker node.
    Removes everything installed by Prepare-WindowsWorkerNode.ps1 and the
    Nirmata host agent so the node can be freshly re-enrolled.

.NOTES
    Run as Administrator. After this script completes, re-run:
    Prepare-WindowsWorkerNode.ps1 -NirmataUrl ... -NirmataToken ... etc.
#>

$ErrorActionPreference = 'Continue'

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Nirmata Windows Node Full Cleanup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ── 1. Stop all Nirmata/Kubernetes services ──────────────────────────────────
Write-Host "`n[1/10] Stopping services..." -ForegroundColor Yellow
Stop-Service kubelet              -Force -ErrorAction SilentlyContinue
Stop-Service nirmata-host-agent   -Force -ErrorAction SilentlyContinue
Stop-Service containerd           -Force -ErrorAction SilentlyContinue
Write-Host "       Done."

# ── 2. Remove kubelet service (try NSSM first, fall back to sc.exe) ──────────
Write-Host "`n[2/10] Removing kubelet service registration..." -ForegroundColor Yellow
$nssm = "C:\ProgramData\Nirmata\bin\nssm.exe"
if (Test-Path $nssm) {
    & $nssm stop   kubelet confirm  2>$null
    & $nssm remove kubelet confirm  2>$null
    Start-Sleep -Seconds 3
}
sc.exe delete kubelet 2>$null
Start-Sleep -Seconds 3
Write-Host "       Done."

# ── 3. Remove nirmata-host-agent service ─────────────────────────────────────
Write-Host "`n[3/10] Removing nirmata-host-agent service..." -ForegroundColor Yellow
if (Test-Path $nssm) {
    & $nssm stop   nirmata-host-agent confirm 2>$null
    & $nssm remove nirmata-host-agent confirm 2>$null
    Start-Sleep -Seconds 2
}
sc.exe delete nirmata-host-agent 2>$null
Start-Sleep -Seconds 2
Write-Host "       Done."

# ── 4. Clean containerd tasks and containers ──────────────────────────────────
Write-Host "`n[4/10] Cleaning containerd tasks and containers..." -ForegroundColor Yellow
$containerdSvc = Get-Service containerd -ErrorAction SilentlyContinue
if ($containerdSvc -and $containerdSvc.Status -ne 'Running') {
    Start-Service containerd -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}
$taskIds = ctr -n k8s.io tasks list -q 2>$null
if ($taskIds) {
    foreach ($id in $taskIds) {
        Write-Host "       Killing task $id"
        ctr -n k8s.io tasks kill --signal SIGKILL $id 2>$null
        Start-Sleep -Seconds 2
        ctr -n k8s.io tasks rm $id 2>$null
    }
} else { Write-Host "       No running tasks." }

$containerIds = ctr -n k8s.io containers list -q 2>$null
if ($containerIds) {
    foreach ($id in $containerIds) {
        Write-Host "       Deleting container $id"
        ctr -n k8s.io containers delete $id 2>$null
    }
} else { Write-Host "       No containers." }

Stop-Service containerd -Force -ErrorAction SilentlyContinue
Write-Host "       Done."

# ── 5. Remove HNS networks (Calico overlay) ───────────────────────────────────
Write-Host "`n[5/10] Removing HNS networks..." -ForegroundColor Yellow
$hnsNets = Get-HnsNetwork -ErrorAction SilentlyContinue
if ($hnsNets) {
    $hnsNets | Remove-HnsNetwork -ErrorAction SilentlyContinue
    Write-Host "       Removed $($hnsNets.Count) HNS network(s)."
} else { Write-Host "       No HNS networks present." }

# ── 6. Clear containerd snapshots ─────────────────────────────────────────────
Write-Host "`n[6/10] Clearing containerd snapshot layers..." -ForegroundColor Yellow
$snapPath = "C:\ProgramData\containerd\root\io.containerd.snapshotter.v1.windows\snapshots"
if (Test-Path $snapPath) {
    cmd /c "rd /s /q `"$snapPath`"" 2>$null
    New-Item -ItemType Directory -Force $snapPath | Out-Null
    Write-Host "       Snapshots cleared."
} else { Write-Host "       Snapshot path not found." }

# ── 7. Remove Kubernetes certs, kubeconfig, kubelet state ────────────────────
Write-Host "`n[7/10] Removing Kubernetes state..." -ForegroundColor Yellow
Remove-Item "C:\ProgramData\Kubernetes"  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\var\lib\kubeconfig"      -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\var\lib\kubelet"         -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\k"                       -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "       Done."

# ── 8. Remove Calico CNI state ────────────────────────────────────────────────
Write-Host "`n[8/10] Removing Calico CNI state..." -ForegroundColor Yellow
Remove-Item "C:\var\lib\calico"                            -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\containerd\cni\conf\*"       -Force   -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\containerd\cni\bin\calico*"  -Force   -ErrorAction SilentlyContinue
Remove-Item "C:\opt\cni"                                   -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\etc\cni"                                   -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "       Done."

# ── 9. Remove all Nirmata agent files (binaries, NSSM, logs, DB) ─────────────
Write-Host "`n[9/10] Removing Nirmata agent files..." -ForegroundColor Yellow
Remove-Item "C:\ProgramData\Nirmata" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "       Done."

# ── 10. Summary ───────────────────────────────────────────────────────────────
Write-Host "`n[10/10] Checking disk space and service state..." -ForegroundColor Yellow
$drive = Get-PSDrive C
Write-Host "       Free disk: $([math]::Round($drive.Free/1GB,2)) GB"

$svcs = @('nirmata-host-agent','kubelet','containerd') | ForEach-Object {
    Get-Service $_ -ErrorAction SilentlyContinue
}
if ($svcs) {
    $svcs | Format-Table Name, Status, StartType -AutoSize
} else {
    Write-Host "       All Nirmata services removed."
}

Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Cleanup complete. Node is ready for fresh enrollment." -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next step — re-run Prepare-WindowsWorkerNode.ps1:" -ForegroundColor Cyan
Write-Host "  & ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri" -ForegroundColor White
Write-Host "    'https://p2.nirmata.co/nirmata-host-agent/Prepare-WindowsWorkerNode.ps1').Content))" -ForegroundColor White
Write-Host "    -KubernetesVersion '1.33.0' -ContainerdVersion '1.7.23'" -ForegroundColor White
Write-Host "    -NirmataUrl 'https://p2.nirmata.co' -NirmataToken '<token>'" -ForegroundColor White
Write-Host "    -HostAgentImageTag '<tag>'" -ForegroundColor White
