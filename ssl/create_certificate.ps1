# Create Certificate
# ------------------
#
# Author: Henrik Nørfjand Stengaard
# Date:   2019-04-03
#
# A PowerShell script to create self-signed certificates.
# Self-signed certificates are issued by CA certificate to avoid warnings in browsers and on mobile devices.
#
# Example: .\create_certificate.ps1 -rootCaName 'Company Name' -domainDnsName '*.companyname.local'
#
# powershell:
# [rootCaName]_root_ca.cer: DER encoded
# [domainDnsName].pfx: PKS12/pfx
# 
# openssl:
# [rootCaName]_root_ca.pem:
# [domainDnsName].pem:
# [domainDnsName]_key.pem:
# [domainDnsName].key:
# [domainDnsName].crt:
#
# OpenSSL can be downloaded from https://slproweb.com/products/Win32OpenSSL.html and download latest Win64 OpenSSL Light EXE file.


Param(
	[Parameter(Mandatory=$true)]
	[string]$rootCaName,
	[Parameter(Mandatory=$true)]
	[string]$domainDnsName,
	[Parameter(Mandatory=$false)]
	[string]$outputDir,
	[Parameter(Mandatory=$false)]
	[string]$opensslBinPath
)


# auto detected openssl bin path
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
if (!$opensslBinPath)
{
	$opensslBinPath = AutoDetectedOpensslBinPath
}

# openssl exe file. set to null, if it doesn't exist
$opensslExeFile = Join-Path $opensslBinPath -ChildPath 'openssl.exe'
if (!(Test-Path $opensslBinPath))
{
    $opensslExeFile = $null
}

# use user profile .ssl as output direcotry, if output directory is not defined
if (!$outputDir)
{
    $homeDir = Resolve-Path ~
    $outputDir = Join-Path $homeDir -ChildPath '.ssl'
}

# resolve output dir
$outputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputDir)


# root ca certificate
$rootCaDnsName = "{0} Root CA" -f $rootCaName
$rootCaCert = get-childitem 'Cert:\LocalMachine\My' | Where-Object { $_.Subject -like ('CN={0}' -f $rootCaDnsName) } | Select-Object -First 1

if (!$rootCaCert)
{
    Write-Output ('Creating ''{0}'' root ca certificate in local computer certificates' -f $rootCaDnsName)

    $params = @{
        DnsName = ("{0} Root CA" -f $rootCaName)
        FriendlyName = ("{0} Root Certificate Authority" -f $rootCaName)
        KeyLength = 2048
        KeyAlgorithm = 'RSA'
        HashAlgorithm = 'SHA256'
        KeyExportPolicy = 'Exportable'
        NotAfter = (Get-Date).AddYears(5)
        CertStoreLocation = 'Cert:\LocalMachine\My'
        KeyUsage = 'CertSign','CRLSign' #fixes invalid cert error
    }
    $rootCaCert = New-SelfSignedCertificate @params

    Write-Output 'Done'
}


# root ca filename
$rootCaFileName = $rootCaName.ToLower() -replace '[^a-z0-9\-\._]', '_'

# create root ca directory, if it doesn't exist
$outputRootCaDir = Join-Path $outputDir -ChildPath $rootCaFileName
if (!(Test-Path $outputRootCaDir))
{
    mkdir $outputRootCaDir | Out-Null
}


# root ca cert file
$rootCaCertFileName = $rootCaDnsName.ToLower() -replace '[^a-z0-9\-\._]', '_'
$rootCaCertFile = Join-Path $outputRootCaDir -ChildPath ('{0}.cer' -f $rootCaCertFileName)

# export root ca cert, if root ca cert file doesn't exist
if (!(Test-Path $rootCaCertFile))
{
    Write-Output ('Exporting ''{0}'' root ca certificate to file ''{1}''' -f $rootCaName, $rootCaCertFile)

    Export-Certificate -Cert $rootCaCert -FilePath $rootCaCertFile | Out-Null

    Write-Output 'Done'
}


# import root ca certificate in trusted root certification authorities
$rootCaCertTrusted = get-childitem 'Cert:\LocalMachine\Root' | Where-Object { $_.Subject -like ('CN={0}' -f $rootCaDnsName) } | Select-Object -First 1
if (!$rootCaCertTrusted)
{
    Write-Output ('Importing ''{0}'' root ca certificate in trusted root certification authorities' -f $rootCaName)

    Import-Certificate -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $rootCaCertFile | Out-Null

    Write-Output 'Done'
}


# domain pfx password
$domainPfxPassword = $domainDnsName -replace '^\*\.', ''

# domain dns names
$domainDnsNames = @($domainDnsName)
if ($domainDnsName -match '^\*\.')
{
    $domainDnsNames += $domainDnsName -replace '^\*\.', ''
}

# domain dns filename
$domainDnsFileName = $domainDnsName.ToLower() -replace '^\*\.', '' -replace '[^a-z0-9\-\._]', '_'

# create domain dns directory, if it doesn't exist
$outputDomainDnsDir = Join-Path $outputRootCaDir -ChildPath $domainDnsFileName
if (!(Test-Path $outputDomainDnsDir))
{
    mkdir $outputDomainDnsDir | Out-Null
}


