# ElasticFlare
ElasticFlare pulls CloudFlare firewall and audit logs, then ingests and enriches the data using the Elastic Stack.

* Utilizes a pair of PowerShell script to make API calls and pull down logs.
* Geo-IP enrichment on client IP.
* Client user agent parsing
* Identify blocked requests and reason for blocks.
* When a firewall rule is triggered, additional calls made to pull information on the firewall rule.
* Email notification when CloudFlare fields are added or removed.

**10/14/2019:** Significant changes have been made.  These changes were designed to provide uniform field naming and improve ease of use.  Previous implementations will need to re-ingest all data to unify field names and data types for accurate representation on dashboards and in searches. 

I recommend configuring two scheduled tasks in Windows to execute the scripts on a set schedule.  See the [CloudFlare ELS API documentation](https://api.cloudflare.com) for additional support and limitations.

**Built and tested on Elastic Stack 7.2.0.**

Feedback and requests for additional features or enrichments is always welcome.

## Overview Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/Overview.png)

## Blocks Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/Blocks.PNG)

## Cache Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/Cache.png)

## End User Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/End%20User.png)

## Endpoints & Queries Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/EndpointsAndQueries.png)

## Geo Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/Geo.png)

## Response Times Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/ResponseTimes.png)

## SSL Dashboard
![alt text](https://raw.githubusercontent.com/wwalker0307/ElasticFlare/master/assets/SSL.png)
