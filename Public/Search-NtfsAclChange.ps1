function Search-NtfsAclChange {
<#
.Synopsis
    Get the report of changes in the NTFS ACL in the folder structure
.DESCRIPTION
    The Search-NtfsAclChange function will report of any changes of the folder structure on the given path. 
    Depth of the search can be limited with a 'DepthLimit' parameter
.EXAMPLE
    Search-NtfsAclChange -Path C:\Users
    Just make the run with default settings (DepthLimit = 99)
.EXAMPLE
    Search-NtfsAclChange -Path C:\Users -DepthLimit 10 -IncludeFiles
    Include files, limit search depth to 10 levels
.EXAMPLE
    Search-NtfsAclChange -Path C:\Users -DepthLimit 10 -IncludeFiles | Tee-Object -Variable Report | Format-Table
    Include files, limit search depth to 10 levels, add all output objects to the $Report variable and display interactively
.EXAMPLE
    $report = Search-NtfsAclChange -Path C:\Users -DepthLimit 10 -IncludeFiles
    $report | Out-GridView -PassThru | % { $gi = Get-Item $_.path ; if ($gi.PSIsContainer) {start $gi.FullName} else {start $gi.DirectoryName}}
    Same, but display result in the Out-GridView and open destination folder if selected in ogv.
.INPUTS
    [string] as a starting path
.OUTPUTS
    [PSCustomObject]
.NOTES
    Based on the idea in https://www.reddit.com/r/PowerShell/comments/az9rqj/looking_for_faster_getchilditem_w_error_handling/ei6f9zd/
    Uses direct call to the Get-Acl (without intermediate Get-Item) to speed up things a little.
    Does not compares ACEs directly, but judges from the presense or absence of inherited or uninherited ACEs, to speed up things A LOT.
    Not compatible with PS -lt 3, but can rewritten easly
.FUNCTIONALITY
    Get a custom object when NTFS ACL of an object differs from the ACL of its parent
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
[Alias('Report-NTFSPermissions')]
param (
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    # Path to start from
    $Path = '.',
    # How many levels down should be checked
    [int]$DepthLimit = 99,
    # Include all objects (files) in the search
    [switch]$IncludeFiles,
    # Internal parameter
    [int]$CurrentDepth = 0,
    # Internal parameter
    $ParentAcl = $null,
    # Internal parameter
    $PSIsContainer = $true
    )
    #don't uncomment on a big volumes - this considerably slows down the process
    #Write-Progress -Activity 'reporing' -Status "$path"
#    $PSBoundParameters
    $state = [pscustomobject][ordered]@{
        path = $path
        aceAdded = [int]-1
        aceInherited = [int]-1
        depth = $CurrentDepth
        brokenInheritance = $false
        ownerChanged = $false
        accessError = $false
        ACL = $null
        shouldBeOutput = $false
        }
    
    try {
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        }
    catch {
        $state.accessError = $true
        $state.shouldBeOutput = $true
        }

    if ($state.accessError -eq $false) {
        $state.ACL = $acl
        $state.aceAdded = [int]($acl.Access.IsInherited.Where({$_ -eq $false}).count)
        $state.aceInherited = [int]($acl.Access.IsInherited.Where({$_ -eq $true}).count)

        if ((    $state.aceAdded -gt 0) -and ($state.aceInherited -gt 0)) {
            #inheritance is enabled, but there is new ACEs
            $state.shouldBeOutput = $true
            }
        elseif (($state.aceAdded -gt 0) -and ($state.aceInherited -eq 0)) {
            #inheritance is broken
            $state.brokenInheritance = $true
            $state.shouldBeOutput = $true
            }
    
        if ($ParentAcl.owner -ne $acl.Owner) {
            $state.ownerChanged = $true
            $state.shouldBeOutput = $true
            }
        }

    if ($state.shouldBeOutput) {
        Select-Object -InputObject $state -Property * -ExcludeProperty shouldBeOutput
        }

    if ($CurrentDepth -eq $depthLimit) {
        break
        }
        
    if (($state.accessError -eq $false) -and $PSIsContainer) {
        #PSIsContainer allows to avoid the redundant queries to the files
        $gciSplat = @{
            LiteralPath = $Path
            Directory = -not $IncludeFiles
            }
        $gci = Get-ChildItem @gciSplat
        
        foreach ($childItems in $gci) {
            #and here splatting allows to cast the $IncludeFiles without using if ($IncludeFiles)
            $splat = @{
                Path = $childItems.FullName
                DepthLimit = $DepthLimit
                CurrentDepth = $CurrentDepth + 1
                ParentAcl = $acl
                IncludeFiles = $IncludeFiles
                PSIsContainer = $childItems.PSIsContainer
                }
            Search-NtfsAclChange @splat
            }
        }
}

