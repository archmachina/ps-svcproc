<#
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Stages
)

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Modules
Remove-Module Noveris.ModuleMgmt -EA SilentlyContinue
Import-Module ./Noveris.ModuleMgmt/source/Noveris.ModuleMgmt/Noveris.ModuleMgmt.psm1

Remove-Module noveris.build -EA SilentlyContinue
Import-Module -Name noveris.build -RequiredVersion (Install-PSModuleWithSpec -Name noveris.build -Major 0 -Minor 4)

########
# Capture version information
$version = Get-BuildVersionInfo -Sources @(
    $Env:GITHUB_REF,
    $Env:BUILD_SOURCEBRANCH,
    $Env:CI_COMMIT_TAG,
    $Env:BUILD_VERSION,
    "v0.1.0"
)

########
# Build stage
Invoke-BuildStage -Name "Build" -Filters $Stages -Script {
    # Template PowerShell module definition
    Write-Information "Templating Noveris.SvcProc.psd1"
    Format-TemplateFile -Template source/Noveris.SvcProc.psd1.tpl -Target source/Noveris.SvcProc/Noveris.SvcProc.psd1 -Content @{
        __FULLVERSION__ = $version.Full
    }

    # Test the module manifest
    Write-Information "Testing module manifest"
    Test-ModuleManifest source/Noveris.SvcProc/Noveris.SvcProc.psd1
}

Invoke-BuildStage -Name "Publish" -Filters $Stages -Script {
    # Publish module
    Publish-Module -Path ./source/Noveris.SvcProc -NuGetApiKey $Env:NUGET_API_KEY
}
