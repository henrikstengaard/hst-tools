# NuGet Install
# -------------
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2016-02-24

# Powershell script to download latest NuGet from the website and install 
# it to program files with updating add to user path environment variable

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# elevate script, if not run as administrator
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
	$arguments = "& '" + $myinvocation.mycommand.definition + "'"
	Start-Process powershell -Verb runAs -WorkingDirectory "$scriptPath" -ArgumentList $arguments
	Break
}

function Nuget-Install
{
	$nugetLatestUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	$nugetInstallDir = [System.IO.Path]::Combine($env:ProgramFiles, "NuGet")
	$nugetFile = [System.IO.Path]::Combine($nugetInstallDir, "nuget.exe")

	Write-Host "Install latest NuGet"
	Write-Host "From: '$nugetLatestUrl'"
	Write-Host "To: '$nugetFile'"
	
	if(!(Test-Path -Path $nugetInstallDir))
	{
		md $nugetInstallDir | Out-Null
	}
	
	# download nuget latest url to nuget file
	$webclient = New-Object System.Net.WebClient
	$webclient.DownloadFile($nugetLatestUrl, $nugetFile)
	
	# check if nuget is present in path
	if ($env:path -notmatch 'nuget')
	{
		Write-Host "Installing NuGet in user environment variable: 'Path'"
		
		$path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";$nugetInstallDir" 
		
		[System.Environment]::SetEnvironmentVariable("Path", $path, "User")
	}

	Write-Host "Successfully installed!"
	Write-Host ""
	
	& $nugetFile | Select -First 1
}

# Use try catch block to ensure script exits with error code, if it fails
try
{
	Nuget-Install
}
catch
{
    Write-Error $_
    [System.Environment]::Exit(1)
}

Write-Host "Press any key to continue ..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null

