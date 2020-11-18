<#
#>

#Requires -Modules @{"ModuleName"="Noveris.Logger";"RequiredVersion"="0.6.1"}

########
# Global settings
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

<#
#>
Function Invoke-ServiceRun
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$Iterations = -1,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Start", "Finish")]
        [string]$WaitFrom = "Start",

        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [int]$WaitSeconds = 0,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(Mandatory=$false)]
        [int]$RotateSizeKB = 0,

        [Parameter(Mandatory=$false)]
        [int]$PreserveCount = 5
    )

    process
    {
        # Are we running indefinitely?
        [int]$count = $Iterations
        $infinite = $false
        if ($count -lt 0)
        {
            $infinite = $true
        }

        # Set up log rotation arguments
        $rotateArgs = $null
        if (![string]::IsNullOrEmpty($LogPath))
        {
            $rotateArgs = @{
                LogPath = $LogPath
                PreserveCount = $PreserveCount
                RotateSizeKB = $RotateSizeKB
            }
        }

        while ($infinite -or $count -gt 0)
        {
            # Capture start of script run
            $start = [DateTime]::Now
            Write-Verbose ("Start Time: " + $start.ToString("yyyyMMdd HH:mm:ss"))

            # Rotate log
            if ($null -ne $rotateArgs)
            {
                Reset-LogFileState @rotateArgs
            }

            # Run script block and redirect output as string
            try {
                Write-Verbose "Running script block"
                if ([string]::IsNullOrEmpty($LogPath))
                {
                    & $ScriptBlock *>&1 |
                        Format-RecordAsString -DisplaySummary |
                        Out-String -Stream
                    if (!$?) {
                        Write-Information "Script returned error"
                    }
                } else {
                    & $ScriptBlock *>&1 |
                        Format-RecordAsString -DisplaySummary |
                        Out-String -Stream |
                        Tee-Object -Append -FilePath $LogPath
                    if (!$?) {
                        Write-Information "Script returned error"
                    }
                }
            } catch {
                Write-Information "Script threw error: $_"
            }

            # Capture finish of script run
            $finish = [DateTime]::Now
            Write-Verbose ("Finish Time: " + $finish.ToString("yyyyMMdd HH:mm:ss"))

            if ($count -gt 0)
            {
                $count--
            }

            # Sleep for next iteration if we have iterations remaining
            # or are infinite (-1).
            if ($infinite -or $count -gt 0)
            {
                # Calculate the wait time
                $relative = $finish
                if ($WaitFrom -eq "Start")
                {
                    $relative = $start
                }

                # Determine the wait time in seconds
                $wait = ($relative.AddSeconds($WaitSeconds) - [DateTime]::Now).TotalSeconds
                Write-Verbose "Next iteration in $wait seconds"

                if ($wait -gt 0)
                {
                    # Wait until we should run again
                    Write-Verbose "Starting sleep"
                    Start-Sleep -Seconds $wait
                }
            }
        }
    }
}
