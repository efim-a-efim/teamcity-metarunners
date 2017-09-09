Param(
    [parameter()][ValidateSet("CODE", "FILE")]
    [string]$Type = '%meta_powershell_script_type%',

    [parameter()][ValidateNotNullOrEmpty()]
    [string]$ComputerName = '%meta_powershell_remote_host%',

    [parameter()][ValidateNotNullOrEmpty()]
    [string]$User = '%meta_powershell_remote_user%',

    [parameter()]
    [string]$Password = '%meta_powershell_remote_password%',

    $Content = @'
%meta_powershell_script_code%
'@
)
function EscapeServiceMessage ([string]$message) {
    $message = $message.Replace("|", "||")
    $message = $message.Replace("`n", "|n")
    $message = $message.Replace("`r", "|r")
    $message = $message.Replace("'", "|'")
    $message = $message.Replace("[", "|[")
    $message = $message.Replace("]", "|]")
    $message
}

# set buffer to 500 chars wide to prevent unneeded wraps
try {
    $rawUI = (Get-Host).UI.RawUI
    $m = $rawUI.MaxPhysicalWindowSize.Width
    $rawUI.BufferSize = New-Object Management.Automation.Host.Size ([Math]::max($m, 500), $rawUI.BufferSize.Height)
    $rawUI.WindowSize = New-Object Management.Automation.Host.Size ($m, $rawUI.WindowSize.Height)
} catch {}

trap {
    $message = EscapeServiceMessage $_
    Write-Host "##teamcity[buildStatus text='$message' status='FAILURE']"
    Write-Host "##teamcity[message text='$message' status='ERROR']"
    exit 1
}

# Determine hosts
$computers = @( $ComputerName -split '\s*,\s*', 0, 'RegexMatch' )

$scriptPath = '';
if ($Type -eq 'CODE') {
    $tempDir ='%system.teamcity.build.tempDir%'
    $tempFile = [Guid]::NewGuid().ToString("n") + '.ps1'
    $scriptPath = join-path -Path $tempDir -ChildPath $tempFile

    Set-Content -LiteralPath $scriptPath -Value $Content
} else {
    $scriptPath = $Content;
}

Write-Host "Script file: $scriptPath"
$scriptInfo = Get-Command -Name $scriptPath

$arguments = @{}
if ($scriptInfo.Parameters -ne $null) {
    # load system parameters from TeamCity
    [xml]$doc = Get-Content -LiteralPath ($env:TEAMCITY_BUILD_PROPERTIES_FILE + '.xml') -Encoding UTF8
    $parameters = $doc.properties.entry | ForEach-Object -Begin {$ret = @{}} -Process {$ret.Add($_.key, $_.InnerText)} -End {$ret}
    
    foreach ($param in $scriptInfo.Parameters.GetEnumerator()) {
        if ($parameters.ContainsKey($param.Key)) {
            $arguments.Add($param.Key, $parameters[$param.Key]);
        }
    }
} else {
    Write-Host "Failed to discover script parameters"
}

Write-Host "Arguments:"
Write-Host ($arguments | Format-Table -AutoSize | Out-String)


Write-Host "Running script on hosts $($computers -join ',') from user $User"
# Here starts remoting
Write-Host "##teamcity[message text='Connecting to host(s): $($computers -join ',')']"
if ($Password) {
    Write-Host "##teamcity[message text='Using Basic authentication with User = $User']"
    $credential = new-object -typename System.Management.Automation.PSCredential `
        -argumentlist $User, $(ConvertTo-SecureString $Password -AsPlainText -Force)
    $session = New-PSSession -ComputerName $computers -Credential $credential
} else {
    # use windows auth
    Write-Host "##teamcity[message text='Using Windows authentication']"
    $session = New-PSSession -ComputerName $computers
}
Write-Host "##teamcity[message text='Running script $scriptPath with arguments $(EscapeServiceMessage $($arguments -join ' '))']"
Invoke-Command -Session $session -FilePath $scriptPath -ArgumentList $arguments

Write-Host "##teamcity[message text='Cleaning up']"
Remove-PSSession $session
Remove-Item -Force $scriptPath
