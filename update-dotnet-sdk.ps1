#! /usr/bin/pwsh
param(
    [Parameter(Mandatory = $true)][string] $GitHubToken,
    [Parameter(Mandatory = $false)][string] $Channel = "3.1",
    [Parameter(Mandatory = $false)][string] $GlobalJsonFile = "./global.json",
    [Parameter(Mandatory = $false)][string] $UserName = "",
    [Parameter(Mandatory = $false)][string] $UserEmail = "",
    [Parameter(Mandatory = $false)][string] $BranchName = "",
    [Parameter(Mandatory = $false)][string] $CommitMessage = "",
    [Parameter(Mandatory = $false)][switch] $SkipCommit,
    [Parameter(Mandatory = $false)][switch] $DryRun
)

function Get-Global-Json-Version([string]$FileName) {

    if (-Not (Test-Path $FileName)) {
        throw "Unable to find '$FileName'"
    }

    try {
        $JsonContent = Get-Json-From-File $FileName | Select-Object -expand "sdk" -ErrorAction SilentlyContinue
    }
    catch {
        throw "JSON file unreadable: '$FileName'"
    }

    $Version = $null

    if ($JsonContent) {

        Say-Verbose "JSON: $JsonContent"

        try {
            $JsonContent.PSObject.Properties | ForEach-Object {
                $PropertyName = $_.Name
                if ($PropertyName -eq "version") {
                    $Version = $_.Value
                }
            }
        }
        catch {
            throw "Unable to parse the SDK node in '$FileName'"
        }
    }
    else {
        throw "Unable to find the SDK node in '$FileName'"
    }

    if ($null -eq $Version) {
        throw "Unable to find the SDK:version node in '$FileName'"
    }

    return $Version
}

function Get-Latest-SDK-Version([string]$FileName) {

    if (-Not (Test-Path $FileName)) {
        throw "Unable to find '$FileName'"
    }

    try {
        $JsonContent = Get-Json-From-File $FileName | Select-Object -ErrorAction SilentlyContinue
    }
    catch {
        throw "JSON file unreadable: '$FileName'"
    }

    $Version = $null

    if ($JsonContent) {

        Say-Verbose "JSON: $JsonContent"

        try {
            $JsonContent.PSObject.Properties | ForEach-Object {
                $PropertyName = $_.Name
                if ($PropertyName -eq "latest-sdk") {
                    $Version = $_.Value
                }
            }
        }
        catch {
            throw "Unable to parse the root node in '$FileName'"
        }
    }
    else {
        throw "Unable to find the root node in '$FileName'"
    }

    if ($null -eq $Version) {
        throw "Unable to find the latest-sdk node in '$FileName'"
    }

    return $Version
}

function Get-Json-From-File([string]$FileName) {

    if (-Not (Test-Path $FileName)) {
        throw "Unable to find '$FileName'"
    }

    try {
        return Get-Content($FileName) -Raw | ConvertFrom-Json
    }
    catch {
        throw "JSON file unreadable: '$FileName'"
    }
}

function Say([string] $message) {
    Write-Host "update-dotnet-sdk: $message"
}

function Say-Verbose([string] $message) {
    Write-Verbose "update-dotnet-sdk: $message"
}

$CurrentSDKVersion = Get-Global-Json-Version $GlobalJsonFile

Say "Current .NET SDK version is $CurrentSDKVersion"

$ReleaseNotesUrl = "https://raw.githubusercontent.com/dotnet/core/master/release-notes/$Channel/releases.json"
$ReleaseNotesPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())

Say-Verbose "Downloading .NET $Channel release notes JSON from $ReleaseNotesUrl to $ReleaseNotesPath..."

$OldProgressPreference = $ProgressPreference
$ProgressPreference = "SilentlyContinue"

try {
    Invoke-WebRequest $ReleaseNotesUrl -OutFile $ReleaseNotesPath -UseBasicParsing
}
catch {
    Say "Cannot download $ReleaseNotesUrl"
    throw
}
finally {
    $ProgressPreference = $OldProgressPreference
}

$LatestSDKVersion = Get-Latest-SDK-Version $ReleaseNotesPath

Say "Latest .NET SDK version for channel '$Channel' is $LatestSDKVersion"

if ($CurrentSDKVersion -ge $LatestSDKVersion) {
    Say "The .NET SDK version specified by '$GlobalJsonFile' is up-to-date"
    return
}

Say-Verbose "Updating SDK version in '$GlobalJsonFile' to $LatestSDKVersion..."

$GlobalJson = Get-Json-From-File $GlobalJsonFile
$GlobalJson.sdk.version = $LatestSDKVersion

if ($DryRun) {
    Say "Skipped update of SDK version in '$GlobalJsonFile' to $LatestSDKVersion"
}
else {
    $GlobalJson | ConvertTo-Json | Set-Content -Path $GlobalJsonFile
    Say "Updated SDK version in '$GlobalJsonFile' to $LatestSDKVersion"
}

if ($UserName) {
    if ($DryRun) {
        Say "Skipped update of git user name to '$UserName'"
    }
    else {
        git config user.name $UserName
        Say "Updated git user name to '$UserName'"
    }
}

if ($UserEmail) {
    if ($DryRun) {
        Say "Skipped update of git user email to '$UserEmail'"
    }
    else {
        git config user.email $UserEmail
        Say "Updated git user email to '$UserEmail'"
    }
}

if (-Not $BranchName) {
    $BranchName = "update-dotnet-sdk-$LatestSDKVersion".ToLowerInvariant()
}

if (-Not $CommitMessage) {
    $CommitMessage = "Update .NET SDK`n`nUpdate .NET SDK to version $LatestSDKVersion."
}

Say-Verbose "Commit message: $CommitMessage"

if ($DryRun) {
    Say "Skipped git commit for SDK update on branch $BranchName"
}
else {

    git checkout -b $BranchName | Out-Null
    Say-Verbose "Created git branch $BranchName"

    git add $GlobalJsonFile | Out-Null
    Say-Verbose "Staged git commit for '$GlobalJsonFile'"

    git commit -m $CommitMessage | Out-Null
    $GitSha = (git log --format="%H" -n 1 | Out-String).Substring(0, 7)

    Say "Commited .NET SDK update to git ($GitSha)"
}
