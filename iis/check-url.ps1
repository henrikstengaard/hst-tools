# Check url
# ---------
#
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2018-09-11
#
# -url "[URL]" (Required): Url to check.


Param(
	[Parameter(Mandatory=$true)]
    [string]$url,
	[Parameter(Mandatory=$false)]
    [switch]$forceHttp
)

Add-Type -AssemblyName System.Web


# execute request
function ExecuteRequest
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$url,
        [Parameter(Mandatory=$true)]
        [bool]$forceHttp
    )

    if ($forceHttp)
    {
        $url = $url -replace '^https?://', 'http://'
    }

    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect = $false

    $location = ""

    try {
        $response = $request.GetResponse()
        $statusCode = [int]$response.StatusCode
        $location = $response.Headers["Location"]
    }
    catch [System.Net.WebException] {
        Write-Host $_.Exception.ToString() -Foreground Red
        $response = $_.Exception.Response
        $statusCode = [int]$response.StatusCode

        $encoding = [System.Text.Encoding]::UTF8;
        $reader = New-Object -type System.IO.StreamReader $response.GetResponseStream(), $encoding
        $responseText = $reader.ReadToEnd()
        $reader.Close()

        Write-Host $responseText
    }

    if (!$location)
    {
        $location = ''
    }

    if ($location -notmatch '^https?://')
    {
        $uri = [System.Uri]$url
        $location = (New-Object -TypeName 'System.Uri' -ArgumentList $uri, $location).AbsoluteUri
    }

    $response.Close()
    $response.Dispose()    

    return @{ "StatusCode" = $statusCode; "Location" = $location }
}

Write-Host ("Request: '{0}'" -f $url)

$response = ExecuteRequest -url $url $forceHttp

Write-Host $response.StatusCode

if ([int32]$response.StatusCode -eq 301)
{
    Write-Host ("Location '{0}'" -f $response.Location)
}

# cyclic redirect check of response location
$responseIndex = @{}
$redirectSession = @{ $url = $true }
$redirectCount = 0
$cyclicRedirect = $false
$url = $response.Location
$urlsVisited = New-Object System.Collections.Generic.List[System.Object]
$urlsVisited.Add($redirect.OldUrl)
do {
    if (!$url)
    {
        break;
    }

    $redirectCount++
    $url = $url.ToLower() -replace '/+$', ''
    $cyclicRedirect = $redirectSession.ContainsKey($url)

    if (!$cyclicRedirect)
    {
        $urlsVisited.Add($url)
    }

    $redirectSession[$url] = $true

    Write-Host ("Request: '{0}'" -f $url)
    
    if ($responseIndex.ContainsKey($url))
    {
        $response = $responseIndex[$url]
    }
    else
    {
        $response = ExecuteRequest -url $url -forceHttp $forceHttp

        $responseIndex[$url] = $response
    }

    Write-Host $response.StatusCode

    if ([int32]$response.StatusCode -eq 301)
    {
        Write-Host ("Location: '{0}'" -f $response.Location)
    }
        
    $urlHasRedirect = $response -and [int32]$response.StatusCode -eq 301 -and $response.Location
    if ($urlHasRedirect)
    {
        $url = $response.Location
    }
} while ($urlHasRedirect -and !$cyclicRedirect -and $redirectCount -lt 20)

# fail, if cyclic redirects detected in urls
if ($cyclicRedirect)
{
    Write-Host ("ERROR: Cyclic redirect detect in urls '{0}'" -f ($urlsVisited -join ',')) -Foreground Red
    exit 1
}

# fail, if too many redirects
if ($redirectCount -ge 20)
{
    Write-Host "ERROR: Too many redirects" -Foreground Red
    exit 1
}