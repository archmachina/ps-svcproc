<#
#>

########
# Global settings
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

Import-Module ([System.IO.Path]::Combine($PSScriptRoot, "Noveris.ModuleMgmt.psm1"))

Remove-Module Noveris.Logger -EA SilentlyContinue
Import-Module -Name Noveris.Logger -RequiredVersion (Install-PSModuleWithSpec -Name Noveris.Logger -Major 0 -Minor 6)

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

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [int]$WaitSeconds
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

        while ($infinite -or $count -gt 0)
        {
            # Capture start of script run
            $start = [DateTime]::Now
            Write-Verbose ("Start Time: " + $start.ToString("yyyyMMdd HH:mm:ss"))

            # Run script block and redirect output as string
            try {
                Write-Verbose "Running script block"
                & $ScriptBlock *>&1 |
                    Format-RecordAsString -DisplaySummary |
                    Out-String -Stream
                if (!$?) {
                    Write-Information "Script returned error"
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
