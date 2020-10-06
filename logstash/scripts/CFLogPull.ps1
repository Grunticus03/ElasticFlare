#Configuration Variables
$Path = "Logstash ingest folder"
$ArchivePath = 'Folder to save zip files to(exclude trailing slash)'
$SmtpFrom = "Sending email address for notification"
$SmtpTo = 'Recipient of email notification. To include more than one recipient, use following syntax "email1@example.com", "email2@example.com", "etc@example.com"'
$SmtpServer = "Hostname/IP of SMTP server"
$APIKey = "Global API Key"
$CFEmail = "CloudFlare admin email address for API call"
$OrgId = "Organization ID for audit log pulls"
$dictroot = "Root dictionary folder"
# The following variables specify the timeframe to pull logs. As per the API documentation, https://api.cloudflare.com/#logs-received-logs-received,
# the ending time ($EM) must be at least 5 minutes prior to now. In addition, the total timeframe cannot exceed 1 hour
$SM = "Starting time number of minutes to go back - If it's 12:00 and you want logs starting at 11:50, set to 10"
$EM = "Ending time number of minutes to go back - This must be at least 5 minutes in the past."

#CloudFlare Enterprise Log Service (ELS) Pull
#Get time 7m - 2m ago (In UTC)
$D = Get-Date
$T = (Get-Date ($D) -Format MMddyyy_HHmmss)
$S = [Math]::Floor([decimal](Get-Date($D).AddMinutes(-$($SM)).ToUniversalTime()-uformat "%s"))
$E = [Math]::Floor([decimal](Get-Date($D).AddMinutes(-$($EM)).ToUniversalTime()-uformat "%s"))
$apibase = "https://api.cloudflare.com/client/v4"
$RetFlagNot = @()
#Force PowerShell to use TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12

#Set Required Headers
#Change GLOBALAPIKEY and USEREMAILADDRESS, retain double quotes.
$A = @{
  ContentType = 'application/json'
  Method = 'GET'
  Headers = @{
      "X-Auth-Key" = $APIKey
      "X-Auth-Email" = $CFEmail
  }
}

#Pull Domains
$zonetable = (Invoke-RestMethod @A "$($apibase)/zones?per_page=500").Result | Where-object {$_.plan.name -eq "Enterprise Website"}

#Build Dictionaries
foreach ($zone in $zonetable) {

  #Create folder/path to dictionary locations
  if ((Test-Path "$($dictroot)\dns") -eq $false) {
    New-Item -Type Directory "$($dictroot)\dns" | Out-Null
  }
  if ((Test-Path "$($dictroot)\fw") -eq $false) {
    New-Item -Type Directory "$($dictroot)\fw" | Out-Null
  }
  
  #Build Zone Table
  [string[]]$zonelist += '"'+$zone.name+'": '+$zone.id
  
  #Build Firewall Rule Dictionaries
  $rules = (Invoke-RestMethod @A -Uri "$($apibase)/zones/$($zone.id)/firewall/rules").Result
  foreach ($rule in $rules) {
    [string[]]$fwdesc += '"'+$rule.id+'": '+$rule.description
    [string[]]$fwaction += '"'+$rule.id+'": '+$rule.action
    [string[]]$fwexpression += '"'+$rule.id+'": '+$rule.filter.expression
    [string[]]$fwcreated += '"'+$rule.id+'": '+$rule.created_on
    [string[]]$fwmodified += '"'+$rule.id+'": '+$rule.modified_on
    [string[]]$fwpaused += '"'+$rule.id+'": '+$rule.paused
    [string[]]$fwpriority += '"'+$rule.id+'": '+$rule.priority
  }
  
  #Build DNS Dictionaries
  $DNSEntries = (Invoke-RestMethod @A -Uri "$($apibase)/zones/$($zone.id)/dns_records").Result
  foreach ($DNSEntry in $DNSEntries) {
    [string[]]$DNSContent += '"'+$DNSEntry.id+'": '+$DNSEntry.content
    [string[]]$DNSCreatedOn += '"'+$DNSEntry.id+'": '+$DNSEntry.created_on
    [string[]]$DNSModifiedOn += '"'+$DNSEntry.id+'": '+$DNSEntry.ModifiedOn
    [string[]]$DNSName += '"'+$DNSEntry.id+'": '+$DNSEntry.Name
    [string[]]$DNSProxiable += '"'+$DNSEntry.id+'": '+$DNSEntry.Proxiable
    [string[]]$DNSProxied += '"'+$DNSEntry.id+'": '+$DNSEntry.Proxied
    [string[]]$DNSTTL += '"'+$DNSEntry.id+'": '+$DNSEntry.TTL
    [string[]]$DNSType += '"'+$DNSEntry.id+'": '+$DNSEntry.Type
  }
}

