Function Get-LogicMonitorCollector {
    <#
        .DESCRIPTION
            Returns a list of LogicMonitor collectors and all of their properties. By default, the function returns all collectors.
            If a collector ID, host name, or display name is provided, the function will return properties for the specified collector.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 30 January 2017
            V1.0.0.1 date: 31 January 2017
                - Removed custom-object creation.
            V1.0.0.2 date: 31 January 2017
                - Updated error output color.
                - Streamlined header creation (slightly).
            V1.0.0.3 date: 31 January 2017
                - Added $logPath output to host.
            V1.0.0.4 date: 31 January 2017
                - Added additional logging.
            V1.0.0.5 date: 10 February 2017
                - Updated procedure order.
            V1.0.0.6 date: 13 April 2017
                - Updated Confirm-OutputPathAvailability usage syntax.
            V1.0.0.7 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.8 date: 21 June 2017
                - Updated logging to reduce chatter.
            V1.0.0.9 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
                - Replaced ! with -NOT.
            V1.0.0.10 date: 21 June 2018
                - Updated whitespace.
            V1.0.0.11 date: 18 October 2018
                - Updated default batch size from 250 to 1000.
            V1.0.0.12 date: 14 March 2019
                - Added support for rate-limited re-try.
            V1.0.0.13 date: 18 March 2019
                - Updated alias publishing method.
            V1.0.0.14 date: 8 April 2019
                - Fixed bug in collector retrieval by name/description.
        .LINK
            https://github.com/wetling23/logicmonitor-posh-module
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER Id
            Represents collector ID of the desired collector. Wildcard searches are not supported.
        .PARAMETER Hostname
            Represents display name of the desired collector. Wildcard searches are not supported.
        .PARAMETER DescriptionName
            Represents IP address or FQDN of the desired device. Wildcard searches are not supported.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of devices to request in each batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all collectors and will return the properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -Id 6

            In this example, the function will search for a collector with "6" in the id property. The properties of that collector will be returned.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -Hostname collector1

            In this example, the function will search for a collector with "collector1" in the hostname property. The properties of that collector will be returned.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -DescriptionName collector1-description

            In this example, the function will search for a collector with "collector1-description" in the hostname property. The properties of that collector will be returned.
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllCollectors')]
    [alias('Get-LogicMonitorCollectors')]
    Param (
        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = 'AllCollectors')]
        [Parameter(ParameterSetName = 'IDFilter')]
        [Parameter(ParameterSetName = 'HostnameFilter')]
        [Parameter(ParameterSetName = 'DescriptionFilter')]
        $AccessId,

        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = 'AllCollectors')]
        [Parameter(ParameterSetName = 'IDFilter')]
        [Parameter(ParameterSetName = 'HostnameFilter')]
        [Parameter(ParameterSetName = 'DescriptionFilter')]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = 'AllCollectors')]
        [Parameter(ParameterSetName = 'IDFilter')]
        [Parameter(ParameterSetName = 'HostnameFilter')]
        [Parameter(ParameterSetName = 'DescriptionFilter')]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = 'IDFilter')]
        [Alias("CollectorId")]
        [int]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = 'HostnameFilter')]
        [Alias("CollectorHostname")]
        [string]$Hostname,

        [Parameter(Mandatory = $True, ParameterSetName = 'DescriptionFilter')]
        [Alias("CollectorDescriptionName")]
        [string]$DescriptionName,

        [int]$BatchSize = 1000,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    If (-NOT($BlockLogging)) {
        $return = Add-EventLogSource -EventLogSource $EventLogSource

        If ($return -ne "Success") {
            $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message -ForegroundColor Yellow;

            $BlockLogging = $True
        }
    }

    $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $deviceBatchCount = 1 # Define how many times we need to loop, to get all devices.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all devices.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/setting/collector/collectors"
    $queryParams = $null
    [boolean]$stopLoop = $false # Ensures we run Invoke-RestMethod at least once.
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: Retrieving collector properties. The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

    # Update $resourcePath to filter for a specific collector, when a collector ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$Id"

        $message = ("{0}: A collector ID was provided. Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
    }

    # Determine how many times "GET" must be run, to return all collectors, then loop through "GET" that many times.
    While ($currentBatchNum -lt $deviceBatchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            { $_ -in ("IDFilter", "AllCollectors") } {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
            }
            "HostnameFilter" {
                $queryParams = "?filter=hostname~`"$Hostname`"&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
            }
            "DescriptionFilter" {
                $queryParams = "?filter=description:`"$DescriptionName`"&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

            # Get current time in milliseconds
            $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

            # Concatenate Request Details
            $requestVars = $httpVerb + $epoch + $resourcePath

            # Construct Signature
            $hmac = New-Object System.Security.Cryptography.HMACSHA256
            $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
            $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
            $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
            $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

            # Construct Headers
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "LMv1 $accessId`:$signature`:$epoch")
            $headers.Add("Content-Type", 'application/json')
            $headers.Add("X-Version", 2)
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

        Do {
            Try {
                $response = Invoke-RestMethod -Uri $url -Method $httpverb -Header $headers -ErrorAction Stop

                $stopLoop = $True
            }
            Catch {
                If ($_.Exception.Message -match '429') {
                    $message = ("{0}: Rate limit exceeded, retrying in 60 seconds." -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Exception.Message)
                    If ($BlockLogging) { Write-Host $message -ForegroundColor Yellow } Else { Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417 }

                    Start-Sleep -Seconds 60
                }
                Else {
                    $message = ("{0}: Unexpected error getting collectors. To prevent errors, {1} will exit. PowerShell returned: {2}" -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Exception.Message)
                    If ($BlockLogging) { Write-Host $message -ForegroundColor Red } Else { Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417 }

                    Return "Error"
                }
            }
        }
        While ($stopLoop -eq $false)

        Switch ($PsCmdlet.ParameterSetName) {
            "AllCollectors" {
                $message = ("{0}: Entering switch statement for all-collector retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                # If no collector ID, IP/FQDN, or display name is provided...
                $devices += $response.items

                $message = ("{0}: There are {1} collectors in `$devices." -f (Get-Date -Format s), $($devices.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                # The first time through the loop, figure out how many times we need to loop (to get all collectors).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all collectors." -f (Get-Date -Format s), $deviceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                    $firstLoopDone = $true

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
                }

                # Increment offset, to grab the next batch of collectors.
                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                # Increment the variable, so we know when we have retrieved all collectors.
                $currentBatchNum++

            }
            # If a collector ID, IP/FQDN, or display name is provided...
            { $_ -in ("IDFilter", "HostnameFilter", "DescriptionFilter") } {
                $message = ("{0}: Entering switch statement for single-collector retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $devices = $response
                }
                Else {
                    $devices = $response.items
                }

                If ($devices.count -eq 0) {
                    $message = ("{0}: There was an error retrieving the collector. LogicMonitor reported that zero collectors were retrieved. The error is: {1}" -f (Get-Date -Format s), $response.errmsg)
                    If ($BlockLogging) { Write-Host $message -ForegroundColor Red } Else { Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417 }

                    Return "Error"
                }
                Else {
                    $message = ("{0}: There are {1} collectors in `$devices." -f (Get-Date -Format s), $($devices.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
                }

                # The first time through the loop, figure out how many times we need to loop (to get all collectors).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all collectors." -f (Get-Date -Format s), $deviceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                    $firstLoopDone = $True

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) { Write-Verbose $message } ElseIf ($PSBoundParameters['Verbose']) { Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417 }

                # Increment the variable, so we know when we have retrieved all collectors.
                $currentBatchNum++
            }
        }
    }

    Return $devices
} #1.0.0.14