Properties {
    $solution = "Hangfire.sln"
}

Include "packages\Hangfire.Build.*\psake-common.ps1"

Task Default -Depends Compile