#Save Dictionaries To Disk
#Firewall Dictionaries
$fwdesc | Out-File "$($dictroot)\fw\description.yaml" -Encoding utf8
$fwaction | Out-File "$($dictroot)\fw\action.yaml" -Encoding utf8
$fwexpression | Out-File "$($dictroot)\fw\expression.yaml" -Encoding utf8
$fwcreated | Out-File "$($dictroot)\fw\created.yaml" -Encoding utf8
$fwmodified | Out-File "$($dictroot)\fw\modified.yaml" -Encoding utf8
$fwpaused | Out-File "$($dictroot)\fw\paused.yaml" -Encoding utf8
$fwpriority | Out-File "$($dictroot)\fw\priority.yaml" -Encoding utf8
#DNS Dictionaries
$DNSContent | Out-File "$($dictroot)\dns\content.yaml" -Encoding utf8
$DNSCreatedOn | Out-File "$($dictroot)\dns\created_on.yaml" -Encoding utf8
$DNSModifiedOn | Out-File "$($dictroot)\dns\modified_on.yaml" -Encoding utf8
$DNSName | Out-File "$($dictroot)\dns\name.yaml" -Encoding utf8
$DNSProxiable | Out-File "$($dictroot)\dns\proxiable.yaml" -Encoding utf8
$DNSProxied | Out-File "$($dictroot)\dns\proxied.yaml" -Encoding utf8
$DNSTTL | Out-File "$($dictroot)\dns\ttl.yaml" -Encoding utf8
$DNSType | Out-File "$($dictroot)\dns\type.yaml" -Encoding utf8
#Zone List Dictionary
$zonelist | Out-File "$($dictroot)\auditzones.yaml" -Encoding utf8

