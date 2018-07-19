Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsCsvFile
)

$redirects = @()
$redirects += Import-Csv -Delimiter ';' $redirectsCsvFile

$newRedirects = @()
$newRedirects += $redirects | Where-Object { [int32]$_.NewUrlStatus -ne 404 }

$newRedirectsCsvFile = $redirectsCsvFile -replace '\.[^\.]+$', '_excluded_404.csv'
$newRedirects | export-csv -delimiter ';' -path $newRedirectsCsvFile -NoTypeInformation -Encoding UTF8