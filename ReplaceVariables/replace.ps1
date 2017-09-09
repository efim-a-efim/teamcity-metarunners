$env:TEAMCITY_BUILD_PROPERTIES_FILE = '.\conf'

[xml]$doc = Get-Content -LiteralPath ($env:TEAMCITY_BUILD_PROPERTIES_FILE + '.xml') -Encoding UTF8
$parameters = $doc.properties.entry | ForEach-Object -Begin {$ret = @{}} -Process {$ret.Add($_.key, $_.InnerText)} -End {$ret}

Write-Host "##teamcity[blockOpened name='Available variables']"
$parameters
Write-Host "##teamcity[blockClosed name='Available variables']"

@'
.\App.config
.\app.json
'@ -split '[\r|\n]' | Where-Object {$_ -notmatch '^[\s|\r|\n]*$'} | foreach-object {
	resolve-path $_ | foreach-object { 
		Write-Host "##teamcity[blockOpened name='File $_']"
		$content = (Get-Content -Path $_) -join "`n"
		foreach ($k in $parameters.Keys){
			if ($content -match '#{'+$k+'}') {
				Write-Host "Variable $k"
				$content = $content.Replace('#{'+$k+'}', $parameters[$k])
			}
		}
		$content | Set-Content -Path $_
		Write-Host "##teamcity[blockClosed name='File $_']"
	}
}



