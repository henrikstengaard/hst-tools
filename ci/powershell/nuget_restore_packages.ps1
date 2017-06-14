Param(
    [Parameter(Mandatory=$true)]
    [string]$solutionFile
)

# Use try catch block to ensure script exits with error code, if it fails
try
{
    $nugetFile = "%teamcity.tool.NuGet.CommandLine.3.5.0%\tools\nuget.exe"
    $nugetConfigFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($solutionFile), 'nuget.config')

    $nugetClearArgs = "locals all -clear"

    Write-Output "$nugetFile $nugetClearArgs"

    $process = Start-Process -FilePath $nugetFile -ArgumentList $nugetClearArgs -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0)
    {
        Write-Error "Failed to restore nuget packages for solution file '$solutionFile'"
        Write-Output "##teamcity[buildStatus status='FAILURE']"
        exit 1
    }

    # nuget restore, if nuget config file exists
    if (Test-Path $nugetConfigFile)
    {
        $nugetRestoreArgs = "restore ""{0}"" -ConfigFile ""{1}""" -f $solutionFile, $nugetConfigFile

        Write-Output "$nugetFile $nugetRestoreArgs"

        $process = Start-Process -FilePath $nugetFile -ArgumentList $nugetRestoreArgs -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -ne 0)
        {
            Write-Error "Failed to restore nuget packages for solution file '$solutionFile'"
            Write-Output "##teamcity[buildStatus status='FAILURE']"
            exit 1
        }
    }
}
catch
{
    Write-Error $_
    ##teamcity[buildStatus status='FAILURE']
    exit 1
}