# Generate SSL Certificate
# ------------------------
#
# Author: Henrik Nørfjand Stengaard
# Date:   2017-04-21
#
# A PowerShell script to generate self-signed SSL certificates issued by generated CA certificate to avoid warnings in browsers and on mobile devices.
#
# Reference
# https://blog.httpwatch.com/2013/12/12/five-tips-for-using-self-signed-ssl-certificates-with-ios/


Param(
	[Parameter(Mandatory=$true)]
	[string]$name,
	[Parameter(Mandatory=$true)]
	[string]$domain,
	[Parameter(Mandatory=$false)]
	[string]$opensslBinPath
)


function AutoDetectedOpensslBinPath()
{
	$paths = @( [System.IO.Path]::Combine($env:SystemDrive, "OpenSSL-Win32\bin"), [System.IO.Path]::Combine(${env:ProgramFiles(x86)}, "OpenSSL-Win32\bin"), [System.IO.Path]::Combine($env:SystemDrive, "OpenSSL-Win64\bin"), [System.IO.Path]::Combine($env:ProgramFiles, "OpenSSL-Win64\bin") )

	foreach($path in $paths)
	{
		if (test-path -Path $path)
		{
			return $path
		}
	}
}


# autodetect openssl bin path, if parameter is not defined
if (!$opensslBinPath) { 
	$opensslBinPath = AutoDetectedOpensslBinPath
}


# fail, if openssl bin path is not defined or doesn't exist
if (!$opensslBinPath -or !(test-path -path $opensslBinPath))
{
	Write-Error "Openssl bin path '$opensslBinPath' doesn't exist"
	exit 1
}

$opensslExeFile = [System.IO.Path]::Combine($opensslBinPath, "openssl.exe")
$opensslConfigFile = [System.IO.Path]::Combine($opensslBinPath, "openssl.cfg")
$opensslLocalConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("openssl.cfg")


# fail, if openssl exe file doesn't exist
if (!(test-path -path $opensslExeFile))
{
	Write-Error "Openssl exe file '$opensslExeFile' doesn't exist"
	exit 1
}


# fail, if openssl config file doesn't exist
if (!(test-path -path $opensslConfigFile))
{
	Write-Error "Openssl config file '$opensslConfigFile' doesn't exist"
	exit 1
}


# fail, if openssl local config file doesn't exist
if (!(test-path -path $opensslLocalConfigFile))
{
	Write-Error "Openssl local config file '$opensslLocalConfigFile' doesn't exist"
	exit 1
}


# print openssl bin path
Write-Host "------------------------"
Write-Host "Generate SSL Certificate"
Write-Host "------------------------"
Write-Host ""
Write-Host "Using openssl bin path '$opensslBinPath'."


# build alt names for domain openssl config
$altNames = @()
if ($domain -match '^\*.')
{
	$altNames += "DNS.{0} = {1}" -f ($altNames.Count + 1), ($domain -replace '^\*.', '')
}
$altNames += "DNS.{0} = {1}" -f ($altNames.Count + 1), $domain


# create domain openssl config
$domainOpensslConfigFile = [System.IO.Path]::Combine($scriptPath, $name + " openssl.cfg")
Write-Host ""
Write-Host "Creating domain openssl cfg '$domainOpensslConfigFile' for '$name'..."
$domainOpensslConfig = [System.IO.File]::ReadAllText($opensslLocalConfigFile)
$domainOpensslConfig = $domainOpensslConfig -replace '\[\$Domain\]', $domain
$domainOpensslConfig = $domainOpensslConfig -replace '\[\$AltNames\]', ($altNames -Join "`n")
[System.IO.File]::WriteAllText($domainOpensslConfigFile, $domainOpensslConfig)
Write-Host "Done."


# create ca private key file
$caKeyFile = [System.IO.Path]::Combine($scriptPath, $name + " CA.key")
Write-Host ""
Write-Host "Creating CA private key '$caKeyFile' for '$name'..."
$opensslArgs = "genrsa -out ""$caKeyFile"" 2048"
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."


# create ca certificate
Write-Host ""
Write-Host "Creating CA certificate for '$name'..."
$caCerFile = [System.IO.Path]::Combine($scriptPath, $name + " CA.cer")
$opensslArgs = "req -x509 -sha256 -new -key ""$caKeyFile"" -out ""$caCerFile"" -days 1825 -subj /CN=""$name CA"" -config ""$opensslConfigFile"""
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."


# create domain private key file
Write-Host ""
$domainKeyFile = [System.IO.Path]::Combine($scriptPath, $name + ".key")
Write-Host "Creating domain private key '$domainKeyFile' for '$domain'..."
$opensslArgs = "genrsa -out ""$domainKeyFile"" 2048"
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."


# create domain certificate signing request
Write-Host ""
$domainReqFile = [System.IO.Path]::Combine($scriptPath, $name + ".req")
Write-Host "Creating domain certificate signing request '$domainReqFile' for '$domain'..."
$opensslArgs = "req -new -out ""$domainReqFile"" -key ""$domainKeyFile"" -subj /CN=""$domain"" -config ""$domainOpensslConfigFile"""
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."


# create domain certificate
Write-Host ""
$domainCerFile = [System.IO.Path]::Combine($scriptPath, $name + ".cer")
Write-Host "Creating domain certificate '$domainCerFile' for '$domain' issued by '$domain CA' certificate..."
$opensslArgs = "x509 -req -sha256 -in ""$domainReqFile"" -out ""$domainCerFile"" -CAkey ""$caKeyFile"" -CA ""$caCerFile"" -days 1825 -CAcreateserial -CAserial serial -extfile ""$domainOpensslConfigFile"" -extensions v3_req"
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."


# create personal information exchange for IIS
Write-Host ""
$domainPfxFile = [System.IO.Path]::Combine($scriptPath, $name + ".pfx")
Write-Host "Creating domain personal information exchange '$domainPfxFile' for IIS..."
Write-Host "Enter password for certificate:"
$opensslArgs = "pkcs12 -export -out ""$domainPfxFile"" -inkey ""$domainKeyFile"" -in ""$domainCerFile"""
$process = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
if ($process.ExitCode -ne 0)
{
	Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
	exit 1
}
Write-Host "Done."