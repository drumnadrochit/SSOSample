param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $true)]
    [string]$NetBiosName,

    [Parameter(Mandatory = $true)]
    [string]$SafeModeAdministratorPassword,

    [Parameter(Mandatory = $true)]
    [string]$PublishedTestHarnessUrl
)

$ErrorActionPreference = 'Stop'

function Write-LabNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $Path -Value $Lines -Force
}

$secureSafeModePassword = ConvertTo-SecureString -String $SafeModeAdministratorPassword -AsPlainText -Force

Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell, Web-Server, Web-Windows-Auth -IncludeManagementTools | Out-Null

$forestAlreadyPresent = $false
try {
    Get-ADDomain -ErrorAction Stop | Out-Null
    $forestAlreadyPresent = $true
}
catch {
    $forestAlreadyPresent = $false
}

if (-not $forestAlreadyPresent) {
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetBiosName `
        -InstallDns `
        -NoRebootOnCompletion `
        -SafeModeAdministratorPassword $secureSafeModePassword `
        -Force | Out-Null
}

$notes = @(
    'Microsoft Entra Application Proxy KCD Lab Bootstrap',
    '===============================================',
    "Forest present before script run: $forestAlreadyPresent",
    "Configured forest: $DomainName",
    '',
    'Actions completed by the bootstrap script:',
    '- Installed AD DS binaries and RSAT PowerShell tools.',
    '- Installed IIS with Windows Authentication support to prepare the VM for IWA-backed workloads.',
    '- Prepared this VM to become the identity-side lab host for Connector and KCD setup.',
    '',
    'Required next steps:',
    '1. Reboot this VM once. The AD DS forest creation was staged with NoRebootOnCompletion so the deployment extension can finish cleanly.',
    '2. Install and register the Microsoft Entra private network connector using an Entra admin account.',
    '3. Publish the backend app in Application Proxy and set Single sign-on to Integrated Windows authentication.',
    '4. Configure the internal SPN and delegated login identity according to the scenario under test.',
    "5. Use the deployed test harness at $PublishedTestHarnessUrl to walk through delegated identity combinations.",
    '',
    'Important constraint:',
    '- The test harness container is a public-facing helper app. To validate true KCD against the backend itself, swap the backend target for a Windows-auth-capable application.'
)

Write-LabNote -Path 'C:\Lab\NextSteps.txt' -Lines $notes

Write-Output 'Bootstrap completed. Review C:\Lab\NextSteps.txt and reboot the VM once.'