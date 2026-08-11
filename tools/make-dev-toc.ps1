<#
  make-dev-toc.ps1 - regenerate the gitignored dev loader from the shipped .toc.

  This dev checkout lives in a codename folder "<Name>Dev" so a live CurseForge "<Name>"
  install can sit beside it. WoW needs the .toc name to match the folder, so the folder needs
  <Name>Dev.toc: the shipped <Name>.toc with a "[DEV]" Title and Dev-suffixed SavedVariables
  (Core switches to them when the Title has "[DEV]"). Only ONE copy enabled at a time.
  Run after editing the shipped .toc:  pwsh tools/make-dev-toc.ps1

  Encoding matters here and gets this wrong quietly. Windows PowerShell's
  Get-Content defaults to the system ANSI codepage, so a UTF-8 em dash comes back
  as three Latin-1 characters and gets written out re-encoded -- the Notes line
  then reads "â€”" in the AddOns list. And Set-Content -Encoding utf8 adds a BOM,
  which swallows the "## Interface:" directive on the first line and leaves the
  dev build looking out of date. So: read as UTF-8 explicitly, write with no BOM.
#>
$ErrorActionPreference = 'Stop'
$repo     = Split-Path -Parent $PSScriptRoot
$codename = Split-Path -Leaf $repo
$shipName = $codename -replace 'Dev$',''
$shipToc  = $shipName + '.toc'
$ourFolder = 'Interface\AddOns\'
$out = Get-Content (Join-Path $repo $shipToc) -Encoding UTF8 | ForEach-Object {
    $line = $_ -replace '^(## Title: .+?)\s*$', '${1} [DEV]'

    # Any path into our own folder has to point at THIS folder. A line still
    # reading Interface\AddOns\<Name>\... resolves against the LIVE install
    # whenever one is present -- so the dev build would quietly wear the live
    # build's art and look perfectly correct while testing nothing.
    $line = $line.Replace($ourFolder + $shipName + '\', $ourFolder + $codename + '\')
    # Every name on the line, not just a lone one. A migration keeps the previous
    # name declared alongside the current one, and a loader that suffixed only the
    # first would leave the DEV build reading and writing a LIVE table.
    if ($line -match '^(## SavedVariables(?:PerCharacter)?: )(.+?)\s*$') {
        $prefix = $Matches[1]
        $names  = @($Matches[2] -split ',' | ForEach-Object { $_.Trim() -replace 'DB$','DevDB' })
        $line   = $prefix + ($names -join ', ')
    }
    $line
}
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $repo ($codename + '.toc')), $out, $noBom)
Write-Host ("Wrote " + $codename + ".toc  (dev loader: [DEV] title + Dev saved variables)")
