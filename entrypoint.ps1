<#
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile
)

$ErrorActionPreference = "Stop"
. ./ps-cibootstrap/bootstrap.ps1

########
# Capture version information
$version = @($Env:GITHUB_REF, "v0.1.0") | Select-ValidVersions -First -Required

Write-Information "Version:"
$version

########
# Build stage
Invoke-CIProfile -Name $Profile -Steps @{

    lint = @{
        Steps = {
            Use-PowershellGallery
            Install-Module PSScriptAnalyzer -Scope CurrentUser
            Import-Module PSScriptAnalyzer
            $results = Invoke-ScriptAnalyzer -IncludeDefaultRules -Recurse .
            if ($null -ne $results)
            {
                $results
                Write-Error "Linting failure"
            }
        }
    }

    build = @{
        Steps = {
            # Template PowerShell module definition
            Write-Information "Templating SvcProc.psd1"
            Format-TemplateFile -Template source/SvcProc.psd1.tpl -Target source/SvcProc/SvcProc.psd1 -Content @{
                __FULLVERSION__ = $version.PlainVersion
            }

            # Trust powershell gallery
            Write-Information "Setup for access to powershell gallery"
            Use-PowerShellGallery

            # Install any dependencies for the module manifest
            Write-Information "Installing required dependencies from manifest"
            Install-PSModuleFromManifest -ManifestPath source/SvcProc/SvcProc.psd1

            # Test the module manifest
            Write-Information "Testing module manifest"
            Test-ModuleManifest source/SvcProc/SvcProc.psd1

            # Import modules as test
            Write-Information "Importing module"
            Import-Module ./source/SvcProc/SvcProc.psm1
        }
    }

    pr = @{
        Steps = "build"
    }

    latest = @{
        Steps = "build"
    }

    release = @{
        Steps = "build", {
            $owner = "archmachina"
            $repo = "ps-svcproc"

            $releaseParams = @{
                Owner = $owner
                Repo = $repo
                Name = ("Release " + $version.Tag)
                TagName = $version.Tag
                Draft = $false
                Prerelease = $version.IsPrerelease
                Token = $Env:GITHUB_TOKEN
            }

            Write-Information "Creating release"
            New-GithubRelease @releaseParams

            Publish-Module -Path ./source/SvcProc -NuGetApiKey $Env:NUGET_API_KEY
        }
    }
}
