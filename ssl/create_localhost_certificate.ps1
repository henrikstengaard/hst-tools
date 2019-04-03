# run as admin to allow import pfx certificate!

# create ssl certificate dir
$sslDir = Join-Path $env:USERPROFILE -ChildPath '.ssl'
If(!(test-path $sslDir))
{
    New-Item -ItemType Directory -Force -Path $sslDir
}

# set certificate password here
$pfxPassword = ConvertTo-SecureString -String "localhost" -Force -AsPlainText
$pfxFile = Join-Path $sslDir -ChildPath "localhost.pfx"
$cerFile = Join-Path $sslDir -ChildPath "localhost.cer"

$createNewCertificate = $false
if ((Test-Path $cerFile) -or (Test-Path $pfxFile) -and (Read-Host -Prompt "Create new localhost certificate? [Y]") -match '^y|yes$')
{
    $createNewCertificate = $true
}

if ($createNewCertificate)
{
    # setup certificate properties including the commonName (DNSName) property for Chrome 58+
    $certificate = New-SelfSignedCertificate `
        -Subject localhost `
        -DnsName localhost `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotBefore (Get-Date) `
        -NotAfter (Get-Date).AddYears(5) `
        -CertStoreLocation "cert:CurrentUser\My" `
        -FriendlyName "Localhost Certificate" `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature, KeyEncipherment, DataEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") 
    $certificatePath = 'Cert:\CurrentUser\My\' + ($certificate.ThumbPrint)  

    # create pfx certificate
    Export-PfxCertificate -Cert $certificatePath -FilePath $pfxFile -Password $pfxPassword
    Export-Certificate -Cert $certificatePath -FilePath $cerFile
}

if ((Read-Host -Prompt "Import localhost certificate? [Y]") -match '^y|yes$')
{
    # import the pfx certificate
    Import-PfxCertificate -FilePath $pfxFile Cert:\LocalMachine\My -Password $pfxPassword -Exportable

    # trust the certificate by importing the pfx certificate into your trusted root
    Import-Certificate -FilePath $cerFile -CertStoreLocation Cert:\CurrentUser\Root
}