﻿Function Get-LogicMonitorConfigSource {
    <#
        .DESCRIPTION
            Returns a list of LogicMonitor ConfigSources. By default, the function returns all ConfigSources. If a ConfigSource ID or name is provided, the function will 
            return properties for the specified ConfigSource.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 15 February 2019
                - Initial release.
            V1.0.0.1 date: 8 March 2019
                - Fixed bugs with filters.
            V1.0.0.2 date: 14 March 2019
                - Added support for rate-limited re-try.
        .LINK
            
        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER Id
            Represents the ID of the desired ConfigSource.
        .PARAMETER DisplayName
            Represents the display name of the desired ConfigSource.
        .PARAMETER ApplyTo
            Represents the 'apply to' expression of the desired ConfigSource(s).
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of DataSoruces to request from LogicMonitor, in a single batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorConfigSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all monitored devices and will return their properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorConfigSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ConfigSourceId 6

            In this example, the function returns the ConfigSource with ID '6'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorConfigSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DisplayName 'Oracle Library Cache'

            In this example, the function returns the ConfigSource with display name 'Oracle Library Cache'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorConfigSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ApplyTo 'system.hostname =~ "255.1.1.1"'

            In this example, the function returns the ConfigSource with the 'appliesTo' filter 'system.hostname =~ "255.1.1.1"'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorConfigSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ApplyTo 'isWindows()&&hasCategory("collector")'

            In this example, the function returns the ConfigSource with the 'appliesTo' filter 'isWindows()&&hasCategory("collector")'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllConfigSources')]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = 'IDFilter')]
        [int]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = 'NameFilter')]
        [string]$DisplayName,

        [Parameter(Mandatory = $True, ParameterSetName = 'AppliesToFilter')]
        [string]$ApplyTo,

        [int]$BatchSize = 1000,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    If (-NOT($BlockLogging)) {
        $return = Add-EventLogSource -EventLogSource $EventLogSource

        If ($return -ne "Success") {
            $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message

            $BlockLogging = $True
        }
    }

    $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    [int]$offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    [int]$ConfigSourceBatchCount = 1 # Define how many times we need to loop, to get all ConfigSources.
    [boolean] $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all ConfigSources.
    [string]$httpVerb = "GET" # Define what HTTP operation will the script run.
    [string]$resourcePath = "/setting/configsources" # Define the resourcePath.
    $queryParams = $null
    $configSources = $null
    [boolean]$stopLoop = $false # Ensures we run Invoke-RestMethod at least once.
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific ConfigSource, when a ConfigSource ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$Id"

        $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all ConfigSources, then loop through "GET" that many times.
    While ($currentBatchNum -lt $ConfigSourceBatchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            "AllConfigSources" {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "IDFilter" {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "NameFilter" {
                # Replace special characters to better encode the URL.
                $DisplayName = $DisplayName.Replace('_', '%5F')
                $DisplayName = $DisplayName.Replace(' ', '%20')

                $queryParams = "?filter=displayName:`"$DisplayName`"&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "AppliesToFilter" {
                # Replace special characters to better encode the URL.
                $ApplyTo = $ApplyTo.Replace('"', '%2522')
                $ApplyTo = $ApplyTo.Replace('&', '%26')
                $ApplyTo = $ApplyTo.Replace("`r`n", "`n")
                $ApplyTo = $ApplyTo.Replace('#', '%23')
                $ApplyTo = $ApplyTo.Replace("`n", '%0A')
                $ApplyTo = $ApplyTo.Replace(')', '%29')
                $ApplyTo = $ApplyTo.Replace('(', '%28')
                $ApplyTo = $ApplyTo.Replace('>', '%3E')
                $ApplyTo = $ApplyTo.Replace('<', '%3C')
                $ApplyTo = $ApplyTo.Replace('/', '%2F')
                $ApplyTo = $ApplyTo.Replace(',', '%2C')
                $ApplyTo = $ApplyTo.Replace('*', '%2A')
                $ApplyTo = $ApplyTo.Replace('!', '%21')
                $ApplyTo = $ApplyTo.Replace('=', '%3D')
                $ApplyTo = $ApplyTo.Replace('~', '%7E')
                $ApplyTo = $ApplyTo.Replace(' ', '%20')
                $ApplyTo = $ApplyTo.Replace('|', '%7C')
                $ApplyTo = $ApplyTo.Replace('$', '%24')
                $ApplyTo = $ApplyTo.Replace('\', '%5C')
                $ApplyTo = $ApplyTo.Replace('_', '%5F')

                $queryParams = "?filter=appliesTo:`"$ApplyTo`"&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        $message = ("{0}: The value of `$url is: {1}." -f (Get-Date -Format s), $url)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

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
            $headers.Add("X-Version", '2')
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        Do {
            Try {
                $response = Invoke-RestMethod -Uri $url -Method $httpverb -Header $headers -ErrorAction Stop

                $stopLoop = $True
            }
            Catch {
                If ($_.Exception.Message -match '429') {
                    $message = ("{0}: Rate limit exceeded, retrying in 60 seconds." -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}

                    Start-Sleep -Seconds 60
                }
                Else {
                    $message = ("{0}: Unexpected error getting ConfigSource(s). To prevent errors, {1} will exit. PowerShell returned: {2}" -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
            }
        }
        While ($stopLoop -eq $false)

        Switch ($PsCmdlet.ParameterSetName) {
            "AllConfigSources" {
                $message = ("{0}: Entering switch statement for all-ConfigSource retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no ConfigSource ID is provided...
                $configSources += $response.items

                $message = ("{0}: There are {1} ConfigSources in `$configSources." -f (Get-Date -Format s), $($configSources.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all ConfigSources).
                If ($firstLoopDone -eq $false) {
                    [int]$ConfigSourceBatchCount = ((($response.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all ConfigSources. LogicMonitor reports that there are {2} ConfigSources." `
                            -f (Get-Date -Format s), $ConfigSourceBatchCount, $response.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of ConfigSources.
                $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $ConfigSourceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all ConfigSources.
                $currentBatchNum++
            }
            "IDFilter" {
                $message = ("{0}: Entering switch statement for single-ConfigSource retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $configSources = $response.items

                $message = ("{0}: There are {1} ConfigSources in `$ConfigSources." -f (Get-Date -Format s), $($configSources.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                Return $configSources
            }
            {$_ -in ("NameFilter", "AppliesToFilter")} {
                $message = ("{0}: Entering switch statement for filtered-ConfigSource retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($response.items.count -eq 1) {
                    $message = ("{0}: Found a single ConfigSources." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                    $configSources = $response.items

                    Return $configSources
                }
                Else {
                    $configSources += $response.items

                    $message = ("{0}: There are {1} ConfigSources in `$configSources." -f (Get-Date -Format s), $($configSources.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                    # The first time through the loop, figure out how many times we need to loop (to get all ConfigSources).
                    If ($firstLoopDone -eq $false) {
                        [int]$ConfigSourceBatchCount = ((($response.total) / 250) + 1)

                        $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all ConfigSources." -f (Get-Date -Format s), $configSourceBatchCount)
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                        $firstLoopDone = $True

                        $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                    }

                    $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $ConfigSourceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                    # Increment the variable, so we know when we have retrieved all ConfigSources.
                    $currentBatchNum++
                }
            }
        }
    }

    Return $configSources
} #1.0.0.2