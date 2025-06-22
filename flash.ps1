# コマンドライン引数を取得
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('L', 'R')]
    [string]$Side = 'R',
    [Parameter(Mandatory=$false)]
    [string]$BuildDir = "firmware",
    [Parameter(Mandatory=$false)]
    [string]$Uf2File = "zmk.uf2"
)

$Uf2File = Join-Path $BuildDir $Uf2File

# ファイルの存在確認
if (-not (Test-Path $Uf2File)) {
    Write-Error "File '$Uf2File' not found."
    exit 1
}

Write-Host "Firmware file: $Uf2File"
Write-Host "Waiting for new drive... (Press Ctrl+C to cancel)"

try {
    # Get initial drive list
    $initialDrives = Get-PSDrive -PSProvider FileSystem

    while ($true) {
        Start-Sleep -Milliseconds 500
        $currentDrives = Get-PSDrive -PSProvider FileSystem

        # Detect new drives
        $newDrives = $currentDrives | Where-Object {
            $drive = $_
            -not ($initialDrives | Where-Object { $_.Name -eq $drive.Name })
        }

        if ($newDrives) {
            $targetDrive = $newDrives[0]
            $targetPath = Join-Path ($targetDrive.Name + ":\") (Split-Path $Uf2File -Leaf)

            Write-Host "New drive detected: $($targetDrive.Name)"
            Write-Host "Copying firmware..."

            # Get file size
            $fileSize = (Get-Item $Uf2File).Length
            $buffer = New-Object byte[] 1MB
            $totalBytesRead = 0

            # Open file stream
            $source = [System.IO.File]::OpenRead($Uf2File)
            $destination = [System.IO.File]::Create($targetPath)

            try {
                do {
                    $bytesRead = $source.Read($buffer, 0, $buffer.Length)
                    if ($bytesRead -gt 0) {
                        $destination.Write($buffer, 0, $bytesRead)
                        $totalBytesRead += $bytesRead
                        $percentComplete = [math]::Min(100, ($totalBytesRead * 100) / $fileSize)
                        Write-Progress -Activity "Copying firmware" -Status "$([math]::Round($percentComplete))% complete" -PercentComplete $percentComplete
                    }
                } while ($bytesRead -gt 0)
            }
            finally {
                $source.Close()
                $destination.Close()
            }

            Write-Progress -Activity "Copying firmware" -Completed
            Write-Host "Flash completed!"
            break
        }
    }
}
catch [System.Management.Automation.Host.HostException] {
    Write-Host "`nCancelled."
    exit 0
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
