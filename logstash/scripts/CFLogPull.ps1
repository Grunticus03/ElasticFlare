#Configuration Variables
$Path = "Logstash ingest folder"
$ArchivePath = 'Folder to save zip files to(exclude trailing slash)'
$SmtpFrom = "Sending email address for notification"
$SmtpTo = 'Recipient of email notification. To include more than one recipient, use following syntax "email1@example.com", "email2@example.com", "etc@example.com"'
$SmtpServer = "Hostname/IP of SMTP server"
$APIKey = "Global API Key"
$CFEmail = "CloudFlare admin email address for API call"
$OrgId = "Organization ID for audit log pulls"
# The following variables specify the timeframe to pull logs. As per the API documentation, https://api.cloudflare.com/#logs-received-logs-received,
# the ending time ($EM) must be at least 5 minutes prior to now. In addition, the total timeframe cannot exceed 1 hour
$SM = "Starting time number of minutes to go back - If it's 12:00 and you want logs starting at 11:50, set to 10"
$EM = "Ending time number of minutes to go back - This must be at least 5 minutes in the past."

#CloudFlare Enterprise Log Service (ELS) Pull
$D = Get-Date
$T = (Get-Date ($D) -Format MMddyyy_HHmmss)
$S = [Math]::Floor([decimal](Get-Date($D).AddMinutes(-$($SM)).ToUniversalTime()-uformat "%s"))
$E = [Math]::Floor([decimal](Get-Date($D).AddMinutes(-$($EM)).ToUniversalTime()-uformat "%s"))
#Force PowerShell to use TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12
$A = @{
  ContentType = 'application/json'
  Method = 'GET'
  Headers = @{
      "X-Auth-Key" = $APIKey
      "X-Auth-Email" = $CFEmail
  }
}
$apibase = "https://api.cloudflare.com/client/v4"

