# Self-signed SSL certificate

This directory contains a powershell script and configs to generate self-signed SSL certificate for a specific eg. "www.domain.local" or wildcard domain "*.domain.local" used for local website development.
A self-signed CA certificate is first generated used to issue the SSL certificate generated for the domain. 
Adding the CA certificates to trusted root certification authorities makes it possible for browsers to trust the SSL certificate and avoid certificate warning messsages usually shown when using self-signed SSL certificates.

## Requirements

Following software must be installed:

- OpenSSL for Windows: Download latest light version from here https://slproweb.com/products/Win32OpenSSL.html. This is currently Win32/Win64 OpenSSL v1.0u.

## Installation

Install the script by cloning or downloading the github. 

## Usage

The generate_ssl_certificate.ps1 script is run from powershell with following parameters:

- name (required): Name of certificates to generate. This is used to for certificate files generated and display name for certificates.
- domain (required): Domain the certificate will be generated for. This can be specific eg. "www.domain.local" or wildcard domain "*.domain.local".
- outputDir (optional): Path to directory with output files eg. "c:\temp\my-certificate".
- opensslBinPath (optional): Path to directory with openssl.exe file eg. "c:\Program Files\OpenSSL-Win64\bin".

Generate ssl certificate script will attempt to auto detect OpenSSL directory in either root of system drive (typically "C:\") or in Program Files regardless of Win32 or Win64 version installed.
If auto detection fails, script must be run with -opensslBinPath argument to specify location of OpenSSL bin directory.

When running generate_ssl_certificate.ps1 script it will prompt for a password to create a personal information exchange .pfx export of the domain certificate. This is later used for importing the domain certificate in IIS.

Example 1: Generate self-signed SSL certificate for www.domain.local:

```powershell
generate_ssl_certificate.ps1 -name 'www.domain.com' -domain 'www.domain.local'
```

Example 2: Generate self-signed wildcard SSL certificate for *.domain.local:

```powershell
generate_ssl_certificate.ps1 -name 'domain.com' -domain '*.domain.local'
```

Example 3: Generate self-signed wildcard SSL certificate for *.domain.local and specifying location of output directory:

```powershell
generate_ssl_certificate.ps1 -name 'domain.com' -domain '*.domain.local' -outputDir 'c:\temp\domain.local certificate'
```

Example 4: Generate self-signed wildcard SSL certificate for *.domain.local and specifying location of openssl:

```powershell
generate_ssl_certificate.ps1 -name 'domain.com' -domain '*.domain.local' -opensslBinPath 'c:\Program Files\OpenSSL-Win64\bin'
```

## Certificate files generated

Running generate_ssl_certificate.ps1 script will generate following files:

* "[name] CA.key". Private key used to generate CA certificate.
* "[name] CA.cer": CA certificate used to issue domain certificate.
* "[name].key": Private key used to generate domain certificate.
* "[name].req": Certificate signing request to generate domain certificate.
* "[name].cer": Domain certificate.
* "[name].pfx": Personal information exchange export of domain certificate. 

## Install CA Certificate in Windows 10

Install CA certificate in Windows with following steps:

1. Double-click on "[name] CA.cer" CA certificate file in Windows Explorer. 
2. Click "Install certificate...".
3. Select "Local Machine" and click "Next".
4. Select "Place all certificate in the following store".
5. Click "Browse", select "Trusted Root Certification Authorities" and click "Next".
6. Click "Finish".

CA certificate is now trusted on Windows 10.

## Install Domain Certificate in Windows 10 for IIS

Install Domain Certificate in Windows with following steps:

1. Double-click on "[name].pfx" CA certificate file in Windows Explorer. 
2. Select "Local Machine" and click "Next".
3. Click "Next" for File To Import.
4. Enter password for certificate, which was used to create personal information exchange .pfx for IIS.
5. Check "Mark this key as exportable.". 
6. Select "Place all certificate in the following store".
7. Click "Browse", select "Personal" and click "Next".
8. Click "Finish".

Domain certificate can now be used when adding bindings for a website in IIS.

## Install CA Certificate in Mac OSX

Install CA certificate on Mac OSX with the following steps:

1. Double-click on "[name] CA.cer" CA certificate file in Finder.
2. Enter current user password to install CA certificate in Keychain.
3. Double-click on "[name] CA" certificate.
4. Expand Trust and select Always trust for "When using this certificate".
5. Enter current user password to install CA certificate to always trust CA certificate.

CA certificate is now trusted on Mac OSX.

## Install CA Certificate in iOS

Install CA certificate on iOS with the following steps:

1. Tab on the CA certificate file send as an attachment to a mail.
2. Certificate overview is shown, tab "Install" in upper right corner.
3. Certificate warning is shown, tab "Install" in upper right corner.
4. Tab "Install" in bottom popup menu.
5. Tab "Done" in upper right corner.

## Import CA Certificate in Firefox

Import CA Certificate in Firefox with following steps:

1. Open menu and options in Firefox.
2. Click "Advanced", "Certificates" and "View Certificates".
3. Click "Authorities" and "Import".
4. Check "Trust this CA to identify web sites.".
5. Click "OK".

Firefox will now trust the CA Certificate.