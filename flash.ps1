# Get command line arguments
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

# Check if the drive is a UF2 loader
function Test-IsUf2Loader {
    param([string]$DriveLetter)

    $drivePath = $DriveLetter + ":\"

    # Check if the drive is accessible
    if (-not (Test-Path $drivePath)) {
        return $false
    }

    try {
        # Get drive information
        $drive = Get-PSDrive -Name $DriveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if (-not $drive) {
            return $false
        }

        # Check the volume label
        $volume = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'" -ErrorAction SilentlyContinue
        if ($volume -and $volume.VolumeName -match "UF2") {
            return $true
        }

        # Check if the INFO_UF2.TXT file exists
        $infoFile = Join-Path $drivePath "INFO_UF2.TXT"
        if (Test-Path $infoFile) {
            return $true
        }

        # Check if the INDEX.HTM file exists (often found in UF2 loaders)
        $indexFile = Join-Path $drivePath "INDEX.HTM"
        if (Test-Path $indexFile) {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

function Write-Firmware {
    param([string]$TargetDrive, [string]$SourceFile)

    $targetPath = Join-Path ($TargetDrive + ":\") (Split-Path $SourceFile -Leaf)

    Write-Host "Copying firmware to drive $TargetDrive..."

    Copy-Item -Path $SourceFile -Destination $targetPath -Force

    Write-Host "Flash completed!"
}

# Check if the firmware file exists
if (-not (Test-Path $Uf2File)) {
    Write-Error "File '$Uf2File' not found."
    exit 1
}

Write-Host "Firmware file: $Uf2File"

# Check if there is a UF2 loader in the existing drives
Write-Host "Checking existing drives for UF2 loader..."
$initialDrives = Get-PSDrive -PSProvider FileSystem

foreach ($drive in $initialDrives) {
    if (Test-IsUf2Loader -DriveLetter $drive.Name) {
        Write-Host "UF2 loader found on drive $($drive.Name)"
        Write-Firmware -TargetDrive $drive.Name -SourceFile $Uf2File
        exit 0
    }
}

Write-Host "No UF2 loader found in existing drives."
Write-Host "Waiting for new UF2 loader drive... (Press Ctrl+C to cancel)"

try {
    while ($true) {
        Start-Sleep -Milliseconds 500
        $currentDrives = Get-PSDrive -PSProvider FileSystem

        # Detect new drives
        $newDrives = $currentDrives | Where-Object {
            $drive = $_
            -not ($initialDrives | Where-Object { $_.Name -eq $drive.Name })
        }

        if ($newDrives) {
            foreach ($newDrive in $newDrives) {
                Write-Host "New drive detected: $($newDrive.Name)"

                if (Test-IsUf2Loader -DriveLetter $newDrive.Name) {
                    Write-Host "UF2 loader detected on drive $($newDrive.Name)"
                    Write-Firmware -TargetDrive $newDrive.Name -SourceFile $Uf2File
                    exit 0
                } else {
                    Write-Host "Drive $($newDrive.Name) is not a UF2 loader, skipping..."
                }
            }

            # New drive added, update the initial drive list
            $initialDrives = $currentDrives
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
