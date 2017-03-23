Param(
    [Parameter(Mandatory=$true)]
    [string]$solutionFile
)

# Use try catch block to ensure script exits with error code, if it fails
try
{
    $nugetArgs = "restore ""{0}""" -f $solutionFile

    $process = Start-Process -FilePath "nuget.exe" -ArgumentList $nugetArgs -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0)
    {
        Write-Error "Failed to restore nuget packages for solution file '$solutionFile'"
        #Write-Output "##teamcity[buildStatus status='FAILURE']"
        #exit 1
    }
}
catch
{
    Write-Error $_
    ##teamcity[buildStatus status='FAILURE']
    exit 1
}