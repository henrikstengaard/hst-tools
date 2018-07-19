Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsXmlFile
)

# read urls from redirects xml file
[xml]$xml = Get-Content -Path $redirectsXmlFile
$urls = New-Object System.Collections.Generic.List[System.Object]

foreach ($url in $xml.Redirects.Urls.Url)
{
	$oldUrl = if ($url.Old -is [System.Xml.XmlElement]) { $url.Old.InnerText } else { $url.Old }

	$urls.Add(@{ 'OldUrl' = $oldUrl; 'NewUrl' = $url.New })
}

# write redirects csv file
$redirectsCsvFile = $redirectsXmlFile -replace '\.[^\.]+$', '.csv'
$urls | ForEach-Object{ New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $redirectsCsvFile -NoTypeInformation -Encoding UTF8