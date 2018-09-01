# Import Certificates
# -------------------
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2018-09-01
#
# Powershell script to import certificates

Param(
	[Parameter(Mandatory=$true)]
	[string]$baseDomain,
	[Parameter(Mandatory=$false)]
	[switch]$pause	
)

$scriptDir = split-path -parent $MyInvocation.MyCommand.Definition

# elevate script, if not run as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
	$arguments = "& '" + $myinvocation.mycommand.definition + "' -pause"

	if ($baseDomain)
	{
		$arguments += " -baseDomain '$baseDomain'" 
	}

	Start-Process powershell -Verb runAs -WorkingDirectory "$scriptDir" -ArgumentList $arguments
	break
}

# import certificates
function Import-Certificates
{
	# import root ca certificate in local machine root certificate authorities
	Write-Host "Importing $baseDomain root ca" -ForegroundColor Yellow
	Import-Certificate -FilePath (Join-Path $scriptDir -ChildPath "$baseDomain root ca.cer") -CertStoreLocation 'Cert:\LocalMachine\Root'

	# import domain personal information exchange in local machine personal
	Write-Host "Importing $baseDomain domain" -ForegroundColor Yellow
	$password = ConvertTo-SecureString $baseDomain -asplaintext -force
	Import-PfxCertificate -FilePath (Join-Path $scriptDir -ChildPath "$baseDomain domain.pfx") -CertStoreLocation 'Cert:\LocalMachine\My' -Exportable -Password $password

	Write-Host "Successfully imported certificates!" -ForegroundColor Green
}

# Use try catch block to ensure script exits with error code, if it fails
try
{
	Import-Certificates
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