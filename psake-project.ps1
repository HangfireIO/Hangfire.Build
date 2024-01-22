Include "src\psake-common.ps1"

Task Default -Depends Pack

Task Collect -Depends CleanBuild -Description "Copy all artifacts to the build folder." {
    Collect-Tool "src\psake-common.ps1"
    Collect-Tool "src\psake-project.ps1"
    Collect-Tool "build.bat"
}

Task Pack -Depends Collect -Description "Create NuGet package." {
    Create-Package "Hangfire.Build" "0.3.2"
}
