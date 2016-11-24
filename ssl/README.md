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
- opensslBinPath (optional): Path to directory with openssl.exe file eg. "c:\Program Files\OpenSSL-Win64\bin".

Generate ssl certificate script will attempt to auto detect OpenSSL directory in either root of system drive (typically "C:\") or in Program Files regardless of Win32 or Win64 version installed.
If auto detection fails, script must be run with -opensslBinPath argument to specify location of OpenSSL bin directory.

Example 1: Generate self-signed SSL certificate for www.domain.local:

###
    > generate_ssl_certificate.ps1 -name 'www.domain.com' -domain 'www.domain.local'

Example 2: Generate self-signed wildcard SSL certificate for *.domain.local:

###
    > generate_ssl_certificate.ps1 -name 'domain.com' -domain '*.domain.local'

Example 3: Generate self-signed wildcard SSL certificate for *.domain.local specifying location of openssl:

###
    > generate_ssl_certificate.ps1 -name 'domain.com' -domain '*.domain.local' -opensslBinPath 'c:\Program Files\OpenSSL-Win64\bin'

As a last step generate_ssl_certificate.ps1 script will prompt for a password to create a personal information exchange .pfx export of the domain certificate. This is later used for importing the domain certificate in IIS.

## Certificate files generated

Running generate_ssl_certificate.ps1 script will generate following files:

* "[name] CA.key". Private key used to generate CA certificate.
* "[name] CA.cer": CA certificate used to issue domain certificate.
* "[name].key": Private key used to generate domain certificate.
* "[name].req": Certificate signing request to generate domain certificate.
* "[name].cer": Domain certificate.
* "[name].pfx": Personal information exchange export of domain certificate. 

## CA Certificate Installation in Windows 10

Install CA certificate in Windows with following steps:

1. Double-click on "[name] CA.cer" CA certificate file in Windows Explorer. 
2. Click "Install certificate...".
3. Select "Local Machine" and click "Next".
4. Select "Place all certificate in the following store".
5. Click "Browse", select "Trusted Root Certification Authorities" and click "Next".
6. Click "Finish".

## Domain Certificate Installation in IIS 10

Install domain certificate in IIS with following steps:

1. Open "IIS Manager".
2. In connection (left pane), click your "computer name", Server Certificates in IIS feature list (middle pane).
3. Click "Import" in right pane.
4. Click "..." and select "[name].pfx" personal information exchange file for domain.
5. Enter password identical to password entered when running generate_ssl_certificate.ps1 script.
6. Click "OK".

Domain certificate can now be used when adding bindings for a website in IIS.