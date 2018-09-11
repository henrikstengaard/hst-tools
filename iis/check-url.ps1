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
	[string]$url
)

Add-Type -AssemblyName System.Web


# execute request
function ExecuteRequest
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$url
    )

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

    $response.Close()
    $response.Dispose()    

    return @{ "StatusCode" = $statusCode; "Location" = $location }
}

ExecuteRequest $url