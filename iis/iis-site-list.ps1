# IIS Site List
# -------------
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2016-12-13

# Powershell script to list running IIS sites with process id for application pool. Following parameters can be used:
# -full: Display full information about IIS site with physical path, application pool and bindings.
# -all: Display all sites covering both running and not running sites.

Param(
	[Parameter(Mandatory=$false)]
	[switch]$all,
	[Parameter(Mandatory=$false)]
	[switch]$full,
	[Parameter(Mandatory=$false)]
	[switch]$pause	
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# elevate script, if not run as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
	$arguments = "& '" + $myinvocation.mycommand.definition + "' -pause"

	if ($all)
	{
		$arguments += " -all" 
	}
	if ($full)
	{
		$arguments += " -full" 
	}

	Start-Process powershell -Verb runAs -WorkingDirectory "$scriptPath" -ArgumentList $arguments
	break
}

function IISSiteList
{
	Import-Module Webadministration

	$sites = @()
	$sites += Get-ChildItem -Path IIS:\Sites

	ForEach($site in $sites)
	{
		$appPool = "IIS:\AppPools\" + $site.ApplicationPool +  "\WorkerProcesses\"
		$processId = dir $appPool | Select-Object -expand processId

		# skip site, if all parameter is not defined and it doesn't have a process id (not running) 
		if (!$all -and !$processId)
		{
			continue
		}

		Write-Host "Website" -NoNewline -ForegroundColor Cyan
		Write-Host " '" -NoNewline -ForegroundColor DarkGray
		Write-Host $site.Name -NoNewline -ForegroundColor White
		
		Write-Host "' is " -NoNewline -ForegroundColor DarkGray

		if ($processId)
		{
			Write-Host "running" -NoNewline -ForegroundColor Green
			Write-Host " with process id "  -NoNewline -ForegroundColor DarkGray
			Write-Host $processId -ForegroundColor Magenta
		}
		else{
			Write-Host "not running" -ForegroundColor Yellow
		}

		if ($full)
		{
			Write-Host "  PhysicalPath '" -NoNewline -ForegroundColor DarkGray
			Write-Host $site.PhysicalPath -NoNewline -ForegroundColor White
			Write-Host "'" -ForegroundColor DarkGray
			Write-Host "  ApplicationPool '" -NoNewline -ForegroundColor DarkGray
			Write-Host $site.ApplicationPool -NoNewline -ForegroundColor White
			Write-Host "'" -ForegroundColor DarkGray

			for($i = 0; $i -lt $site.Bindings.Collection.Count; $i++)
			{
				$binding = $site.Bindings.Collection[$i]
				Write-Host ("  Binding " + ($i + 1) + " '") -NoNewline -ForegroundColor DarkGray
				Write-Host ($binding.Protocol + " " + $binding.BindingInformation) -NoNewline -ForegroundColor Green
				Write-Host "'" -ForegroundColor DarkGray
			}
		}
	}
}

# Use try catch block to ensure script exits with error code, if it fails
try
{
	IISSiteList
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