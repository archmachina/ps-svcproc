<#
#>

########
# Global settings
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
Set-StrictMode -Version 2

<#
#>
Function Format-RecordAsString
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        $Input,

        [Parameter(Mandatory=$false)]
        [switch]$DisplaySummary = $false,

        [Parameter(Mandatory=$true)]
        [bool]$StopOnError
    )

    begin
    {
        $errors = 0
        $warnings = 0
    }

    process
    {
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd HH:mm")

        if ([System.Management.Automation.InformationRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.VerboseRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (VERBOSE): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.ErrorRecord].IsAssignableFrom($_.GetType()))
        {
            $errors++
            ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
            $Input | Out-String -Stream | ForEach-Object {
                ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
            }

            if ($StopOnError)
            {
                Write-Error "Error encountered and StopOnError is true. Stopping."
            }
        }
        elseif ([System.Management.Automation.DebugRecord].IsAssignableFrom($_.GetType()))
        {
            ("{0} (DEBUG): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([System.Management.Automation.WarningRecord].IsAssignableFrom($_.GetType()))
        {
            $warnings++
            ("{0} (WARNING): {1}" -f $timestamp, $_.ToString())
        }
        elseif ([string].IsAssignableFrom($_.GetType()))
        {
            ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
        }
        else
        {
            # Don't do ToString() here as this breaks things like Format-Table that
            # don't convert to string properly. Out-String (below) will handle this for us.
            $Input
        }
    }

    end
    {
        # Summarise the number of errors and warnings, if required
        if ($DisplaySummary)
        {
            $timestamp = [DateTime]::Now.ToString("yyyyMMdd HH:mm")
            ("{0} (INFO): Warnings: {1}" -f $timestamp, $warnings)
            ("{0} (INFO): Errors: {1}" -f $timestamp, $errors)
        }
    }
}

<#
#>
Function Reset-LogFileState
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(Mandatory=$false)]
        [int]$PreserveCount = 5,

        [Parameter(Mandatory=$false)]
        [int]$RotateSizeKB = 0
    )

    process
    {
        # Check if the target is a directory
        if (Test-Path -PathType Container $LogPath)
        {
            Write-Error "Target is a directory"
        }

        # Create the log file, if it doesn't exist
        if (!(Test-Path $LogPath))
        {
            Write-Verbose "Log Path doesn't exist. Attempting to create."
            if ($PSCmdlet.ShouldProcess($LogPath, "Create Log"))
            {
                New-Item -Type File $LogPath -EA SilentlyContinue | Out-Null
            } else {
                return
            }
        }

        # Get the attributes of the target log file
        $logInfo = Get-Item $LogPath
        $logSize = ($logInfo.Length/1024)
        Write-Verbose "Current log file size: $logSize KB"

        # Check the size of the log file and rotate if greater than
        # the desired maximum
        if ($logSize -gt $RotateSizeKB)
        {
            Write-Verbose "Rotation required due to log size"
            Write-Verbose "PreserveCount: $PreserveCount"

            # Shuffle all of the logs along
            [int]$count = $PreserveCount
            while ($count -gt 0)
            {
                # If count is 1, we're working on the active log
                if ($count -le 1)
                {
                    $source = $LogPath
                } else {
                    $source = ("{0}.{1}" -f $LogPath, ($count-1))
                }
                $destination = ("{0}.{1}" -f $LogPath, $count)

                # Check if there is an actual log to move and rename
                if (Test-Path -Path $source)
                {
                    Write-Verbose "Need to rotate $source"
                    if ($PSCmdlet.ShouldProcess($source, "Rotate"))
                    {
                        Move-Item -Path $source -Destination $destination -Force
                    }
                }

                $count--
            }

            # Create the log path, if it doesn't exist (i.e. was renamed/rotated)
            if (!(Test-Path $LogPath))
            {
                if ($PSCmdlet.ShouldProcess($LogPath, "Create Log"))
                {
                    New-Item -Type File $LogPath -EA SilentlyContinue | Out-Null
                } else {
                    return
                }
            }

            # Clear the content of the log path (only applies if no rotation was done
            # due to 0 PreserveCount, but the log is over the RotateSizeKB maximum)
            if ($PSCmdlet.ShouldProcess($LogPath, "Truncate"))
            {
                Clear-Content -Path $LogPath -Force
            }
        }
    }
}

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
        [ValidateNotNull()]
        [string]$LogPath = "",

        [Parameter(Mandatory=$false)]
        [int]$RotateSizeKB = 0,

        [Parameter(Mandatory=$false)]
        [int]$PreserveCount = 5,

        [Parameter(Mandatory=$false)]
        [bool]$StopOnError = $false
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
            Write-Verbose "Running script block"
            if ([string]::IsNullOrEmpty($LogPath))
            {
                & {
                    try {
                        & $ScriptBlock *>&1
                    } catch {
                        $_
                    }
                } |
                    Format-RecordAsString -DisplaySummary -StopOnError $StopOnError |
                    Out-String -Stream
                if (!$?) {
                    Write-Information "Script returned error"
                }
            } else {
                & {
                    try {
                        & $ScriptBlock *>&1
                    } catch {
                        $_
                    }
                } |
                    Format-RecordAsString -DisplaySummary -StopOnError $StopOnError |
                    Out-String -Stream |
                    Tee-Object -Append -FilePath $LogPath
                if (!$?) {
                    Write-Information "Script returned error"
                }
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