#Pull logs from all ELS enabled zones.
#This will loop through all currently registered domains and, if they have an Enterprise Website plan, pull the logs.
$RetFlagNot = @()
$Zones = (Invoke-RestMethod @A "$($apibase)/zones?per_page=100").Result
foreach ($zone in $zones) {
  if ($zone.plan.name -eq "Enterprise Website") {
    $Z = $zone.id
    if (((Invoke-RestMethod @a "$($apibase)/zones/$z/logs/control/retention/flag").result.flag) -ne $true) {
      $RetFlagNot += @{$zone.name=$zone.id}
      } else {
        $Fields = (Invoke-RestMethod @a -uri "$($apibase)/zones/$z/logs/received/fields").psobject.properties.name -join ","
        $Known = "CacheCacheStatus,CacheResponseBytes,CacheResponseStatus,CacheTieredFill,ClientASN,ClientCountry,ClientDeviceType,ClientIP,ClientIPClass,ClientRequestBytes,ClientRequestHost,ClientRequestMethod,ClientRequestPath,ClientRequestProtocol,ClientRequestReferer,ClientRequestURI,ClientRequestUserAgent,ClientSSLCipher,ClientSSLProtocol,ClientSrcPort,ClientXRequestedWith,EdgeColoCode,EdgeColoID,EdgeEndTimestamp,EdgePathingOp,EdgePathingSrc,EdgePathingStatus,EdgeRateLimitAction,EdgeRateLimitID,EdgeRequestHost,EdgeResponseBytes,EdgeResponseCompressionRatio,EdgeResponseContentType,EdgeResponseStatus,EdgeServerIP,EdgeStartTimestamp,FirewallMatchesActions,FirewallMatchesRuleIDs,FirewallMatchesSources,OriginIP,OriginResponseBytes,OriginResponseHTTPExpires,OriginResponseHTTPLastModified,OriginResponseStatus,OriginResponseTime,OriginSSLProtocol,ParentRayID,RayID,SecurityLevel,WAFAction,WAFFlags,WAFMatchedVar,WAFProfile,WAFRuleID,WAFRuleMessage,WorkerCPUTime,WorkerStatus,WorkerSubrequest,WorkerSubrequestCount,ZoneID"
        if ($Fields.length -ne $Known.length) {
          #Create list of changes
          $Change = Compare-Object ($known.Split(',')) ($fields.Split(',')) | Select -ExpandProperty InputObject | foreach {Write-Output "$_"`n}
          #Determine whether or not to send notification based on existence of file in temp directory
          $Notify = Test-Path C:\temp\FieldChange_$(Get-Date ($D) -Format MMddyyy_HH00).txt
          #If file does not exist for the current hour, send notification
          if ($Notify -eq $false) {
          $Change | out-file C:\temp\FieldChange_$(Get-Date ($D) -Format MMddyyy_HH00).txt
            if ($Fields.length -lt $Known.length) {
              $Body = "The CloudFlare log pull script has detected a change in field availability:`n`nFields removed:`n" + $Change
              Send-MailMessage -Body $Body -Encoding UTF8 -From $SmtpFrom -SmtpServer $SmtpServer -Subject "Change To CloudFlare Fields" -To $SmtpTo
            } else {
              $Body = "The CloudFlare log pull script has detected a change in field availability:`n`nFields added:`n" + $Change
              Send-MailMessage -Body $Body -Encoding UTF8 -From $SmtpFrom -SmtpServer $SmtpServer -Subject "Change To CloudFlare Fields" -To $SmtpTo
            }
          }
        }
        $R = Invoke-RestMethod @A "$($apibase)/zones/$z/logs/received?start=$S&end=$E&timestamps=unix&fields=$Fields"
        #Performs a character check of the log request. If the resulting output is empty, no file will be saved.
        if ($R.length -gt 0) {
        $R | Out-File "$path\CloudFlare$T.txt" -Encoding utf8 -Append
      }
    }
  }
}
#Send notification of zones without Retention Flag enabled.
if ($RetFlagNot -gt 0) {
  $RetFlagBody = "The Enterprise licensed zones listed below do not have logging enabled.
$($RetFlagNot|ft -auto -hidetableheaders|Out-String)
To enable logging, contact your account representative or run the following API call.
Important: Enter your API Key, Email Address, and zone ID where necessary before running.`n
PowerShell
`$A = @{`n  ContentType = 'application/json'`n  Method = 'GET'`n  Headers = @{`n      'X-Auth-Key' = 'APIKEY'`n      'X-Auth-Email' = 'AuthorizedUserEmail'`n  }`n}
Invoke-RestMethod @A -Uri 'https://api.cloudflare.com/client/v4/zones/ZONEID/logs/control/retention/flag?flag=true'`n`n
Linux
curl -X POST `"https://api.cloudflare.com/client/v4/zones/ZONEID/logs/control/retention/flag`" \`n     -H `"X-Auth-Email: AuthorizedUserEMail`" \`n     -H `"X-Auth-Key: APIKEY`" \`n     -H `"Content-Type: application/json`" \`n     --data '{`"flag`":true}'"
  Send-MailMessage -Body $RetFlagBody -Encoding UTF8 -From $SmtpFrom -SmtpServer $SmtpServer -Subject "CloudFlare Logging Disabled" -To $SmtpTo
}

#Pull Organization audit logs.
$Since = (Get-Date ($D).AddMinutes(-6).AddSeconds(-($D).second) -Format yyyy-MM-ddThh:mm:ssZ)
$L = Invoke-RestMethod @A -Uri "$($apibase)/organizations/$OrgId/audit_logs?per_page=1000&since=$Since" | Select -ExpandProperty Result
if (($L.result.length) -gt 0) {
  foreach ($auditrecord in $L) {
    [array]$records += $auditrecord | ConvertTo-Json -Compress
  }
  $records | Out-File $path\CloudFlareAudit$T.log -Encoding utf8
}
#Archive the previous hours files and then delete them.
$d = Get-Date
$t = (Get-Date ($d).AddHours(-1) -UFormat %m%d%G_%H00) + ".zip"
$s = ($d).AddMinutes(-($d).minute).AddSeconds(-($d).second).AddHours(-1)
$e = ($d).AddMinutes(-($d).minute).AddSeconds(-($d).second).AddSeconds(-1)
Set-Location $path
Get-ChildItem -Path $path -Recurse | Where-Object {$_.LastWritetime -gt $s -and $_.LastWriteTime -lt $e} | Compress-Archive -DestinationPath $ArchivePath\$t -Update
Get-ChildItem -Path $path -Recurse | Where-Object {$_.LastWritetime -gt $s -and $_.LastWriteTime -lt $e} | Remove-Item
