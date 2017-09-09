$appVersions=@{}
@'
%system.AppVersions%
'@ -split '[\r|\n]' | Where-Object {$_ -notmatch '^[\s|\r|\n]*$'} | foreach-object { 
  ($paramName,$paramValue)=$($_ -split '\s*=>\s*',2,"RegexMatch,IgnoreCase,Multiline"); 
  If ($paramValue -NotContains '{0}'){$paramValue = "${paramValue}.{0}"}
  $appVersions[$paramName] = $paramValue
}

# This gets the name of the current Git branch. 
$branch = "%teamcity.build.branch%"
if ($branch.Contains("/")) {
  $branch = ($branch -split '/')[-1]
}

If ($appVersions.ContainsKey($branch) -eq $True){
	$buildNumber = $appVersions[$branch] -f '%build.counter%'
} elseif ($branch -Match '\d+\.\d+\.\d+') {
	$buildNumber = "${branch}.%build.counter%"
} elseif($branch -Match '\d+\.\d+') {
	$buildNumber = "${branch}.0.%build.counter%"
} else {
	$buildNumber = "%build.counter%"
}

Write-Host $("##teamcity[buildNumber '{0}']" -f $buildNumber)

# Patch AssemblyInfo
Write-Host "##teamcity[compilationStarted compiler='Patching AssemblyInfo files']"
Get-ChildItem -Recurse -Filter '*AssemblyInfo.cs' -Path '%teamcity.build.checkoutDir%' | Foreach-Object {
	Write-Host $("##teamcity[message text='Patching {0}']" -f $_.FullName)
	(Get-Content $_.FullName) | foreach-object {
		($_ -replace 'AssemblyVersion\("\d+\.\d+\.\d+\.\d+"\)', $('AssemblyVersion("{0}")' -f $buildNumber)) -replace 'AssemblyFileVersion\("\d+\.\d+\.\d+\.\d+"\)', $('AssemblyFileVersion("{0}")' -f $buildNumber)
	} | Set-Content $_.FullName
}
Write-Host "##teamcity[compilationFinished compiler='Patching AssemblyInfo files']"