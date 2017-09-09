Set-Location -Path '%teamcity.build.workingDir%'

# Prepare
[xml]$src = [xml]''
$dstPackageName=$([System.IO.Path]::GetFileNameWithoutExtension('%DestinationPackage%'))
$cfgFile = Join-Path -Path '%system.teamcity.build.workingDir%' -ChildPath "$dstPackageName.%build.number%.xml"
$pkgTemp = Join-Path -Path '%system.teamcity.build.workingDir%' -ChildPath "$dstPackageName"

# Pre-build cleanup
Write-Host "##teamcity[blockOpened name='Pre-build cleanup']"
Write-Host "##teamcity[progressStart 'Pre-build cleanup']"
If (Test-Path $cfgFile) { Remove-Item -Path $cfgFile -Force }
If (Test-Path $pkgTemp) { Remove-Item -Path $pkgTemp -Force -Recurse }
Write-Host "##teamcity[progressStop 'Pre-build cleanup']"
Write-Host "##teamcity[blockClosed name='Pre-build cleanup']"

@'
%InputPackages%
'@ -split '[\r|\n]' | Where-Object {$_ -notmatch '^[\s|\r|\n]*$'} | foreach-object { 
  ($package, $internalPath)=$($_ -split '\s*=>\s*',2,"RegexMatch,IgnoreCase,Multiline");

  If (-Not (Test-Path $package)) {
    If (-Not('%SkipIfNotExists%' -eq 'true')) {
      Write-Host "##teamcity[message text='Source package does not exist' status='ERROR' errorDetails='Source package does not exist']"
      If ('%Cleanup%' -eq 'true') {
        Write-Host "##teamcity[blockOpened name='Cleanup']"
        If (Test-Path $cfgFile) { Remove-Item -Path $cfgFile -Force }
        If (Test-Path $pkgTemp) { Remove-Item -Path $pkgTemp -Force -Recurse }
        Write-Host "##teamcity[blockClosed name='Cleanup']"
      }
      Write-Host "##teamcity[buildProblem text='Source package does not exist']"
      Exit 1
    }
    Write-Host "##teamcity[message text='Source package does not exist, skipping' status='WARNING']"
  }

  Write-Host "##teamcity[blockOpened name='Extract package $package']"
  Write-Host "##teamcity[progressStart 'Extract package $package']"

  # Extract package config
  Write-Host "##teamcity[message text='Extracting configuration...']"
  [xml]$cfg = [xml]( &"%system.MSDeploy.BinaryPath%" -verb:getParameters -xml -source:package="$package")
  Foreach ($Node in $cfg.DocumentElement.ChildNodes) {
    $src.DocumentElement.AppendChild($src.ImportNode($Node, $true))
  }
  Write-Host "##teamcity[message text='Done']"
  
  # Extract package content
  Write-Host "##teamcity[message text='Extracting files...']"
  $dstPath = Join-Path -Path $pkgTemp -ChildPath $internalPath
  If (-Not (Test-Path $dstPath)) {
    New-Item -ItemType Directory -Path $dstPath -Force
  }
  & "%system.MSDeploy.BinaryPath%" -verb:sync -source:package=$package -dest:dirPath=$dstPath
  Write-Host "##teamcity[message text='Done']"

  Write-Host "##teamcity[progressFinish 'Extract package $package']"
  Write-Host "##teamcity[blockClosed name='Extract package $package']"
}

Write-Host "##teamcity[blockOpened name='Create resulting package']"
Write-Host "##teamcity[progressStart 'Create resulting package']"
# Save complete combined XML config
[xml]$src = [xml]$srcOutput.output.InnerXml
$src.Save($cfgFile)
& "%system.MSDeploy.BinaryPath%" -verb:sync -source:dirPath=$pkgTemp -dest:package=%DestinationPackage% -declareParamFile:$cfgFile %Parameters%
Write-Host "##teamcity[progressFinish 'Create resulting package']"
Write-Host "##teamcity[blockClosed name='Create resulting package']"

If ('%Cleanup%' -eq 'true') {
    Write-Host "##teamcity[blockOpened name='Cleanup']"
    If (Test-Path $cfgFile) { Remove-Item -Path $cfgFile -Force }
    If (Test-Path $pkgTemp) { Remove-Item -Path $pkgTemp -Force -Recurse }
    Write-Host "##teamcity[blockClosed name='Cleanup']"
}