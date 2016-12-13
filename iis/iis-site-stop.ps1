# IIS Site Stop
# -------------
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2016-12-05

# A powershell script to stop IIS Site and application pool with physical path matching current directory

Param(
	[Parameter()]
	[string]$currentDirectory,
	[Parameter()]
	[switch]$pause
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# elevate script, if not run as administrator
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
	$arguments = "& '" + $myinvocation.mycommand.definition + "' -pause -currentDirectory " + (Convert-Path .)
	Start-Process powershell -Verb runAs -WorkingDirectory "$scriptPath" -ArgumentList $arguments
}

if (!$currentDirectory)
{
	$currentDirectory = Convert-Path .
}

function IISSiteStop
{
	Import-Module Webadministration

	$site = Get-ChildItem -Path IIS:\Sites | where { $currentDirectory -like ($_.PhysicalPath + "*") } | Select-Object -First 1

	if (!$site)
	{
		Write-Host "No IIS sites configured with current path '$currentDirectory'" -ForegroundColor Red
		exit 1
	}
	else 
	{
		Write-Host "Stopping" -NoNewline -ForegroundColor Yellow
		Write-Host " IIS site '" -NoNewline -ForegroundColor DarkGray
		Write-Host $site.Name -NoNewline -ForegroundColor White
		Write-Host " and application pool '" -NoNewline -ForegroundColor DarkGray
		Write-Host $site.ApplicationPool -NoNewline -ForegroundColor White
		Write-Host "'" -ForegroundColor DarkGray

		Stop-WebSite $site.Name

		if((Get-WebAppPoolState $site.ApplicationPool).Value -ne 'Stopped')
		{
			Stop-WebAppPool -Name $site.ApplicationPool
		}
	}
}

# Use try catch block to ensure script exits with error code, if it fails
try
{
	IISSiteStop
}
catch
{
    Write-Error $_
}

if ($pause)
{
	Write-Host "Press enter to continue ..."
	Read-Host
}