#Force PowerShell to use TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12

#Set Required Headers
#Change GLOBALAPIKEY and USEREMAILADDRESS, retain double quotes.
$A = @{
  ContentType = 'application/json'
  Method = 'GET'
  Headers = @{
      "X-Auth-Key" = "CloudFlare API Key"
      "X-Auth-Email" = "CloudFlare Email Address"
  }
}

$zonetable = Invoke-RestMethod @A "https://api.cloudflare.com/client/v4/zones?per_page=500"
foreach ($zone in $zonetable.result) {
  [string[]]$zonelist += '"'+$zone.name+'": '+$zone.id
}
$zonelist | Out-File \dictionaries\cloudflareauditzones.yaml -Encoding utf8