#Pull logs from all ELS enabled zones.
#This will loop through all Enterprise licensed domains and pull logs.
foreach ($zone in $zonetable) {
  if (((Invoke-RestMethod @a "$($apibase)/zones/$($zone.id)/logs/control/retention/flag").result.flag) -ne $true) {
    $RetFlagNot += @{$zone.name=$zone.id}
  } else {
    #Get list of fields available and convert into string
    $Fields = (Invoke-RestMethod @a -uri "$($apibase)/zones/$($zone.id)/logs/received/fields").psobject.properties.name -join ","
    #List of known fields
    $Known = "CacheCacheStatus,CacheResponseBytes,CacheResponseStatus,CacheTieredFill,ClientASN,ClientCountry,ClientDeviceType,ClientIP,ClientIPClass,ClientRequestBytes,ClientRequestHost,ClientRequestMethod,ClientRequestPath,ClientRequestProtocol,ClientRequestReferer,ClientRequestURI,ClientRequestUserAgent,ClientSSLCipher,ClientSSLProtocol,ClientSrcPort,ClientXRequestedWith,EdgeColoCode,EdgeColoID,EdgeEndTimestamp,EdgePathingOp,EdgePathingSrc,EdgePathingStatus,EdgeRateLimitAction,EdgeRateLimitID,EdgeRequestHost,EdgeResponseBytes,EdgeResponseCompressionRatio,EdgeResponseContentType,EdgeResponseStatus,EdgeServerIP,EdgeStartTimestamp,FirewallMatchesActions,FirewallMatchesRuleIDs,FirewallMatchesSources,OriginIP,OriginResponseBytes,OriginResponseHTTPExpires,OriginResponseHTTPLastModified,OriginResponseStatus,OriginResponseTime,OriginSSLProtocol,ParentRayID,RayID,SecurityLevel,WAFAction,WAFFlags,WAFMatchedVar,WAFProfile,WAFRuleID,WAFRuleMessage,WorkerCPUTime,WorkerStatus,WorkerSubrequest,WorkerSubrequestCount,ZoneID"
    #Compare the length of Fields and Known. If different send notification
    if ($Fields.length -ne $Known.length) {
      #Create list of changes
      $Change = Compare-Object ($known.Split(',')) ($fields.Split(',')) | Select -ExpandProperty InputObject | foreach {Write-Output "$_"`n}
      #Determine whether or not to send notification based on existence of file in temp directory
      $Notify = Test-Path "$($dictroot)\FieldChange_$(Get-Date ($D) -Format MMddyyy_HH00).txt"
      #If file does not exist for the current hour, send notification
      if ($Notify -eq $false) {
      $Change | out-file "$($dictroot)\FieldChange_$(Get-Date ($D) -Format MMddyyy_HH00).txt"
        if ($Fields.length -lt $Known.length) {
          $Body = "CloudFlare log pull script has detected a change in field availability:`n`nFields removed:`n" + $Change
          Send-MailMessage -Body $Body -Encoding UTF8 -From $SmtpFrom -SmtpServer $SmtpServer -Subject "CloudFlare Field Change" -To $SmtpTo
        } else {
          $Body = "CloudFlare log pull script has detected a change in field availability:`n`nFields added:`n" + $Change
          Send-MailMessage -Body $Body -Encoding UTF8 -From $SmtpFrom -SmtpServer $SmtpServer -Subject "CloudFlare Field Change" -To $SmtpTo
        }
      }
    }
    $R = Invoke-RestMethod @A "$($apibase)/zones/$($zone.id)/logs/received?start=$S&end=$E&timestamps=unix&fields=$Fields"
    #Perform character check of $R, if output is empty no file will be saved.
    if ($R.length -gt 0) {
    $R | Out-File "$path\CloudFlare$T.txt" -Encoding utf8 -Append
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
$Since = (Get-Date ($D).AddMinutes(-7).AddSeconds(-($D).second) -Format yyyy-MM-ddThh:mm:ssZ)
$L = (Invoke-RestMethod @A -Uri "$($apibase)/organizations/$($OrgId)/audit_logs?per_page=1000&since=$Since").Result
if (($L.result.length) -gt 0) {
  foreach ($auditrecord in $L) {
    [array]$records += $auditrecord | ConvertTo-Json -Compress
  }
  $records | Out-File $path\CloudFlareAudit$T.log -Encoding utf8
}

#Archive the previous hours files and then delete them.
$T = (Get-Date ($D).AddHours(-1) -UFormat %m%d%G_%H00) + ".zip"
$S = ($D).AddMinutes(-($D).minute).AddSeconds(-($D).second).AddHours(-1)
$E = ($D).AddMinutes(-($D).minute).AddSeconds(-($D).second).AddSeconds(-1)
Set-Location $path
Get-ChildItem -Path $path -Recurse | Where-Object {$_.LastWritetime -gt $S -and $_.LastWriteTime -lt $E} | Compress-Archive -DestinationPath $ArchivePath\$T -Update
$E = ($D).AddMinutes(-($D).minute).AddSeconds(-($D).second).AddHours(-24)
Get-ChildItem -Path $path -Recurse | Where-Object {$_.LastWriteTime -lt $E} | Remove-Item