# domain cert
$domainCert = get-childitem 'Cert:\LocalMachine\My' | Where-Object { $_.Subject -like ('CN={0}' -f $domainDnsName) } | Select-Object -First 1
if (!$domainCert)
{
    Write-Output ('Creating ''{0}'' domain certificate in local computer certificates' -f $domainDnsName)

    $params = @{
        DnsName = $domainDnsNames
        FriendlyName = ("{0} Certificate" -f $domainDnsName)
        Signer = $rootCaCert
        KeyLength = 2048
        KeyAlgorithm = 'RSA'
        HashAlgorithm = 'SHA256'
        KeyExportPolicy = 'Exportable'
        NotAfter = (Get-date).AddYears(5)
        TextExtension = @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") 
        CertStoreLocation = 'Cert:\LocalMachine\My'
    }
    $domainCert = New-SelfSignedCertificate @params

    Write-Output 'Done'
}


# domain cert file
$domainPfxFile = Join-Path $outputDomainDnsDir -ChildPath ('{0}.pfx' -f $domainDnsFileName)

# export domain cert, if domain cert file doesn't exist
if (!(Test-Path $domainPfxFile))
{
    Write-Output ('Exporting ''{0}'' domain pfx certificate to file ''{1}''' -f $domainDnsName, $domainPfxFile)

    $passwordSecureString = ConvertTo-SecureString -AsPlainText $domainPfxPassword -Force
    Export-PfxCertificate -Cert $domainCert -FilePath $domainPfxFile -Password $passwordSecureString | Out-Null

    Write-Output 'Done'
}

# exit, if openssl exe doesn't exist
if (!$opensslExeFile)
{
    Write-Output ''
    Write-Output "Openssl exe doesn't exist. Skipping creation of .pem, .key and .crt files!"
    exit
}


# root ca pem file
$rootCaPemFile = Join-Path $outputRootCaDir -ChildPath ('{0}.pem' -f $rootCaCertFileName)
if (!(Test-Path $rootCaPemFile))
{
    Write-Output ('Creating ''{0}'' root ca pem to file ''{1}''' -f $rootCaDnsName, $rootCaPemFile)

    $opensslArgs = ('x509 -inform der -in "{0}" -out "{1}"' -f $rootCaCertFile, $rootCaPemFile)
    $opensslProcess = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
    if ($opensslProcess.ExitCode -ne 0)
    {
        Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
        exit 1
    }
    Write-Output 'Done'
}


# domain private key pem file
$domainPrivateKeyPemFile = Join-Path $outputDomainDnsDir -ChildPath ('{0}_key.pem' -f $domainDnsFileName)
if (!(Test-Path $domainPrivateKeyPemFile))
{
    Write-Output ('Creating ''{0}'' domain private key pem to file ''{1}''' -f $domainDnsName, $domainPrivateKeyPemFile)

    $opensslArgs = ('pkcs12 -in "{0}" -nocerts -out "{1}" -password pass:{2} -nodes' -f $domainPfxFile, $domainPrivateKeyPemFile, $domainPfxPassword)
    $opensslProcess = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
    if ($opensslProcess.ExitCode -ne 0)
    {
        Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
        exit 1
    }
    Write-Output 'Done'
}


# domain private key file
$domainPrivateKeyFile = Join-Path $outputDomainDnsDir -ChildPath ('{0}.key' -f $domainDnsFileName)
if (!(Test-Path $domainPrivateKeyFile))
{
    Write-Output ('Creating ''{0}'' domain private key to file ''{1}''' -f $domainDnsName, $domainPrivateKeyFile)

    $opensslArgs = ('rsa -in "{0}" -out "{1}"' -f $domainPrivateKeyPemFile, $domainPrivateKeyFile)
    $opensslProcess = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
    if ($opensslProcess.ExitCode -ne 0)
    {
        Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
        exit 1
    }

    Write-Output 'Done'
}


# domain pem file
$domainPemFile = Join-Path $outputDomainDnsDir -ChildPath ('{0}.pem' -f $domainDnsFileName)
if (!(Test-Path $domainPemFile))
{
    Write-Output ('Exporting ''{0}'' domain pem to file ''{1}''' -f $domainDnsName, $domainPemFile)

    $opensslArgs = ('pkcs12 -in "{0}" -nokeys -out "{1}" -password pass:{2} -nodes' -f $domainPfxFile, $domainPemFile, $domainPfxPassword)
    $opensslProcess = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
    if ($opensslProcess.ExitCode -ne 0)
    {
        Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
        exit 1
    }

    Write-Output 'Done'
}


# domain crt file
$domainCrtFile = Join-Path $outputDomainDnsDir -ChildPath ('{0}.crt' -f $domainDnsFileName)

if (!(Test-Path $domainCrtFile))
{
    Write-Output ('Exporting ''{0}'' domain crt to file ''{1}''' -f $domainDnsName, $domainCrtFile)

    $opensslArgs = ('pkcs12 -in "{0}" -clcerts -nokeys -out "{1}" -password pass:{2} -nodes' -f $domainPfxFile, $domainCrtFile, $domainPfxPassword)
    $opensslProcess = Start-Process $opensslExeFile $opensslArgs -Wait -Passthru -NoNewWindow
    if ($opensslProcess.ExitCode -ne 0)
    {
        Write-Error "Failed to run '$opensslExeFile' with args '$opensslArgs'"
        exit 1
    }

    Write-Output 'Done'
}