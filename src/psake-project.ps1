Properties {
    $solution = "Hangfire.sln"
}

Include "packages\Hangfire.Build.*\tools\psake-common.ps1"

Task Default -Depends Compile