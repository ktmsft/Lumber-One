# Builds the upload zip.
#
#   .\tools\build.ps1
#
# Produces dist\LumberOne-<version>.zip with a single top-level LumberOne\
# folder holding LumberOne.toc. WoW loads a folder only when it contains a .toc
# named after it, so those two names are locked together and to the addon's name.
#
# Ships only what the addon loads, plus the readme, changelog and licence. tools\
# and the dev loader are development-only and have no business in a player's
# AddOns folder.

param([switch] $SkipTests)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$name = 'LumberOne'

# --- version comes from the TOC, so there's one source of truth ---
$toc = Get-Content (Join-Path $root "$name.toc") -Encoding UTF8
$version = ($toc | Select-String '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$interface = ($toc | Select-String '^## Interface:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
"$name $version  (Interface $interface)"

# --- does that interface number match the client actually installed? ---
#
# The number comes from .build.info and is never copied from another addon.
# Checking it here makes that mechanical. A warning rather than an error on
# purpose: building for the previous patch is legitimate, and the client updates
# on Blizzard's schedule.
#
# The TOC may declare SEVERAL versions -- one build covering the live client and
# a PTR -- so the test is that the installed client is somewhere in the list, not
# that it equals it. Setting a single future number here once made the live
# client refuse to load the addon outright.
$declared = @($interface -split ',' | ForEach-Object { $_.Trim() })
$clientRoot = $root
1..4 | ForEach-Object { $clientRoot = Split-Path -Parent $clientRoot }
$buildInfo = Join-Path $clientRoot '.build.info'
if (Test-Path $buildInfo) {
	$rows = Get-Content $buildInfo
	$headers = $rows[0] -split '\|'
	$verColumn = -1
	for ($i = 0; $i -lt $headers.Count; $i++) {
		if ($headers[$i] -like 'Version!*') { $verColumn = $i }
	}
	if ($verColumn -ge 0 -and $rows.Count -gt 1) {
		$build = ($rows[1] -split '\|')[$verColumn]
		if ($build -match '^(\d+)\.(\d+)\.(\d+)') {
			# 12.0.7.68974 -> 120007. Minor and patch get two digits each.
			$expected = [int]$Matches[1] * 10000 + [int]$Matches[2] * 100 + [int]$Matches[3]
			if ($declared -notcontains "$expected") {
				Write-Warning "TOC declares $interface but the installed client is $build (= $expected)."
			} else {
				"client: $build is covered ($expected in $interface)"
			}
		}
	}
}

# --- guard: no byte-order mark on the .toc ---
#
# WoW reads the .toc line by line looking for "## Directive:" at the start of a
# line. A UTF-8 BOM sits in front of the very first one, so "## Interface" is not
# seen and the addon reports as out of date -- silently. Windows PowerShell's
# Set-Content -Encoding utf8 writes a BOM, which is how it got into the dev
# loader for a whole release. Checked here because the .toc is copied byte for
# byte into the zip.
$tocBytes = [System.IO.File]::ReadAllBytes((Join-Path $root "$name.toc"))
if ($tocBytes.Length -ge 3 -and $tocBytes[0] -eq 0xEF -and $tocBytes[1] -eq 0xBB -and $tocBytes[2] -eq 0xBF) {
	throw "$name.toc starts with a UTF-8 BOM - WoW will not read '## Interface'. Rewrite it with UTF8Encoding(`$false)."
}
"toc:   no BOM"

# --- does it compile? ---
$shippedLua = @('Data.lua', 'Core.lua', 'UI.lua', 'Options.lua')
if (-not $SkipTests) {
	$luajit = Get-Command luajit -ErrorAction SilentlyContinue
	if (-not $luajit) {
		Write-Warning "luajit not found - skipping the compile check. Install it or pass -SkipTests to silence this."
	} else {
		foreach ($f in $shippedLua) {
			& luajit -bl (Join-Path $root $f) > $null 2>$null
			if ($LASTEXITCODE -ne 0) { throw "$f does not compile" }
		}
		"lua:   $($shippedLua.Count) file(s) compile"
	}
}

# --- guard: the licence that ships must be the one the TOC claims ---
#
# This addon carried an MIT LICENSE.txt alongside an All Rights Reserved LICENSE
# for a release, and the MIT one is what went out -- so the published build gave
# away rights the TOC said were reserved. A licence grant cannot be taken back
# from anyone who already has it, so the only fix is never shipping the wrong one
# again. Hence a guard rather than a comment.
$licenseTag = ($toc | Select-String '^## X-License:\s*(.+)$')
if ($licenseTag) {
	$claimed = $licenseTag.Matches[0].Groups[1].Value.Trim()
	$licenseText = Get-Content (Join-Path $root 'LICENSE') -Encoding UTF8 -Raw
	if ($claimed -match 'All Rights Reserved' -and $licenseText -match 'MIT License') {
		throw "LICENSE is the MIT text but the TOC claims '$claimed'."
	}
	"lic:   LICENSE agrees with '$claimed'"
}
if (Test-Path (Join-Path $root 'LICENSE.txt')) {
	throw "LICENSE.txt is still present - it is the stale MIT text. Delete it; LICENSE is the one that ships."
}

# --- what ships ---
$files = @("$name.toc") + $shippedLua + @('README.md', 'LICENSE')
foreach ($f in @('CHANGELOG.md')) {
	if (Test-Path (Join-Path $root $f)) { $files += $f }
}

# Art. The skins live in images\ (backgrounds) and images\keyed\ (the plank and
# rail pieces, with their white matte keyed back to transparency). Both ship.
# The .png originals stay local -- WoW loads only TGA/BLP, so a shipped PNG is
# dead weight the client will not read.
$art = @(Get-ChildItem (Join-Path $root 'images') -Filter *.tga -File -Recurse -ErrorAction SilentlyContinue)
foreach ($t in $art) {
	$rel = $t.FullName.Substring((Join-Path $root '').Length)
	$files += $rel
}

# --- guard: every shipped TGA must be one the client will actually load ---
#
# RLE-compressed TGA draws blank and WoW says nothing about it, so that one is a
# hard error. Bit depth likewise.
#
# Deliberately NOT checked: power-of-two dimensions. The other addons on the
# shelf enforce that, but their art is generated to size -- there the rule is
# really "the generator did its job". This addon's art is hand-cropped, every
# piece of it is non-power-of-two (377x373, 921x166, 69x386 ...), and it has
# drawn correctly since 1.0.0. Modern clients load NPOT textures.
#
# The one place it could theoretically bite is a rail with REPEAT wrap, since
# tiling is what makes dimensions matter -- and the Nature skin does exactly that
# with a 76x341 rail. That was written and verified in 1.0.2 ("its side rails now
# repeat instead of stretching"), so it works in practice. Noted rather than
# guarded: a check that fails a build for art that demonstrably renders is worse
# than no check.
foreach ($t in $art) {
	$h = New-Object byte[] 18
	$fs = [System.IO.File]::OpenRead($t.FullName)
	try { $null = $fs.Read($h, 0, 18) } finally { $fs.Dispose() }

	$datatype = $h[2]
	$bpp = $h[16]

	if ($datatype -ne 2) { throw "$($t.Name): TGA datatype $datatype - must be 2 (uncompressed); RLE draws blank" }
	if ($bpp -ne 32 -and $bpp -ne 24) { throw "$($t.Name): $bpp-bit TGA - must be 24 or 32" }
}
"art:   $($art.Count) TGA(s), all uncompressed"

# --- guard: every piece each skin names must actually be here ---
#
# UI.lua builds its texture paths by concatenation -- IMG_PATH .. prefix .. "bg.tga"
# -- so no literal filename appears in the source to grep for. A skin whose prefix
# has no matching art loads fine and draws an EMPTY frame: no error, no warning,
# just a window with no border. So derive the filenames the same way UI.lua does
# and check each one exists.
$ui = Get-Content (Join-Path $root 'UI.lua') -Encoding UTF8 -Raw
$prefixes = @([regex]::Matches($ui, 'prefix\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
if ($prefixes.Count -eq 0) { throw "found no skin prefixes in UI.lua - has the SKINS table changed shape?" }
foreach ($p in $prefixes) {
	if (-not (Test-Path (Join-Path $root "images\${p}bg.tga"))) {
		throw "skin '$p' has no images\${p}bg.tga"
	}
	foreach ($piece in @('top', 'bottom', 'leftrail', 'rightrail')) {
		if (-not (Test-Path (Join-Path $root "images\keyed\$p$piece.tga"))) {
			throw "skin '$p' has no images\keyed\$p$piece.tga"
		}
	}
}
"art:   $($prefixes.Count) skin(s), every piece present"

# --- guard: the art path in UI.lua must point at the SHIPPED folder ---
#
# IMG_PATH is a hardcoded Interface\AddOns\<folder>\images\ string. In the dev
# checkout the folder is LumberOneDev, so a path left saying LumberOne resolves
# against the LIVE install whenever one is present -- the dev build then wears
# the live build's art and looks perfectly correct while testing nothing. What
# ships must name the shipped folder, whatever the checkout is called.
if ($ui -notmatch [regex]::Escape("Interface\\AddOns\\$name\\images\\")) {
	throw "UI.lua's IMG_PATH does not point at Interface\AddOns\$name\images\"
}
"art:   IMG_PATH points at $name"

# --- guard: the TOC's file list and the shipped file list must agree ---
#
# The TOC is what WoW actually loads, so it is the authority. Two ways to get this
# wrong, both silent: add a Lua file to the TOC and forget to ship it (the addon
# errors on load for everyone but you), or add one to the repo and forget to list
# it (it ships as dead weight and never loads).
$tocLua = @($toc | Where-Object { $_ -match '^\s*[^#\s].*\.lua\s*$' } | ForEach-Object { $_.Trim() })
$notShipped = @($tocLua | Where-Object { $files -notcontains $_ })
if ($notShipped.Count) {
	throw "the TOC loads files that aren't being shipped: $($notShipped -join ', ')"
}
$notLoaded = @($files | Where-Object { $_ -like '*.lua' -and $tocLua -notcontains $_ })
if ($notLoaded.Count) {
	throw "shipping Lua the TOC never loads: $($notLoaded -join ', ')"
}
"toc:   $($tocLua.Count) Lua file(s) loaded, all shipped"

$staging = Join-Path $dist $name
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

foreach ($f in $files) {
	$sourcePath = Join-Path $root $f
	if (-not (Test-Path $sourcePath)) { throw "missing required file: $f" }
	$destPath = Join-Path $staging $f
	$destDir = Split-Path -Parent $destPath
	if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
	Copy-Item $sourcePath $destPath
}

# --- zip ---
# Entries are written by hand rather than with Compress-Archive. That names entries
# using the platform separator, so on Windows PowerShell it emits "LumberOne\Core.lua".
# The zip spec mandates '/'. WoW and most unzippers tolerate backslashes, but it is
# not worth betting an upload on.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dist "$name-$version.zip"

$stream = [System.IO.File]::Open($zip, [System.IO.FileMode]::Create)
try {
	$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
	try {
		foreach ($file in Get-ChildItem $staging -Recurse -File | Sort-Object FullName) {
			$rel = $file.FullName.Substring($staging.Length + 1).Replace('\', '/')
			$entry = $archive.CreateEntry("$name/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
			$entryStream = $entry.Open()
			try {
				$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
				$entryStream.Write($bytes, 0, $bytes.Length)
			} finally { $entryStream.Dispose() }
		}
	} finally { $archive.Dispose() }
} finally { $stream.Dispose() }

Remove-Item $staging -Recurse -Force

# --- verify what we just wrote, rather than assume ---
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
	$names = $check.Entries | ForEach-Object { $_.FullName }
	$backslashes = @($names | Where-Object { $_ -like '*\*' })
	if ($backslashes.Count) { throw "zip has backslash separators: $($backslashes[0])" }
	$tops = @($names | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
	if ($tops.Count -ne 1 -or $tops[0] -ne $name) {
		throw "zip must contain exactly one top-level $name/ folder, found: $($tops -join ', ')"
	}
	# WoW finds the addon by the .toc named after its folder. If that entry is
	# missing the zip installs into a folder the client silently ignores.
	if ($names -notcontains "$name/$name.toc") {
		throw "zip has no $name/$name.toc - WoW would ignore the folder entirely"
	}
	# The dev loader must never ship: it carries [DEV] and the Dev saved variables,
	# so a player installing it would get an addon that looks wrong and writes to
	# the wrong table.
	if ($names -contains "$name/${name}Dev.toc") {
		throw "the dev loader is in the zip"
	}
	"zip:   $($names.Count) entries under $($tops[0])/, forward slashes ok"
} finally { $check.Dispose() }

$size = (Get-Item $zip).Length / 1KB
"`nBuilt: $zip"
"Size:  {0:N0} KB" -f $size
