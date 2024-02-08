Hangfire.Build
==============

[![Build status](https://ci.appveyor.com/api/projects/status/8q3bq9egdknbe637?svg=true)](https://ci.appveyor.com/project/odinserj/hangfire-build)

Psake tasks and functions for building Hangfire projects with ease, including the following tasks:

* Create NuGet packages with all files you want to include.
* Task to update common version of all projects in solution.
* Target different frameworks (net45, netstandard1.*, etc).
* Internalize assemblies with `ILRepack /internalize` (`ILRepack` NuGet package required).
* Run unit and integration tests from the command line.
* [AppVeyor](http://www.appveyor.com/) support – build version, pre-release packages for the [project feed](http://www.appveyor.com/docs/nuget#project-feeds) and simple build script.

Please see the Hangfire's [`psake-project.ps1`](https://github.com/HangfireIO/Hangfire/blob/dev/psake-project.ps1) file to see the results.
 
Installation
-------------

This project is being distributed as a solution-level NuGet package, so open your Package Manager Console window and execute the following command.

```
PM> Install-Package Hangfire.Build
```

After installing, there are some things to be done. Please go to the `packages\Hangfire.Build.*\tools` folder and copy the following files to the **project root folder**:

* `build.bat` – bootstrapper script you will call to start the build.
* `psake-project.ps1` – template script for your project, will contain build tasks.

Configuration
--------------

Hangfire.Build project uses convention over configuration to build the project. By default it expects that your directory structure looks like this:

* `.nuget` – a directory with solution-wide package config and `NuGet.exe` executable.
* `build` – (created automatically) folder for build artifacts.
* `nuspecs` – a directory where `*.nuspec` files of your project live.
* `packages` – a directory for NuGet packages for your project (this is by default in NuGet).
* `src` – a directory where your project sources live (in a subdirectories like `Hangfire.Core`).
* `tests` – a directory where your unit and integration tests live (in a subdirectories).

For a full example, you can see the main [Hangfire repository](https://github.com/HangfireIO/Hangfire).

### Tasks

For quick overview, sample Hangfire.Build project file is available [here](https://github.com/HangfireIO/Hangfire/blob/dev/psake-project.ps1). Tasks below provide only the base functionality.

#### `Clean` task

Cleans the build folder and executes `dotnet clean` for the with the given configuration.

#### `Compile` task

Depends on: `Clean`.

Simply build all the projects in the current directory, with the `dotnet build` command and the given configuration. There is no magic here, except perhaps integration with AppVeyor.

#### `Version` task

Updates `$src_dir\SharedAssemblyInfo.cs` (by default) file's `AssemblyVersion` value and `appveyor.yml` files's `version` setting with the given one.

### Functions

#### `Run-XunitTests` function

Requires `xunit.runners` NuGet package installed.

Arguments:
* *project*: String.

Executes XUnit runner for the given project. This function assumes that common project structure is being used, so it looks for the following assembly: `.\tests\{project}\bin\{configuration}\{project}.dll`.

Example:

```
Run-XunitTests "Hangfire.Core.Tests"
```

#### `Run-OpenCover` function

Requires `xunit.runners` and `OpenCover` NuGet package installed.

Arguments:
* *project*: String.
* *coverage_file*: String
* *coverage_filter*: String

Executes OpenCover with XUnit runner for the given project. This function assumes that common project structure is being used, so it looks for the following assembly: `.\tests\{project}\bin\{configuration}\{project}.dll`.

Resulting coverage file is merged with an existing one, so you can use multiple projects to get merged coverage report. Please keep in mind that it is up to you to remove the coverage report file to prevent merging with old reports.

Example:

```
$coverage_file = "coverage.xml"
$coverage_filter = "+[Hangfire.*]* -[*.Tests]* -[*]*.Annotations.* -[*]*.Dashboard.* -[*]*.Logging.* -[*]*.ExpressionUtil.*"

Remove-File $coverage_file
    
Run-OpenCover "Hangfire.Core.Tests" $coverage_file $coverage_filter
Run-OpenCover "Hangfire.SqlServer.Tests" $coverage_file $coverage_filter
Run-OpenCover "Hangfire.SqlServer.Msmq.Tests" $coverage_file $coverage_filter
```

#### `Repack-Assembly` function

Requires `ILRepack` NuGet package installed.

Arguments:
* *project*: String
* *assemblyies*: Array of String – list of assembly names to internalize (with no `.dll` suffix).
* *target*: String – target framework

Invokes `ILRepack /internalize` to merge the given assemblies with the project's main assembly. Main assembly file is resolved as `.\src\{project}\bin\{target}\{configuration}\{project}.*`, `.\src\{project}\bin\{configuration}\{target}\{project}.*` or `.\src\{project}\bin\{configuration}\{project}.*`. It is assumed that merging assemblies are located under the same folder as a main assembly.

After merging, the original project assembly is being overwritted with the result assembly.

Example:

```
Repack-Assembly "Hangfire.Core" @("NCrontab", "CronExpressionDescriptor", "Microsoft.Owin")
```

#### `Collect-*` functions

These function copy build artifacts to the `build` folder to simplify the building of NuGet packages and archive file generation.

**`Collect-Assembly {project} [{target}]`** copies the `*.dll`, `*.xml` and `*.pdb` files to the given build target folder. File names are resolved as `.\src\{project}\bin\{target}\{configuration}\{project}.*`, `.\src\{project}\bin\{configuration}\{target}\{project}.*` or `.\src\{project}\bin\{configuration}\{project}.*`.

Example: `Collect-Assembly "Hangfire.Core" "net45"`

**`Collect-Content {file}`** copies the given file to the `{build_dir}\Content` folder where `file` is a relative path to the project root.

Example: `Collect-Content src\Hangfire.SqlServer\Install.sql`

**`Collect-Tool {file}`** copies the given file to the `{build_dir}\Tools` folder where `file` is a relative path to the project root.

#### `Create-Package` function

Arguments:
* *nuspec* – nuspec filename without path and extension.
* *version* – the version of a resulting package.

This function executes `nuget pack nuspecs\{nuspec}.nuspec` command and places the result into the build folder. Before running `NuGet.exe` executable, it replaces all `%version%` substrings in a given nuspec files and replaces them with the given version. Starting from 0.3, it also replaces `%commit%` occurrences with the current commit hash to make source link work.

Example:

```
Create-Package "Hangfire.Build" "0.1.0"
```

#### `Create-Archive` function

Arguments:
* *name* – file name for resulting archive, excluding path and extension.

Generates a zip archive with all files in the build folder with the given name. Since version 0.4.0 it uses PowerShell's built-in [`Compress-Archive`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/compress-archive) cmdlet, so don't require external executables.

Example:

```
Create-Archive "Hangfire-$version"
```

#### `Sign-ArchiveContents` function

Arguments:
* *name* – file name of an archive, excluding path and extension.
* *project* - signing project slug on SignPath.
* *configuration* – artifacts configuration slug on SignPath.

Submits the given archive created with the `Create-Archive` function to SignPath for signing with the given project and artifacts configuration. For tag-based builds, signing policy name is `release-signing-policy`, for other builds, signing policy is `test-signing-policy`.

The command is synchronous and waits for the signing to be completed. After signing, a signed archive is automatically downloaded and extracted with replacing all the files in the `{build_dir}` directory with the signed ones.

#### `Get-SharedVersion` function

Returns the version defined in the `$src_dir\SharedAssemblyInfo.cs` file in `AssemblyVersion` attribute.

#### `Get-BuildVersion` function

Returns the version returned by the `Get-SharedVersion` and adds a pre-release suffix based on AppVeyor CI build number. If `APPVEYOR_REPO_TAG` environment variable is set, **no pre-release suffix** is being appended. Build number is being padded with `0` symbols.

#### `Get-PackageVersion` function

If called from a build on AppVeyor, triggered by an added tag that starts with "v$version", where $version is the same as returned by a `Get-BuildVersion` function (for safety reasons), then returns the rest of a tag, without the "v" letter. Otherwise returns build version.

For example, if you triggered a build by adding a tag `v1.6.0-beta4`, and current version in your `SharedAssemblyInfo.cs` file is `1.6.0`, then this function returns `1.6.0-beta4`. If your assembly info version is `1.5.0`, then `1.5.0` version is returned to prevent building newer versions by an accident.

Examples:

* `2.0.0-build-00132` – no `APPVEYOR_REPO_TAG`.
* `2.0.0` – `APPVEYOR_REPO_TAG` is set OR building locally.

Building
---------

This project itself is build with the `Hangfire.Build` scripts. So, after making the changes, please run the following command to build NuGet packages:

```
build
```

Contributing
-------------

Just make changes and create a pull request :) Please ensure that there is no breaking changes and it is not required to patch all current Hangfire projects.

License
--------

This project is licensed under the [MIT License](http://opensource.org/licenses/MIT).
