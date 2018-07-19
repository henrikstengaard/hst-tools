Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsCsvFile
)

function AddQueryParameters()
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$url,
        [Parameter(Mandatory=$true)]
        [hashtable]$queryParameters
    )

    # create url builder and parse query
    $uriBuilder = New-Object -TypeName 'System.UriBuilder' -ArgumentList ($url)
    $query = [System.Web.HttpUtility]::ParseQueryString($uriBuilder.Query)

    # parse query string and add
    $queryParameters.Keys | ForEach-Object { $query[$_] = $queryParameters[$_] }

    # update query and return url
    $uriBuilder.Query = $query.ToString()
    return $uriBuilder.ToString()
}

$redirects = @()
$redirects += Import-Csv -Delimiter ';' $redirectsCsvFile

$newRedirects = New-Object System.Collections.Generic.List[System.Object]

foreach($redirect in $redirects)
{
	if ($redirect.OldUrl -match '^\s*$' -or $redirect.NewUrl -match '^\s*$')
	{
		continue
	}

	$redirect.NewUrl = AddQueryParameters $redirect.NewUrl @{ 'utm_medium' = '301'; 'utm_source' = ([System.Web.HttpUtility]::UrlEncode($redirect.OldUrl)) }
	$newRedirects.Add($redirect)
}

$newRedirectsCsvFile = $redirectsCsvFile -replace '\.[^\.]+$', '_redirect_tracking.csv'
$newRedirects | export-csv -delimiter ';' -path $newRedirectsCsvFile -NoTypeInformation -Encoding UTF8