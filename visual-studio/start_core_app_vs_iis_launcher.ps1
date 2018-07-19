if (!$env:DevEnvDir)
{
    Write-Error ("Environment variable 'DevEnvDir' doesn't exist. Run using VS command prompt")
    exit 1
}

$vsIisExeLauncherFile = Join-Path $env:DevEnvDir -ChildPath 'Extensions\Microsoft\Web Tools\ProjectSystem\VSIISExeLauncher.exe'

if (!(Test-Path $vsIisExeLauncherFile))
{
    Write-Error ("VS IIS Express file '{0}' doesn't exist" -f $vsIisExeLauncherFile)
    exit 1
}

$dotNetExeFile = Join-Path $env:ProgramFiles -ChildPath 'dotnet\dotnet.exe'

if (!(Test-Path $dotNetExeFile))
{
    Write-Error ("DotNet file '{0}' doesn't exist" -f $dotNetExeFile)
    exit 1
}

$siteDir = Resolve-Path '.'
$pidFile = Join-Path $siteDir -ChildPath 'pid.txt'

$csProjFile = Get-ChildItem -Path $siteDir -Filter '*.csproj' | Select-Object -First 1

if (!$csProjFile)
{
    Write-Error "CSproj file doesn't exist"
    exit 1
}

$applicationFile = Join-Path $siteDir -ChildPath ('bin\Debug\netcoreapp2.0\{0}.dll' -f ($csProjFile.Name -replace '\.csproj'))


# Build application
# -----------------

if (!(Test-Path $applicationFile))
{
    Write-Output "Building application"

    $dotNetExeArgs = "build"
    Start-Process -FilePath $dotNetExeFile -ArgumentList $dotNetExeArgs -WorkingDirectory $siteDir -Wait -NoNewWindow -PassThru | Out-Null

    if (!(Test-Path $applicationFile))
    {
        Write-Error ("Application file '{0}' doesn't exist" -f $applicationFile)
        exit 1
    }
}


# Start VS IIS
# ------------

Write-Output ("Start application file '{0}'" -f $applicationFile)

# start vs iis launcher
$vsIisExeLauncherArgs = "-p ""$dotNetExeFile"" -a ""exec \""$applicationFile\"""" -pidFile ""$pidFile"" -wd ""$siteDir"""
Start-Process -FilePath $vsIisExeLauncherFile -ArgumentList $vsIisExeLauncherArgs -WorkingDirectory $siteDir -Wait -NoNewWindow -PassThru | Out-Null