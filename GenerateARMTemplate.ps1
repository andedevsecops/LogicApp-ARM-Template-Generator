<#       
  	THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SCRIPT OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

    .SYNOPSIS
        This PowerShell script generates ARM Template for LogicApp. 
        For more information on how to use this script please visit: https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-create-azure-resource-manager-templates

    .DESCRIPTION
        Generates Azure Resource Manager (ARM) Template for Logic App	
    
    .PARAMETER LogicAppName
        Enter the LogicApp name (required)
    
    .PARAMETER LogicAppResourceGroup
        Enter the Resource Group name of LogicApp (required)    

    .EXAMPLE
        .\GenerateARMTemplate.ps1 -LogicAppResourceGroup logicapp-resgrp1 -LogicAppName logicappname
        
#>

#region UserInputs
param(
    [parameter(Mandatory = $true, HelpMessage = "Enter the Tenant Name")]
    [string]$MyTenantName,

    [parameter(Mandatory = $true, HelpMessage = "Enter the Subscription Id")]
    [string]$MySubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Enter the LogicApp Resource Group")]
    [string]$LogicAppResourceGroup,

    [parameter(Mandatory = $true, HelpMessage = "Enter the LogicApp Name")]
    [string]$LogicAppName    
)
#endregion UserInputs

#region HelperFunctions

function Write-Log {
    <#
    .DESCRIPTION 
    Write-Log is used to write information to a log file and to the console.
    
    .PARAMETER Severity
    parameter specifies the severity of the log message. Values can be: Information, Warning, or Error. 
    #>

    [CmdletBinding()]
    param(
        [parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [string]$LogFileName,
 
        [parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Severity = 'Information'
    )
    # Write the message out to the correct channel											  
    switch ($Severity) {
        "Information" { Write-Host $Message -ForegroundColor Green }
        "Warning" { Write-Host $Message -ForegroundColor Yellow }
        "Error" { Write-Host $Message -ForegroundColor Red }
    } 											  
    try {
        [PSCustomObject]@{
            Time     = (Get-Date -f g)
            Message  = $Message
            Severity = $Severity
        } | Export-Csv -Path "$PSScriptRoot\$LogFileName" -Append -NoTypeInformation -Force
    }
    catch {
        Write-Error "An error occurred in Write-Log() method" -ErrorAction SilentlyContinue		
    }    
}

function Get-RequiredModules {
    <#
    .DESCRIPTION 
    Get-Required is used to install and then import a specified PowerShell module.
    
    .PARAMETER Module
    parameter specifices the PowerShell module to install. 
    #>

    [CmdletBinding()]
    param (        
        [parameter(Mandatory = $true)] $Module        
    )
    
    try {
        $installedModule = Get-InstalledModule -Name $Module -ErrorAction SilentlyContinue
        if ($null -eq $installedModule) {
            Write-Log -Message "The $Module PowerShell module was not found" -LogFileName $LogFileName -Severity Warning
            #check for Admin Privleges
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

            if (-not ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
                #Not an Admin, install to current user            
                Write-Log -Message "Can not install the $Module module. You are not running as Administrator" -LogFileName $LogFileName -Severity Warning
                Write-Log -Message "Installing $Module module to current user Scope" -LogFileName $LogFileName -Severity Warning
                
                Install-Module -Name $Module -Scope CurrentUser -Force -AllowClobber
                Import-Module -Name $Module -Force
            }
            else {
                #Admin, install to all users																		   
                Write-Log -Message "Installing the $Module module to all users" -LogFileName $LogFileName -Severity Warning
                Install-Module -Name $Module -Force -AllowClobber -ErrorAction continue
                Import-Module -Name $Module -Force -ErrorAction continue
            }
        }
        # Install-Module will obtain the module from the gallery and install it on your local machine, making it available for use.
        # Import-Module will bring the module and its functions into your current powershell session, if the module is installed.  
    }
    catch {
        Write-Log -Message "An error occurred in Get-RequiredModules() method" -LogFileName $LogFileName -Severity Error																			
        exit
    }
}

#region DriverProgram

Get-RequiredModules("Az.Resources")
Get-RequiredModules("LogicAppTemplate")

# Check Powershell version, needs to be 5 or higher
if ($host.Version.Major -lt 5) {
    Write-Log "Supported PowerShell version for this script is 5 or above" -LogFileName $LogFileName -Severity Error    
    exit
}

$TimeStamp = Get-Date -Format yyyyMMdd_HHmmss 
$LogFileName = '{0}_{1}.csv' -f "LogicAppTemplate", $TimeStamp

Write-Host "`n`n`r`If not already authenticated, you will be prompted to sign in to Azure." -BackgroundColor Blue
Read-Host -Prompt "Press enter to continue or CTRL+C to exit the script."

$Context = Get-AzContext

if (!$Context) {
    Connect-AzAccount
    $Context = Get-AzContext
}

$SubscriptionId = $Context.Subscription.Id
$AzureAccessToken = (Get-AzAccessToken).Token

try {
	Get-LogicAppTemplate -LogicApp $LogicAppName `
                        -ResourceGroup $LogicAppResourceGroup `
                        -SubscriptionId $MySubscriptionId `
                        -TenantName $MyTenantName `
                        -Token $AzureAccessToken `
                        -DisabledState -Verbose | Out-File "$PSScriptRoot\$LogicAppName.json"
}
catch {
	Write-Log -Message "An error occurred in generating ARM Template :$($_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -Expand message)" -LogFileName $LogFileName -Severity Error        
}
#endregion