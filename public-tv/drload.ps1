# DRLoad
# ------
# Author: Henrik Nørfjand Stengaard
# Date: 2017-08-28
# License: MIT
#
# A powershell script to a download mp4 video from http://www.dr.dk video page.


Param(
	[Parameter(Mandatory=$true)]
	[string]$url
)


Add-Type -AssemblyName System.Web


# get html from url using IE to open page and wait 10 seconds for javascript execution to complete
function GetHtml($url)
{
    $ie = New-Object -com InternetExplorer.Application
    $ie.visible = $true
    $ie.navigate($url)
    while($ie.ReadyState -ne 4) {start-sleep -s 1}

    $playElement = $ie.Document.getElementsByTagName('span') | Where-Object { $_.getAttributeNode('class').Value -eq 'dr-icon-play-boxed' } | Select-Object -First 1

    if ($playElement)
    {
        $playElement.Click()
    }

    start-sleep -s 10
    $html = $ie.Document.body.parentElement.outerHTML
    $ie.quit()

    return $html
}


# get flashvars parameter from html
function GetFlashVars($html)
{
    return $html | Select-String -Pattern '<param\s+name="flashvars"\s+value="([^"]+)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 1
}


# get master video resource url from flashvars parameter
function GetMasterVideoResourceUrl($flashVars)
{
    # get flashvars parameters
    $parameters = [System.Web.HttpUtility]::ParseQueryString([System.Web.HttpUtility]::HtmlDecode($flashVars))

    # return null, if program card result parameter doesn't exist
    if (!$parameters.Contains("programcardResult"))
    {
        return $null
    }
    
    # get program card result parameter
    $programcardResult = $parameters["programcardResult"] | ConvertFrom-Json;
    
    # get video resource asset
    $videoResourceAsset = $programcardResult.Assets | Where-Object { $_.Kind -eq "VideoResource" } | Select-Object -First 1

    # return null, if video resource asset doesn't exist
    if (!$videoResourceAsset)
    {
        return $null
    }
    
    # get video resource link containing text "master.
    $masterVideoResourceLink = $videoResourceAsset.Links | Where-Object { $_.Uri -like "*master.*" } | Select-Object -First 1
    
    # return null, if video resource link doesn't exist
    if (!$masterVideoResourceLink)
    {
        return $null
    }

    return $masterVideoResourceLink.Uri
}


# get video filename from master video resource url
function GetVideoFilename($masterVideoResourceUrl)
{
    $name = $masterVideoResourceUrl | Select-String -Pattern '/([^/_]+)[^/]+?\.mp4\.csmil/master\.' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 1

    if (!$name)
    {
        return $null;
    }

    return '{0}.mp4' -f (($name -replace '-', ' ').Trim() -replace '\s+', '_')
}


# download video resource url using ffmpeg
function DownloadVideoResourceUrl($masterVideoResourceUrl, $filename)
{

    $ffmpegArgs = '-i "{0}" -c copy -bsf:a aac_adtstoasc "{1}"'-f $masterVideoResourceUrl, $filename
    # $ffmpegProcess = Start-Process -FilePath $ffmpegFile -ArgumentList $ffmpegArgs -Wait -NoNewWindow -PassThru
    # if ($ffmpegProcess.ExitCode -ne 0)
    # {
    #     Write-Error "Failed to run '$ffmpegFile' with arguments '$ffmpegArgs'"
    #     exit 1
    # }

    Write-Host $ffmpegFile
    Write-Host $ffmpegArgs
        
    # Setting process invocation parameters.
    $processStartInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $processStartInfo.CreateNoWindow = $true
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.RedirectStandardError = $true
    $processStartInfo.FileName = $ffmpegFile
    $processStartInfo.Arguments = $ffmpegArgs

    # Creating process object.
    $process = New-Object -TypeName System.Diagnostics.Process
    $process.StartInfo = $processStartInfo

    # Creating string builders to store stdout and stderr.
    $oStdOutBuilder = New-Object -TypeName System.Text.StringBuilder
    $oStdErrBuilder = New-Object -TypeName System.Text.StringBuilder

    # Adding event handers for stdout and stderr.
    $sScripBlock = {
        if (! [String]::IsNullOrEmpty($EventArgs.Data)) {
            $Event.MessageData.AppendLine($EventArgs.Data)
            #Write-Host $EventArgs.Data
        }
    }

    $oStdOutEvent = Register-ObjectEvent -InputObject $process `
        -Action $sScripBlock -EventName 'OutputDataReceived' `
        -MessageData $oStdOutBuilder
    $oStdErrEvent = Register-ObjectEvent -InputObject $process `
        -Action $sScripBlock -EventName 'ErrorDataReceived' `
        -MessageData $oStdErrBuilder

    # Starting process.
    [Void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    [Void]$process.WaitForExit()

    # Unregistering events to retrieve process output.
    Unregister-Event -SourceIdentifier $oStdOutEvent.Name
    Unregister-Event -SourceIdentifier $oStdErrEvent.Name
}


$scriptDir = split-path -parent $MyInvocation.MyCommand.Definition
$ffmpegFile = Join-Path $scriptDir -ChildPath 'ffmpeg.exe'

if (!(Test-Path -Path $ffmpegFile))
{
    Write-Error ("ffmpeg file '{0}' doesn't exist!" -f $ffmpegFile)
    exit 1
}

$html = GetHtml $url;

$flashVars = GetFlashVars $html

$masterVideoResourceUrl = GetMasterVideoResourceUrl $flashVars

$videoFilename = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((GetVideoFilename $masterVideoResourceUrl))

$masterVideoResourceUrl
$videoFilename
DownloadVideoResourceUrl $masterVideoResourceUrl $videoFilename