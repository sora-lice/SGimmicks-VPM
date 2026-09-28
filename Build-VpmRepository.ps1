param(
    [string]$Version = "2.1.0",
    [string]$GitHubOwner = "YOUR_GITHUB_NAME",
    [string]$RepositoryName = "SGimmicks-VPM",
    [switch]$SiteOnly
)

$ErrorActionPreference = "Stop"

$repositoryRoot = $PSScriptRoot
$sourceProject = Join-Path (Split-Path $repositoryRoot -Parent) "SGimmicksPackageProject"
$packageId = "com.ysasa.sgimmicks"
$packageRoot = Join-Path $repositoryRoot "source\$packageId"
$docsRoot = Join-Path $repositoryRoot "docs"
$releaseRoot = Join-Path $docsRoot "packages"
$templateRoot = Join-Path $repositoryRoot "templates"
$baseUrl = "https://$GitHubOwner.github.io/$RepositoryName"
$packageUrl = "$baseUrl/packages/$packageId-$Version.zip"

function Write-RepositorySite {
    $htmlTemplate = Get-Content -LiteralPath (Join-Path $templateRoot "index.html") -Raw
    $html = $htmlTemplate.Replace("{{REPOSITORY_URL}}", "$baseUrl/index.json")
    $html = $html.Replace("{{VERSION}}", $Version)
    $html = $html.Replace("{{PACKAGE_URL}}", $packageUrl)
    $html | Set-Content -LiteralPath (Join-Path $docsRoot "index.html") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $docsRoot ".nojekyll") -Value "" -Encoding ASCII
}

if ($SiteOnly) {
    Write-RepositorySite
    Write-Host "Repository website: $baseUrl/"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceProject)) {
    throw "SGimmicksPackageProjectが見つかりません: $sourceProject"
}

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SGimmicks") -Destination $packageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SGimmicks.meta") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\CastTimerGimmick") -Destination $packageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\CastTimerGimmick.meta") -Destination $packageRoot

$serializedRoot = Join-Path $packageRoot "SerializedUdonPrograms"
New-Item -ItemType Directory -Path $serializedRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SerializedUdonPrograms.meta") -Destination $packageRoot
$castTimerPrograms = @(
    "240acd391966f3d4c8efcf3aabbbf842.asset",
    "93050332db0d28a4a82be47a9d88944c.asset",
    "dafaae08dca2c044ba4cd26d0cd2c2d3.asset"
)
foreach ($assetName in $castTimerPrograms) {
    Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SerializedUdonPrograms\$assetName") -Destination $serializedRoot
    Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SerializedUdonPrograms\$assetName.meta") -Destination $serializedRoot
}

# unitypackage専用ビルダーはVPM利用時には不要で、Packages配下へ書き込もうとするため除外する。
$legacyBuilders = @(
    (Join-Path $packageRoot "SGimmicks\Editor\SGPackageBuilder.cs"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGPackageBuilder.cs.meta"),
    (Join-Path $packageRoot "CastTimerGimmick\Editor") ,
    (Join-Path $packageRoot "CastTimerGimmick\Editor.meta")
)
foreach ($legacyBuilder in $legacyBuilders) {
    if (Test-Path -LiteralPath $legacyBuilder) {
        Remove-Item -LiteralPath $legacyBuilder -Recurse -Force
    }
}

Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asmdef") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asmdef.meta") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Editor.asmdef") -Destination (Join-Path $packageRoot "SGimmicks\Editor")
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Editor.asmdef.meta") -Destination (Join-Path $packageRoot "SGimmicks\Editor")

$manifest = [ordered]@{
    name = $packageId
    displayName = "SGimmicks"
    version = $Version
    unity = "2022.3"
    description = "PC向けVRChatワールド用ギミック集。テレポート、VIPスポーン、監視カメラ、部屋番号/RTab、強制テレポート、内線、照明、メッセージボード、キャストタイマー、囁き声判定を収録。"
    url = $packageUrl
    vpmDependencies = [ordered]@{
        "com.vrchat.worlds" = "3.10.x"
    }
    author = [ordered]@{
        name = "ysasa"
        email = "ysasa@users.noreply.github.com"
        url = "https://github.com/$GitHubOwner"
    }
    legacyFolders = [ordered]@{
        "Assets\SGimmicks" = "4266535577e7c06439e201b5910eba59"
        "Assets\CastTimerGimmick" = "b78e7576d609426409f7786d6e3ecab6"
    }
    legacyFiles = [ordered]@{
        "Assets\SerializedUdonPrograms\240acd391966f3d4c8efcf3aabbbf842.asset" = "7922c4f787df3814db6aa440c1f40714"
        "Assets\SerializedUdonPrograms\93050332db0d28a4a82be47a9d88944c.asset" = "16cd99473ce622943a22364e2b4abfc8"
        "Assets\SerializedUdonPrograms\dafaae08dca2c044ba4cd26d0cd2c2d3.asset" = "c1dc1a81b997a9c449cf14af048e32d0"
    }
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $packageRoot "package.json") -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $templateRoot "package.json.meta") -Destination $packageRoot

$zipPath = Join-Path $releaseRoot "$packageId-$Version.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$listingManifest = [ordered]@{}
foreach ($key in $manifest.Keys) {
    $listingManifest[$key] = $manifest[$key]
}
$listingManifest["zipSHA256"] = $hash

$indexPath = Join-Path $docsRoot "index.json"
if (Test-Path -LiteralPath $indexPath) {
    $repository = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json -AsHashtable
} else {
    $repository = [ordered]@{
        name = "SGimmicks VPM Repository"
        id = "com.ysasa.sgimmicks.repository"
        url = "$baseUrl/index.json"
        author = "ysasa"
        description = "PC向けVRChatワールド用ギミック集 SGimmicks のVPMリポジトリ"
        packages = [ordered]@{}
    }
}

$repository.name = "SGimmicks VPM Repository"
$repository.id = "com.ysasa.sgimmicks.repository"
$repository.url = "$baseUrl/index.json"
$repository.author = "ysasa"
$repository.description = "PC向けVRChatワールド用ギミック集 SGimmicks のVPMリポジトリ"
if (-not $repository.Contains("packages")) {
    $repository.packages = [ordered]@{}
}
if (-not $repository.packages.Contains($packageId)) {
    $repository.packages[$packageId] = [ordered]@{ versions = [ordered]@{} }
}
if (-not $repository.packages[$packageId].Contains("versions")) {
    $repository.packages[$packageId].versions = [ordered]@{}
}
$repository.packages[$packageId].versions[$Version] = $listingManifest
$repository | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $indexPath -Encoding UTF8

Write-RepositorySite

Write-Host "VPM package: $zipPath"
Write-Host "Repository JSON: $indexPath"
Write-Host "VCC repository URL: $baseUrl/index.json"
Write-Host "SHA256: $hash"
