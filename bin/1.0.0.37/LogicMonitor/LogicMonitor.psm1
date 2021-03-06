﻿Function Add-EventLogSource {
    <#
    .DESCRIPTION
        Adds an Event Log source, for script/module logging. Adding an Event Log source requires administrative rights.
    .NOTES 
        Author: Mike Hashemi
        V1.0.0.0 date: 19 April 2017
            - Initial release.
        V1.0.0.1 date: 1 May 2017
            - Minor updates to status handling.
        V1.0.0.2 date: 4 May 2017
            - Added additional return value.
        V1.0.0.3 date: 22 May 2017
            - Changed output to reduce the number of "Write-Host" messages.
        V1.0.0.4 date: 21 June 2017
            - Fixed typo.
            - Significantly improved performance.
            - Changed logging.
        V1.0.0.5 date: 21 June 2017
            - Added a return value if the event log source exists.
        V1.0.0.6 date: 28 June 2017
            - Added [CmdletBinding()].
        V1.0.0.7 date: 28 June 2017
            - Added a check for the source, then a check on the status of the query.
    .PARAMETER EventLogSource
        Mandatory parameter. This parameter is used to specify the event source, that script/modules will use for logging.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        $EventLogSource
    )
        
        $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
        Write-Host $message -ForegroundColor White
    
        # Check if $EventLogSource exists as a source. If the shell is not elevated and the check fails to access the Security log, assume the source does not exist.
        Try {
            $sourceExists = [System.Diagnostics.EventLog]::SourceExists("$EventLogSource")
        }
        Catch {
            $sourceExists = $False
        }
    
        If ($sourceExists -eq $False) {
            $message = ("{0}: The event source `"{1}`" does not exist. Prompting for elevation." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message -ForegroundColor White
            
            Try {
                Start-Process PowerShell -Verb RunAs -ArgumentList "New-EventLog -LogName Application -Source $EventLogSource -ErrorAction Stop"
            }
            Catch [System.InvalidOperationException] {
                $message = ("{0}: It appears that the user cancelled the operation." -f (Get-Date -Format s))
                Write-Host $message -ForegroundColor Yellow
                Return "Error"
            }
            Catch {
                $message = ("{0}: Unexpected error launching an elevated Powershell session. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                Write-Host $message -ForegroundColor Red
                Return "Error"
            }
    
            Return "Success"
        }
        Else {
            $message = ("{0}: The event source `"{1}`" already exists. There is no action for {2} to take." -f (Get-Date -Format s), $EventLogSource, $MyInvocation.MyCommand)
            Write-Verbose $message
    
            Return "Success"
        }
    } #1.0.0.7
Function Add-LogicMonitorCollector {
    <#
.DESCRIPTION 
    Creates a LogicMonitor collector, writes the ID to the registry and returns the ID. In a terminating error occurs, "Error" is returned.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 31 January 2017
        - Initial release.
    V1.0.0.1 date: 31 January 2017
        - Added additional logging.
    V1.0.0.2 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.3 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.4 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.5 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER CollectorDisplayName
    Mandatory parameter. Represents the long name of the EDGE Hub.
.PARAMETER LMHostName
    Mandatory parameter. Represents the short name of the EDGE Hub.    
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Add-LogicMonitorCollector -AccessId $accessid -AccessKey $accesskey -AccountName $accountname -CollectorDisplayName collector1

    In this example, the function will create a new collector with the following properties:
        - Display name: collector1
    As of collector version 22.004, a monitored device for the collector is automatically created with the display name 127.0.0.1_collector_<collectorID> and IP 127.0.0.1.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True)]
        [string]$CollectorDisplayName,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $hklm = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $httpVerb = "POST" # Define what HTTP operation will the script run.    
    $resourcePath = "/setting/collectors"
    $data = "{`"description`":`"$CollectorDisplayName`"}"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    
    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    $message = ("{0}: Connecting to: {1}." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Add-LogicMonitorCollector function will exit. The specific error was: {1}" `
                -f (Get-Date -Format s), $_Exception.Message)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
        Return "Error"
    }

    Switch ($response.status) {
        "200" {
            $message = ("{0}: Successfully created the collector in LogicMonitor." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }
        "1007" {
            $message = ("{0}: It appears that the web request failed. To prevent errors, the Add-LogicMonitorCollector function will exit. The status was {1} and the error was {2}" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
        Default {
            $message = ("{0}: Unexpected error creating a new collector in LogicMonitor. To prevent errors, the Add-LogicMonitorCollector function will exit. The status was {1} and the error was {2}" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
    }

    $message = ("{0}: Attempting to write the collector ID {1} to the registry." -f (Get-Date -Format s), $($response.data.id))
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        New-ItemProperty -Path $hklm -Name LogicMonitorCollectorID -Value $($response.data.id) -PropertyType String -Force -ErrorAction Stop | Out-Null
    }
    Catch {
        If ($_.Exception.Message -like "*Cannot find path*") {
            $message = ("{0}: Unable to record {1} to the registry. It appears that the key ({2}) does not exist or the account does not have permission to modify it. {3} will continue." `
                    -f (Get-Date -Format s), $response.data.id, $hklm, $MyInvocation.MyCommand) 
            If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}
        }
        Else {
            $message = ("{0}: Unexpected error recording {1} to the registry. No big deal, the function will continue. The specific error is: {2}" `
                    -f (Get-Date -Format s), $response.data.id, $_.Exception.Message)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}
        }
    }

    Return $response.data.id
} 
#1.0.0.5
Function Add-LogicMonitorDevice {
    <#
.DESCRIPTION 
    Adds a monitored device to LogicMonitor. Note that the name (IP or DNS name) must be unique to the collector monitoring the device
	and that the display name must be unique to LogicMonitor. Returns a success or failure string.
.NOTES 
    Author: Mike Hashemi
    V1 date: 24 January 2017
    V1.0.0.1 date: 31 January 2017
        - Added support for the hostGroupIds property.
    V1.0.0.2 date: 31 January 2017
        - Updated error output color.
        - Streamlined header creation (slightly).
    V1.0.0.3 date: 31 January 2017
        - Added $logPath output to host.
    V1.0.0.4 date: 31 January 2017
        - Added additional logging.
    V1.0.0.5 date: 2 February 2017
        - Updated logging.
        - Added support for multiple host group IDs.
        - Added support for the device description field.
    V1.0.0.6 date: 2 February 2017
        - Updated logging.
    V1.0.0.7 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.8 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.9 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.10 date: 19 July 2017
        - Updated handing the $data variable.
    V1.0.0.11 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.        
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER DeviceDisplayName
    Mandatory parameter. Represents the display name of the device to be monitored. This name must be unique in your LogicMonitor account.
.PARAMETER DeviceName
	Mandatory parameter. Represents the IP address or DNS name of the device to be monitored. This IP/name must be unique on the monitoring collector.
.PARAMETER PreferredCollectorID
	Mandatory parameter. Represents the collector ID of the collector which will monitor the device.
.PARAMETER HostGroupID
	Mandatory parameter. Represents the ID number of the group, into which the monitored device will be placed.
.PARAMETER Description
	Represents the device description.
.PARAMETER PropertyNames
    Mandatory parameter. Represents the name(s) of the target property. Note that LogicMonitor properties are case sensitive.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.PARAMETER LogPath
    Path where the function should store its log. When omitted, output will be sent to the shell.
.EXAMPLE
    PS C:\> Add-LogicMonitorDevice -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName device1 -DeviceName 10.0.0.0 -PreferredCollectorID 459 -HostGroupID 379 -PropertyNames location -PropertyValues Denver
    
    In this example, the function will create a new device with the following properties:
        - IP: 10.0.0.0
        - Display name: device1
        - Preferred collector: 459
        - Host group: 379
        - Location: Denver
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,
        
        [Parameter(Mandatory = $True)]
        $AccessKey,
		
        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True)]
        [string]$DeviceDisplayName,

        [Parameter(Mandatory = $True)]
        [string]$DeviceName,

        [Parameter(Mandatory = $True)]
        [int]$PreferredCollectorID,

        [Parameter(Mandatory = $True)]
        [string]$HostGroupID,

        [string]$Description,

        [string[]]$PropertyNames,

        [string[]]$PropertyValues,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $data = ""
    $httpVerb = "POST" # Define what HTTP operation will the script run.
    $resourcePath = "/device/devices"
    $requiredProperties = "`"name`":`"$DeviceName`",`"displayName`":`"$DeviceDisplayName`",`"preferredCollectorId`":$PreferredCollectorID,`"hostGroupIds`":`"$HostGroupID`""
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    If ($Description) {
        $message = ("{0}: Appending `"description`" to the list of properties." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $requiredProperties += ",`"description`":`"$Description`""
    }

    # For each property, assign the name and value to $propertyData...
    Foreach ($property in $PropertyNames) {    
        $message = ("{0}: Updating/adding property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        
        $propertyData += "{`"name`":`"$property`",`"value`":`"$($PropertyValues[$index])`"},"
        $index++
    }
    
    #...trim the trailing comma...
    $propertyData = $propertyData.TrimEnd(",")
    
    #...and assign the entire string to the $data variable.
    If ($propertyData) {
        $data = "{$requiredProperties,`"customProperties`":[$propertyData]}"
    }
    Else {
        $data = "{$requiredProperties}"
    }

    $message = ("{0}: The value of `$data, is: {1}." -f (Get-Date -Format s), $data)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"
	
    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
    # Make Request
    $message = ("{0}: Executing the REST query ({1})." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Add-LogicMonitorDevice function will exit. The specific error message is: {1}" -f (Get-Date -Format s), $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        write-host "response: $response"
        Return "Failure"
    }

    Switch ($response.status) {
        "200" {
            $message = ("{0}: Successfully added the device in LogicMonitor." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			
            Return "Success"
        }
        "600" {
            $message = ("{0}: LogicMonitor reported that there is a duplicate device. Verify that the device you are adding has an IP (or DNS) name unique to the preferred collector and a display name unique to LogicMonitor. The specific message was: {1}" `
                    -f (Get-Date -Format s), $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
			
            Return "Failure (600)"
        }
        Default {
            $message = ("{0}: Unexpected error creating a new device in LogicMonitor. To prevent errors, the Add-LogicMonitorDevice function will exit. The status was: {1} and the error was: `"{2}`"" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
			
            Return "Failure"
        }
    }
}
#1.0.0.11
Function Add-LogicMonitorDeviceGroup {
    <#
        .DESCRIPTION 

        .NOTES 
            Author: Mike Hashemi
            V1 date: 2 February 2017
                - Initial release.
            V1.0.0.3 date: 10 February 2017
                - Updated procedure order.
            V1.0.0.4 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.5 date: 21 June 2017
                - Updated logging to reduce chatter.
            V1.0.0.6 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
                - Replaced ! with -NOT.
            V1.0.0.7 date: 21 June 2018
                - Updated white space.
        .LINK
            
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER GroupDisplayName
            Mandatory parameter. Represents the display name of the device to be monitored. This name must be unique in your LogicMonitor account.
        .PARAMETER GroupName
            Mandatory parameter. Represents the name of the group to be added.
        .PARAMETER ParentGroupID
            Mandatory parameter. Represents the group ID of the group, to which the new group will be subordinate.
        .PARAMETER Description
            Represents the description of the group.
        .PARAMETER DisableAlerting
            Boolean value. Represents the default alerting state for the group.
        .PARAMETER AppliesTo
            Represents the query syntax, to which devices must conform for membership in this group.
        .PARAMETER PropertyNames
            Mandatory parameter. Represents the name(s) of the target property. Note that LogicMonitor properties are case sensitive.
        .PARAMETER PropertyValues
            Mandatory parameter. Represents the value of the target property(ies). Property values must be in the same order as the property names.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Add-LogicMonitorDeviceGroup

            In this example, the function will create a new device group with the following properties:
                - IP: 10.0.0.0
                - Display name: device1
                - Preferred collector: 459
                - Host group: 379
                - Location: Denver
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,
        
        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True)]
        [string]$GroupName,

        [Parameter(Mandatory = $True)]
        [string]$ParentGroupID,

        [string]$Description,

        [boolean]$DisableAlerting = $false,

        [string]$AppliesTo,

        [string[]]$PropertyNames,

        [string[]]$PropertyValues,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $data = ""
    $httpVerb = "POST" # Define what HTTP operation will the script run.
    $resourcePath = "/device/groups"
    $requiredProperties = "`"name`":`"$GroupName`",`"parentId`":`"$ParentGroupID`""
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols    

    If ($Description) {
        $message = ("{0}: Appending `"description`" to the list of properties." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $requiredProperties += ",`"description`":`"$Description`""
    }
    If ($AppliesTo) {
        $message = ("{0}: Appending `"appliesTo`" to the list of properties." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $requiredProperties += ",`"appliesTo`":`"$AppliesTo`""
    }

    $message = ("{0}: Appending `"disableAlerting`" to the list of properties." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $requiredProperties += ",`"disableAlerting`":`"$DisableAlerting`""

    $message = ("{0}: Finished adding standard properties." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # For each property, assign the name and value to $propertyData...
    Foreach ($property in $PropertyNames) {    
        $message = ("{0}: Updating/adding property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $propertyData += "{`"name`":`"$property`",`"value`":`"$($PropertyValues[$index])`"},"
        
        $index++
    }
    
    #...trim the trailing comma...
    $propertyData = $propertyData.TrimEnd(",")

    #...and assign the entire string to the $data variable.
    If ($PropertyNames) {
        $data = "{$requiredProperties,`"customProperties`":[$propertyData]}"

        $message = ("{0}: There are custom properties. The value of `$data is {1}." -f (Get-Date -Format s), $data)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }
    Else {
        $data = "{$requiredProperties}"

        $message = ("{0}: There are no custom properties. The value of `$data is {1}." -f (Get-Date -Format s), $data)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

    # Make Request
    $message = ("{0}: Executing the REST query ({1})." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Add-LogicMonitorDeviceGroup function will exit. The specific error message is: {1}" -f (Get-Date -Format s), $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

        Return "Failure"
    }
    Switch ($response.status) {
        "200" {
            $message = ("{0}: Successfully added the group in LogicMonitor." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Return "Success"
        }
        "600" {
            $message = ("{0}: LogicMonitor reported that there is a duplicate group. Verify that the group you are adding has a unique name. The specific message was: {1}" `
                    -f (Get-Date -Format s), $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Failure (600)"
        }
        Default {
            $message = ("{0}: Unexpected error creating a new group in LogicMonitor. To prevent errors, the Add-LogicMonitorDeviceGroup function will exit. The status was: {1} and the error was: `"{2}`"" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Failure"
        }
    }
}
#1.0.0.7
Function Get-LogicMonitorAlertRules {
    <#
        .DESCRIPTION
            Retrieves Alert objects from LogicMonitor.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 7 August 2018
                - Initial release.
            V1.0.0.1 date: 8 August 2018
                - Added support for retrieval of single alert rule, either by ID or name.
                - Fixed example typo.
                - Added example.
        .LINK
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER AlertRuleId
            Represents deviceId of the desired device.
        .PARAMETER AlertRuleName
            Represents IP address or FQDN of the desired device.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of alert rules to request from LogicMonitor.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorAlertRules -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

            In this example, the function gets all alert rules, in batches of 1000. Output is logged to the application log, and written to the host.
        .EXAMPLE
            PS C:\> Get-LogicMonitorAlertRules -AccessID <access ID> -AccessKey <access key> -AccountName <account name> -AlertRuleId 1 -BlockLogging

            In this example, the function gets the properties of the alert rule with ID "1". No output is logged to the event log.
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllAlertRules')]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = 'IDFilter')]
        [int]$AlertRuleId,

        [Parameter(Mandatory = $True, ParameterSetName = 'NameFilter')]
        [string]$AlertRuleName,

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

    $message = Write-Output ("{0}: Beginning {1}" -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 1 # Define how many times we need to loop, to get all alert rules.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all alert rules.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/setting/alert/rules" # Define the resourcePath, based on the type of query you are doing.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    # Update $resourcePath to filter for a specific alert rule, when a alert rule ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$AlertRuleId"

        $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all alert rules, then loop through "GET" that many times.
    While ($currentBatchNum -lt $batchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -in ("IDFilter", "AllAlertRules")} {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updated `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "NameFilter" {
                $queryParams = "?filter=name:$AlertRuleName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the function will exit. The specific error message is: {1}" `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllAlertRules" {
                $message = ("{0}: Entering switch statement for all-alert rule retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no device ID, IP/FQDN, or display name is provided...
                $alertRules += $response.data.items

                $message = ("{0}: There are {1} alert rules in `$alertRules." -f (Get-Date -Format s), $($alertRules.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all alert rules).
                If ($firstLoopDone -eq $false) {
                    [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all alert rules. LogicMonitor reports that there are {2} alert rules." `
                            -f (Get-Date -Format s), $batchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of alert rules.
                $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all alert rules.
                $currentBatchNum++
            }
            # If a device ID, IP/FQDN, or display name is provided...
            {$_ -in ("IDFilter", "NameFilter")} {
                $message = ("{0}: Entering switch statement for single-alert retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $alertRules += $response.data
                }
                Else {
                    $alertRules += $response.data.items
                }

                $message = ("{0}: There are {1} alert rules in `$alertRules." -f (Get-Date -Format s), $($alertRules.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all alert rules).
                If ($firstLoopDone -eq $false) {
                    [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all alert rules. LogicMonitor reports that there are {2} alert rules." `
                            -f (Get-Date -Format s), $batchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all alert rules.
                $currentBatchNum++
            }
        }
    }

    Return $alertRules
} #1.0.0.1
#This function is not in the module, because as is, it only returns up to 10000 alerts (tested 3 May 2017). If LM ever allows me to get all alerts, I will add it to the module.
Function Get-LogicMonitorAlerts {
    <#
.DESCRIPTION 
    Retrieves Alert objects from LogicMonitor.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 16 January 2017
        - Initial release.
    V1.0.0.2 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.3 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Updated logging setup.
.LINK
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER BatchSize
    Default value is 250. Represents the number of alerts to request from LogicMonitor.
.PARAMETER WriteLog
    Switch parameter. When included (and a log path is defined), the script will send output to a log file and to the screen.
.PARAMETER LogPath
    Path where the function should store its log. When omitted, output will be sent to the shell.
.EXAMPLE
    PS C:\> Get-LogicMonitorAlerts -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

    In this example, the function gets all active alerts, in batches of 250.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [int]$BatchSize = 250,

        [switch]$WriteLog,

        [string]$LogPath
    )

    If (-NOT($BlockLogging)) {
        $return = Add-EventLogSource -EventLogSource $EventLogSource
    
        If ($return -ne "Success") {
            $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message -ForegroundColor Yellow;

            $BlockLogging = $True
        }
    }

    $message = Write-Output ("{0}: Beginning {1}" -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

    # Initialize variables.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 0 # Counter so we know how many times we have looped through the request
    $loopDone = $false # Switch for knowing when to stop requesting alerts. Will change to $true once $response.data.items.count is a positive number.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all alerts.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols    
        
    # Define the resourcePath.
    $resourcePath = "/alert/alerts"

    # Determine how many times "GET" must be run, to return all alerts, then loop through "GET" that many times.
    While ($loopDone -ne $true) {
        $message = Write-Output ("{0}: The request loop has run {1} times." -f (Get-Date -Format s), $batchCount)
        If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

        $queryParams = "?offset=$offset&size=$BatchSize&sort=id"
        
        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        # Build header.
        If ($firstLoopDone -eq $false) {
            $message = Write-Output ("{0}: Building request header." -f (Get-Date -Format s))
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

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
            $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", $auth)
            $headers.Add("Content-Type", 'application/json')
        }
        
        # Make Request
        $message = Write-Output ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = Write-Output ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorAlerts function`
                will exit. The specific error message is: {1}" -f (Get-Date -Format s), $_.Message.Exception)
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}
        
            Return
        }

        $alerts += $response.data.items

        # The first time through the loop, figure out how many times we need to loop (to get all alerts).
        If ($firstLoopDone -eq $false) {
            # Get and sort the list of all possible device properties.
            $outputProperties = $response.data.items | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty name
            $outputProperties += $response.data.items.monitorObjectGroups | Select-Object -ExpandProperty name | Sort-Object | Get-Unique
            $outputProperties = $outputProperties | Sort-Object

            $message = Write-Verbose ("{0}: Output properties: {1}" -f (Get-Date -Format s), $outputProperties.name)
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

            $firstLoopDone = $true
        }

        If ($response.data.items.Count -eq $BatchSize) {
            # The response was full of alerts (up to the number in $BatchSize), so there are probably more. Increment offset, to grab the next batch of alerts.
            $message = Write-Output ("{0}: There are more alerts to retrieve. Incrementing offset by {1}." -f (Get-Date -Format s), $BatchSize)
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}
            
            $message = Write-Verbose ("{0}: The value of `$response.data.items.count is {1}." -f (Get-Date -Format s), $($response.data.items.Count))
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

            $offset += $BatchSize
            $batchCount++
        }
        Else {
            # The number of returned alerts was less than the $BatchSize so we must have run out alerts to retrieve.
            $message = Write-Output ("{0}: There are no more alerts to retrieve." -f (Get-Date -Format s))
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}
			
            $message = Write-Verbose ("{0}: The value of `$response.data.items.count is {1}." -f (Get-Date -Format s), $($response.data.items.Count))
            If ($WriteLog -and ($logPath -ne $null)) {Write-Host $message; $message | Out-File -FilePath $logPath -Append} Else {Write-Host $message}

            $loopDone = $true
        }
    }

    # Assign the value of all properties (including custom properties) to a custom PowerhShell object, which the function will return to the pipeline.
    Foreach ($alert in $alerts) {
        Foreach ($property in $outputProperties) {
            $props.$property = $alert.$property
        }
        New-Object PSObject -Property $props
    }
}
#1.0.0.3
Function Get-LogicMonitorAuditLogs {
    <#
.DESCRIPTION 
    Retrieves LogicMonitor audit logs. By default, the last 24 hours of logs are retrieved.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 07 March 2017
        - Initial release.
    V1.0.0.1 date: 13 March 2017
        - Added OutputType parameter to the Confirm-OutputPathAvailability call.
    V1.0.0.2 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.3 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.4 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER StartDate
    Represents the number of milliseconds from January 1, 1970 to the start date of the audit log filter.
.PARAMETER EndDate
    Represents the number of milliseconds from January 1, 1970 to the end date of the audit log filter.
.PARAMETER BatchSize
    Default value is 50. Represents the number of alerts to request from LogicMonitor.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Get-LogicMonitorAuditLogs -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

    In this example, the function gets all audit log events, in batches of 50.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        $StartDate,

        $EndDate,

        [int]$BatchSize = 50,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 0 # Counter so we know how many times we have looped through the request
    $loopDone = $false # Switch for knowing when to stop requesting alerts. Will change to $true once $response.data.items.count is a positive number.
    $firstLoopDone = $false 
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $regex = "^[0-9]*$" # Used later, to confirm that the start and end times are in the correct format.
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
        
    # Define the resourcePath.
    $resourcePath = "/setting/accesslogs"

    # Verify that $startDate and $endDate were provided correctly. If not provided, set start date as 24 hours before now.
    If ((($StartDate -eq $null) -and ($EndDate -ne $null)) -or (($StartDate -ne $null) -and ($EndDate -eq $null))) {
        #If only StartDate /or/ EndDate are provided.
        $message = ("Both the start and end dates are required. You entered {0} for StartDate and {1} for EndDate. To prevent errors, {2} will exit." -f $StartDate, $EndDate, $MyInvocation.MyCommand)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}

        Return
    }
    ElseIf ((($StartDate -ne $null) -and ($StartDate -notmatch $regex)) -or (($EndDate -ne $null) -and ($EndDate -notmatch $regex))) {
        #If StartDate or EndDate are provided, but are not in the correct format.
        $message = ("StartDate and EndDate must be in the format of milliseconds since January 1, 1970. You entered {0} for StartDate and {1} for EndDate. To prevent errors, {2} will exit." -f $StartDate, $EndDate, $MyInvocation.MyCommand)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}

        Return
    }
    ElseIf (($StartDate -eq $null) -and ($EndDate -eq $null)) {
        #If neither StartDate nor EndDate are provided.
        $message = ("Neither StartDate nor EndDate were provided. Using the last 24-hours.")
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $startDate = [int][double]::Parse((Get-Date (get-date).AddHours(-24) -UFormat "%s"))
        $endDate = [int][double]::Parse((Get-Date -UFormat "%s"))
    }

    # Retrieve log entires.
    While ($loopDone -ne $true) {
        $message = ("{0}: The request loop has run {1} times." -f (Get-Date -Format s), $batchCount)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $queryParams = "?offset=$offset&size=$BatchSize&&filter=happenedOn<:$endDate,happenedOn>:$startDate"
        
        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        # Build header.
        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
            $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", $auth)
            $headers.Add("Content-Type", 'application/json')

            $firstLoopDone = $true
        }
        
        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorAuditLo function`
                will exit. The specific error message is: {1}" -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return
        }

        $logEntries += $response.data.items

        If ($response.data.items.Count -eq $BatchSize) {
            # The response was full of log entries (up to the number in $BatchSize), so there are probably more. Increment offset, to grab the next batch of log entries.
            $message = ("{0}: There are more log entries to retrieve. Incrementing offset by {1}." -f (Get-Date -Format s), $BatchSize)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            
            $message = ("{0}: The value of `$response.data.items.count is {1}." -f (Get-Date -Format s), $($response.data.items.Count))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $offset += $BatchSize
            $batchCount++
        }
        Else {
            # The number of returned log entries was less than the $BatchSize so we must have run out log entries to retrieve.
            $message = ("{0}: There are no more log entries to retrieve." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			
            $message = ("{0}: The value of `$response.data.items.count is {1}." -f (Get-Date -Format s), $($response.data.items.Count))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $loopDone = $true
        }
    }

    Return $logEntries
}
#1.0.0.4
Function Get-LogicMonitorCollectorInstaller {
    <#
        .DESCRIPTION 
            Generates and downloads a 64-bit Windows, LogicMonitor Collector installer. If successful, return the download path.
        .NOTES
            Author: Mike Hashemi
            V1 date: 27 December 2016
            V1.0.0.1 date 15 January 2017
                - Added parameter sets for collector properties.
                - Added support for collector ID retrieval based on the hostname.
            V1.0.0.2 date 31 January 2017
                - Updated code to support the Get-LogicMonitorCollectors syntax for ID retrieval.
                - Updated error handling.
            V1.0.0.3 date: 31 January 2017
                - Updated error output color.
                - Streamlined header creation (slightly).
            V1.0.0.4 date: 31 January 2017
                - Added $logPath output to host.
            V1.0.0.5 date: 31 Janyary 2017
                - Added additional logging.
            V1.0.0.6 date: 10 February 2017
                - Updated procedure order.
                - Updated documentation.
            V1.0.0.7 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.8 date: 14 May 2017
                - Fixed bug in output (incorrect index number).
                - Replaced ! with -NOT.
            V1.0.0.9 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.10 date: 10 May 2018
                - Replaced Invoke-WebRequest with a System.Net.WebClient object.
                - Added support for synchronous and asynchronous downloads.
                - Added parameter type casting.
        .LINK
            
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER CollectorID
            Represents the ID number of the desired collector. If no ID is provided and it cannot be found in the registry, the script will exit.
        .PARAMETER CollectorHostName
            Mandatory parameter. Represents the short name of the EDGE Hub.
        .PARAMETER OutputPath
            Mandatory parameter. Represents the path, to which the installer will be downloaded. The default value is $env:TEMP.
        .PARAMETER Async
            When this switch is included, the cmdlet will initiate the download and exit before it is finished. The default behavior is to wait for the download to complete.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorName "server1""

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector "server1". The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorID 11"

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector 11. The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorID 11 -Async"

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector 11. The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
            The cmdlet will continue (and exit) while the download is in progress.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")] 
    Param (
        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccessId,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccessKey,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [int]$CollectorID,

        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$CollectorHostName,

        [string]$OutputPath = $env:TEMP,

        [switch]$Async,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # Initialize variables.
    $hklm = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $data = ''
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    $OutputPath = $OutputPath.TrimEnd("\")

    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath = "/setting/collectors/$CollectorID/installers/Win64"
        }
        Name {
            Try {
                $message = ("{0}: Searching the registry for {1}'s collectorID." -f (Get-Date -Format s), $CollectorHostName)
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                [int]$collectorId = (Get-ItemProperty -Path $hklm -Name LogicMonitorCollectorID -ErrorAction Stop).LogicMonitorCollectorID
            }
            Catch {
                $message = ("{0}: Failed to retrieve the collector Id from the registry. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}

                Try {
                    $message = ("{0}: Attempting to retrieve the collector ID from LogicMonitor." -f (Get-Date -Format s), $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                        
                    # LogicMonitor for the collector hostname and return the id property value, for the one collector matching the desired hostname.
                    $collector = Get-LogicMonitorCollectors -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -CollectorHostname $CollectorHostName
                }
                Catch {
                    $message = ("{0}: Unexpected error retrieving the collector Id from LogicMonitor. To prevent errors, the function Get-LogicMonitorCollectorInstaller will exit. The specific error is: {1}" -f `
                        (Get-Date -Format s), $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
            }

            If ($collector.Id -as [int]) {
                $message = ("{0}: The ID property of {1} is {2}." -f (Get-Date -Format s), $CollectorHostName, $collector.Id)
                If ($BlockLogging) {Write-Verbose $message -ForegroundColor White} Else {Write-Verbose $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $resourcePath = "/setting/collectors/$($collector.Id)/installers/Win64"
            }
            Else {
                $message = ("{0}: The search of LogicMonitor for {1}'s collector ID value returned a non-number. The value is: {2}. To prevent errors, the {3} function will exit." -f `
                    (Get-Date -Format s), $CollectorHostName, $collector.Id, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }	
        }
    }

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
    # Construct Signature
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
    $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

    # Create the web client object and add headers
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", "LMv1 $accessId`:$signature`:$epoch")
    $webClient.Headers.Add("Content-Type", 'application/json')

    # Make Request
    Switch ($Async) {
        $True {
            $message = ("{0}: Beginning download of the LogicMonitor Collector installer to {1}. {2} will continue while the download is in progress." -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $webClient.DownloadFileAsync($url, "$OutputPath\lmInstaller.exe")
                Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -SourceIdentifier WebClient.DownloadFileComplete -Action { Unregister-Event -SourceIdentifier WebClient.DownloadFileComplete; $webClient.Dispose(); }
            }
            Catch {
                $message = ("{0}: Unexpected error downloading the LogicMonitor Collector installer. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            Return "$OutputPath\lmInstaller.exe"
        }
        $False {
            $message = ("{0}: Beginning download of the LogicMonitor Collector installer to {1}. {2} will continue when the download is complete." -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $webClient.DownloadFile($url, "$OutputPath\lmInstaller.exe")
                $webClient.Dispose()
            }
            Catch {
                $message = ("{0}: Unexpected error downloading the LogicMonitor Collector installer. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            If ((Test-Path -Path "$OutputPath\lmInstaller.exe") -and ((Get-Item -Path "$OutputPath\lmInstaller.exe").Length -gt 10MB)) {
                $message = ("{0}: The LogicMonitor installer was downloaded. Returning the download path." -f (Get-Date -Format s))
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                Return "$OutputPath\lmInstaller.exe"
            }
            Else {
                $message = ("{0}: There was no detectable error downloading the LogicMonitor installer, but it is not present in the download location ({1}). To prevent errors, the function {2} will exit" `
                        -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }
        }
    }
}
#1.0.0.10
Function Get-LogicMonitorCollectors {
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
        .LINK

        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER CollectorId
            Represents collector ID of the desired collector. Wildcard searches are not supported.
        .PARAMETER CollectorHostname
            Represents display name of the desired collector. Wildcard searches are not supported.
        .PARAMETER CollectorDescriptionName
            Represents IP address or FQDN of the desired device. Wildcard searches are not supported.
        .PARAMETER BatchSize
            Default value is 250. Represents the number of devices to request in each batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all collectors and will return the properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -CollectorId 6

            In this example, the function will search for a collector with "6" in the id property. The properties of that collector will be returned.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -CollectorHostname collector1

            In this example, the function will search for a collector with "collector1" in the hostname property. The properties of that collector will be returned.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectors -AccessId <accessID> -AccessKey <accessKey> -AccountName <accountName> -CollectorDescriptionName collector1-description

            In this example, the function will search for a collector with "collector1-description" in the hostname property. The properties of that collector will be returned.
    #>
    [CmdletBinding(DefaultParameterSetName = ’AllCollectors’)]
    Param (
        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllCollectors’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’HostnameFilter’)]
        [Parameter(ParameterSetName = ’DescriptionFilter’)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllCollectors’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’HostnameFilter’)]
        [Parameter(ParameterSetName = ’DescriptionFilter’)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllCollectors’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’HostnameFilter’)]
        [Parameter(ParameterSetName = ’DescriptionFilter’)]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$CollectorId,

        [Parameter(Mandatory = $True, ParameterSetName = ’HostnameFilter’)]
        [string]$CollectorHostname,

        [Parameter(Mandatory = $True, ParameterSetName = ’DescriptionFilter’)]
        [string]$CollectorDescriptionName,

        [int]$BatchSize = 250,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $deviceBatchCount = 1 # Define how many times we need to loop, to get all devices.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all devices.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $resourcePath = "/setting/collectors"
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: Retrieving collector properties. The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific collector, when a collector ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$CollectorId"

        $message = ("{0}: A collector ID was provided. Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all collectors, then loop through "GET" that many times.
    While ($currentBatchNum -lt $deviceBatchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -in ("IDFilter", "AllCollectors")} {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "HostnameFilter" {
                $queryParams = "?filter=hostname~$CollectorHostname&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "DescriptionFilter" {
                $queryParams = "?filter=description:$CollectorDescriptionName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllCollectors" {
                $message = ("{0}: Entering switch statement for all-collector retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no collector ID, IP/FQDN, or display name is provided...
                $devices += $response.data.items

                $message = ("{0}: There are {1} collectors in `$devices." -f (Get-Date -Format s), $($devices.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all collectors).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all collectors." -f (Get-Date -Format s), $deviceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $true

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of collectors.
                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all collectors.
                $currentBatchNum++

            }
            # If a collector ID, IP/FQDN, or display name is provided...
            {$_ -in ("IDFilter", "HostnameFilter", "DescriptionFilter")} {
                $message = ("{0}: Entering switch statement for single-collector retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $devices = $response.data
                }
                Else {
                    $devices = $response.data.items
                }

                If ($devices.count -eq 0) {
                    $message = ("{0}: There was an error retrieving the collector. LogicMonitor reported that zero collectors were retrieved. The error is: {1}" -f (Get-Date -Format s), $response.errmsg)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
                Else {
                    $message = ("{0}: There are {1} collectors in `$devices." -f (Get-Date -Format s), $($devices.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # The first time through the loop, figure out how many times we need to loop (to get all collectors).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all collectors." -f (Get-Date -Format s), $deviceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $True

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all collectors.
                $currentBatchNum++
            }
        }
    }

    Return $devices
}
#1.0.0.10
Function Get-LogicMonitorCollectorUpgradeHistory {
    <#
        .DESCRIPTION
            Retrieves collector upgrade status from LogicMonitor.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 10 August 2018
                - Initial release.
            V1.0.0.1 date: 7 September 2018
                - Fixed bug preventing correct history output.
                - Fixed bug stopping the retrieval loop prematurely.
        .LINK
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of alert rules to request from LogicMonitor.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorUpgradeHistory -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

            In this example, the function gets upgrade history for all collectors, in batches of 1000. Output is logged to the application log, and written to the host.
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllCollectors')]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

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

    $message = Write-Output ("{0}: Beginning {1}" -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 1 # Define how many times we need to loop, to get all alert rules.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all alert rules.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/setting/collector/collectors/upgradeHistory" # Define the resourcePath, based on the type of query you are doing.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    # Determine how many times "GET" must be run, to return all alert rules, then loop through "GET" that many times.
    While ($currentBatchNum -le $batchCount) {
        $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the function will exit. The specific error message is: {1}" `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return
        }

        $histories += $response.items

        $message = ("{0}: There are {1} alert rules in `$histories." -f (Get-Date -Format s), $($histories.count))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # The first time through the loop, figure out how many times we need to loop (to get all alert rules).
        If ($firstLoopDone -eq $false) {
            [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

            $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all alert rules. LogicMonitor reports that there are {2} alert rules." `
                    -f (Get-Date -Format s), $batchCount, $response.data.total)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }

        # Increment offset, to grab the next batch of alert rules.
        $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $offset += $BatchSize

        $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # Increment the variable, so we know when we have retrieved all alert rules.
        $currentBatchNum++
    }

    Return $histories
} #1.0.0.1
Function Get-LogicMonitorDataSources {
    <#
        .DESCRIPTION 
            Returns a list of LogicMonitor DataSources. By default, the function returns all datasources. If a DataSource ID or name is provided, the function will 
            return properties for the specified DataSource.
        .NOTES 
            Author: Mike Hashemi
            V1.0.0.0 date: 5 March 2017
                - Initial release.
                - Bug in the AppliesToFilter parameter set. Engaged LogicMonitor for support.
            V1.0.0.2 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.3 date: 21 June 2017
                - Updated logging to reduce chatter.
            V1.0.0.4 date: 1 August 2017
                - Updated code to support XML output when a DataSource ID is provided.
            V1.0.0.5 date: 18 August 2017
                - Changed the "AppliesTo" query filter.
            V1.0.0.6 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.7 date: 15 May 2018
                - Fixed typo in the cmdlet name.
            V1.0.0.8 date: 14 June 2018
                - Updated whitespace.
            V1.0.0.9 date: 21 June 2018
                - Added encoding of &, to UTF-8.
                - Added example.
        .LINK
            https://git.synoptek.com/tools-group/logicmonitor/Synoptek.LogicMonitor.PowershellModule
        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER DataSourceId
            Represents the ID of the desired DataSource.
        .PARAMETER XmlOutput
            When included, the function will request XML output from LogicMonitor. The switch is only available when a DataSource ID is specified.
        .PARAMETER DataSourceDisplayName
            Represents the display name of the desired DataSource.
        .PARAMETER DataSourceApplyTo
            Represents the "AppliesTo" filter of the desired DataSource.
        .PARAMETER BatchSize
            Default value is 950. Represents the number of DataSoruces to request from LogicMonitor, in a single batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all monitored devices and will return their properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DataSourceId 6

            In this example, the function returns the DataSource with ID '6'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DataSourceId 6 -XmlOutput

            In this example, the function returns the DataSource with ID '6', in XML format.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DataSourceDisplayName 'Oracle Library Cache'

            In this example, the function returns the DataSource with display name 'Oracle Library Cache'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DataSourceApplyTo 'system.hostname =~ "255.1.1.1"'

            In this example, the function returns the DataSource with the 'appliesTo' filter 'system.hostname =~ "255.1.1.1"'.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDataSources -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DataSourceApplyTo 'isWindows()&&hasCategory("collector")'

            In this example, the function returns the DataSource with the 'appliesTo' filter 'isWindows()&&hasCategory("collector")'.
    #>
    [CmdletBinding(DefaultParameterSetName = ’AllDataSources’)]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$DataSourceId,

        [Parameter(ParameterSetName = ’IDFilter’)]
        [switch]$XmlOutput,

        [Parameter(Mandatory = $True, ParameterSetName = 'DisplayNameFilter')]
        [string]$DataSourceDisplayName,

        [Parameter(Mandatory = $True, ParameterSetName = 'AppliesToFilter')]
        [string]$DataSourceApplyTo,

        [int]$BatchSize = 950,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    [int]$offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    [int]$dataSourceBatchCount = 1 # Define how many times we need to loop, to get all DataSource.
    [boolean] $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all DataSources.
    [string]$httpVerb = "GET" # Define what HTTP operation will the script run.
    [string]$resourcePath = "/setting/datasources" # Define the resourcePath.
    $queryParams = $null
    $dataSources = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific DataSource, when a DataSource ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$DataSourceId"

        $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all DataSources, then loop through "GET" that many times.
    While ($currentBatchNum -lt $dataSourceBatchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            "AllDataSources" {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "IDFilter" {
                If ($XmlOutput) {
                    $queryParams = "?format=xml&offset=$offset&size=$BatchSize&sort=id"
                }
                Else {
                    $queryParams = "?offset=$offset&size=$BatchSize&sort=id"
                }

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "DisplayNameFilter" {
                $queryParams = "?filter=displayName:$DataSourceDisplayName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "AppliesToFilter" {
                # Need to encode the ampersands in UTF-8, so the API will interpret them correctly.
                If ($DataSourceApplyTo -match '&') {
                    $DataSourceApplyTo = $DataSourceApplyTo.Replace("&", "%26")
                }
                $queryParams = "?filter=appliesTo:$DataSourceApplyTo&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, {1} function will exit. The specific error message is: {2}" `
                    -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllDataSources" {
                $message = ("{0}: Entering switch statement for all-DataSource retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no DataSource ID is provided...
                $dataSources += $response.data.items

                $message = ("{0}: There are {1} DataSources in `$dataSources." -f (Get-Date -Format s), $($dataSources.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all DataSources).
                If ($firstLoopDone -eq $false) {
                    [int]$dataSourceBatchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all DataSources. LogicMonitor reports that there are {2} DataSources." `
                            -f (Get-Date -Format s), $dataSourceBatchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of DataSources.
                $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $dataSourceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all DataSources.
                $currentBatchNum++
            }
            {$_ -in ("IDFilter", "DisplayNameFilter", "AppliesToFilter")} {
                $message = ("{0}: Entering switch statement for single-DataSource retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($XmlOutput) {
                    $dataSources = $response
                }
                Else {
                    $dataSources = $response.data ###Should this be $response.data.items? What about just for displaynamefilter and appliestofilter
                }

                $message = ("{0}: There are {1} DataSources in `$dataSources." -f (Get-Date -Format s), $($dataSources.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all DataSources).
                If ($firstLoopDone -eq $false) {
                    [int]$dataSourceBatchCount = ((($response.data.total) / 250) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all DataSources." -f (Get-Date -Format s), $dataSourceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $True

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $dataSourceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all DataSources.
                $currentBatchNum++
            }
        }
    }

    Return $dataSources
} #1.0.0.9
Function Get-LogicMonitorDeviceGroupProperties {
    <#
        .DESCRIPTION
            Retrieves all properties (inherited and not) from a selected device group.
        .NOTES 
            Author: Mike Hashemi
            V1.0.0.0 date: 2 July 2017
                - Initial release.
            V1.0.0.1 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.2 date: 30 August 2018
                - Fixed a bug getting group ID when a name is provided.
                - Updated white space.
        .LINK

        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER GroupID
            Represents ID of the desired device group.
        .PARAMETER GroupName
            Represents the name of the desired device group. If more than one group has the same name (e.g. "servers"), then they will all be returned.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all device groups and will return their properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -GroupId 6

            In this example, the function will search for the device group with "6" in the ID property and will return its properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -GroupName customer1

            In this example, the function will search for the device group with "customer1" in the name property and will return its properties. If more than one group has the same name (e.g. "servers"), then they will all be returned.
    #>
    [CmdletBinding(DefaultParameterSetName = ’AllGroups’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$GroupID,

        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$GroupName,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $groupBatchCount = 1 # Define how many times we need to loop, to get all services.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all services.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $resourcePath = "/device/groups"
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: Retrieving group properties. The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific device.
    Switch ($PsCmdlet.ParameterSetName) {
        "NameFilter" {	
            $group = Get-LogicMonitorDeviceGroups -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -GroupName $GroupName -EventLogSource $EventLogSource

            $groupId = $group.id
        }
    }

    $resourcePath += "/$groupId/properties"

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    $message = ("{0}: Building request header." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, {1} will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Return
    }

    Return $response.data.items
} #1.0.0.2
Function Get-LogicMonitorDeviceGroups {
    <#
.DESCRIPTION 
    Returns a list of all LogicMonitor-monitored devices and all of their properties.   
.NOTES 
    Author: Mike Hashemi
    V1 date: 21 November 2016
    V1.0.0.1 date: 31 January 2017
        - Removed custom-object creation.
        - Added support for group retrieval based on ID or name.
    V1.0.0.2 date: 31 January 2017
        - Updated error output color.
        - Streamlined header creation (slightly).
    V1.0.0.3 date 31 January 2017
        - Added $logPath output to host.
    V1.0.0.4 date 31 January 2017
        - Added additional logging.
    V1.0.0.5 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.6 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.7 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.8 date: 2 July 2017
        - Added parameter variable type casting.
    V1.0.0.9 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.    
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER GroupID
    Represents ID of the desired device group.
.PARAMETER GroupName
    Represents the name of the desired device group. If more than one group has the same name (e.g. "servers"), then they will all be returned.
.PARAMETER BatchSize
    Default value is 250. Represents the number of devices to request in each query.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

    In this example, the function will search for all device groups and will return their properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -GroupId 6

    In this example, the function will search for the device group with "6" in the ID property and will return its properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -GroupName customer1

    In this example, the function will search for the device group with "customer1" in the name property and will return its properties. If more than one group has the same name (e.g. "servers"), then they will all be returned.
#>
    [CmdletBinding(DefaultParameterSetName = ’AllGroups’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$GroupID,

        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$GroupName,

        [int]$BatchSize = 250,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $groupBatchCount = 1 # Define how many times we need to loop, to get all services.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all services.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $resourcePath = "/device/groups"
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: Retrieving group properties. The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific service, when a service ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$GroupID"

        $message = ("{0}: A collector ID was provided. Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all groups, then loop through "GET" that many times.
    While ($currentBatchNum -lt $groupBatchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -in ("IDFilter", "AllGroups")} {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "NameFilter" {				
                $queryParams = "?filter=name:$GroupName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorServices function will exit. The specific error message is: {1}. " `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllGroups" {
                $message = ("{0}: Entering switch statement for all-group retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no service ID, or name is provided...
                $retrievedGroups += $response.data.items

                $message = ("{0}: There are {1} groups in `$retrievedGroups. LogicMonitor reports a total of {2} groups." -f (Get-Date -Format s), $($retrievedGroups.count), $($response.data.total))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all groups).
                If ($firstLoopDone -eq $false) {
                    [int]$groupBatchCount = ((($response.data.total) / $BatchSize) + 1)
					
                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all groups." -f (Get-Date -Format s), ($groupBatchCount - 1))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $true

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of services.
                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, ($groupBatchCount - 1))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            # If a group ID, or name is provided...
            {$_ -in ("IDFilter", "NameFilter")} {
                $message = ("{0}: Entering switch statement for single-groups retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                
                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $retrievedGroups = $response.data
                }
                Else {
                    $retrievedGroups = $response.data.items
                }

                If ($retrievedGroups.count -eq 0) {
                    $message = ("{0}: There was an error retrieving the group. LogicMonitor reported that zero groups were retrieved. The error is: {1}" -f (Get-Date -Format s), $response.errmsg)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
                Else {
                    $message = ("{0}: There are {1} groups in `$retrievedGroups." -f (Get-Date -Format s), $($retrievedGroups.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # The first time through the loop, figure out how many times we need to loop (to get all services).
                If ($firstLoopDone -eq $false) {
                    [int]$groupBatchCount = ((($response.data.total) / $BatchSize) + 1)
					
                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve groups." -f (Get-Date -Format s), ($groupBatchCount - 1))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $True

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, ($groupBatchCount - 1))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        } 
		
        # Increment the variable, so we know when we have retrieved all services.
        $currentBatchNum++
    }

    Return $retrievedGroups
} #1.0.0.9
Function Get-LogicMonitorDeviceProperties {
    <#
.DESCRIPTION 
    Retrieves all properties (inherited and not) from a selected device.    
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 08 March 2017
        - Initial release.
    V1.0.0.1 date: 13 March 2017
        - Added OutputType paramater to Confirm-OutputPathAvailability call.
    V1.0.0.2 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.3 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.4 date: 2 July 2017
        - Added $EventLogSource to Get-LogicMonitorDevices call.
    V1.0.0.5 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.        
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER DeviceId
    Represents deviceId of the desired device.
.PARAMETER DeviceDisplayName
    Represents display name of the desired device.
.PARAMETER DeviceName
    Represents IP address or FQDN of the desired device.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

    In this example, the function will search for all monitored devices and will return their properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 6

    In this example, the function will search for the monitored device with "6" in the ID property and will return its properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName server1

    In this example, the function will search for the monitored device with "server1" in the displayName property and will return its properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName 10.1.1.1

    In this example, the function will search for the monitored device with "10.1.1.1" in the name property and will return its properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName server1.domain.local

    In this example, the function will search for the monitored device with "server1.domain.local" (the FQDN) in the name property and will return its properties.
#>
    [CmdletBinding(DefaultParameterSetName = ’IDFilter’)]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,
        [Parameter(Mandatory = $True)]
        $AccessKey,
        [Parameter(Mandatory = $True)]
        $AccountName,
        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$DeviceId,
        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$DeviceDisplayName,
        [Parameter(Mandatory = $True, ParameterSetName = ’IPFilter’)]
        [string]$DeviceName,
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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $deviceBatchCount = 1 # Define how many times we need to loop, to get all devices.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all devices.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $resourcePath = "/device/devices" # Define the resourcePath, based on the type of device you're searching for.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific device.
    Switch ($PsCmdlet.ParameterSetName) {
        "NameFilter" {	
            $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceDisplayName $DeviceDisplayName -EventLogSource $EventLogSource
            
            $deviceId = $device.id
        }
        "IPFilter" {
            $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceName $DeviceName -EventLogSource $EventLogSource
            
            $deviceId = $device.id
        }
    }

    $resourcePath += "/$DeviceId/properties"

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    $message = ("{0}: Building request header." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorDevices function will exit. The specific error message is: {1}" `
                -f (Get-Date -Format s), $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        
        Return
    }

    $devices = $response.data.items
	
    Return $devices
} #1.0.0.5
Function Get-LogicMonitorDevices {
    <#
        .DESCRIPTION 
            Returns a list of LogicMonitor-monitored devices and all of their properties. By default, the function returns all devices. 
            If a device ID, device name (IP or DNS name), or device display name is provided, the function will return properties for 
            the specified device.
        .NOTES 
            Author: Mike Hashemi
            V1 date: 21 November 2016
            V1.0.0.1 date: 13 January 2017
                - Added support for single-device retrieval.
            V1.0.0.2 date: 31 January 2017
                - Removed custom-object creation.
            V1.0.0.3 date: 31 January 2017
                - Updated error output color.
                - Streamlined header creation (slightly).
            V1.0.0.4 date: 31 January 2017
                - Added $logPath output to host.
            V1.0.0.5 date: 31 January 2017
                - Added additional logging.
            V1.0.0.6 date: 10 February 2017
                - Updated procedure order.
            V1.0.0.7 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.8 date: 21 June 2017
                - Updated logging to reduce chatter.
            V1.0.0.9 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
                - Replaced ! with -NOT.
            V10.0.0.10 date: 16 June 2018
                - Updated tabs.
                - Removed $props hash table, since it is not used.
        .LINK
            
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER DeviceId
            Represents deviceId of the desired device.
        .PARAMETER DeviceDisplayName
            Represents display name of the desired device.
        .PARAMETER DeviceName
            Represents IP address or FQDN of the desired device.
        .PARAMETER BatchSize
            Default value is 300. Represents the number of devices to request from LogicMonitor, in a single batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

            In this example, the function will search for all monitored devices and will return their properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 6

            In this example, the function will search for the monitored device with "6" in the ID property and will return its properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName server1

            In this example, the function will search for the monitored device with "server1" in the displayName property and will return its properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName 10.1.1.1

            In this example, the function will search for the monitored device with "10.1.1.1" in the name property and will return its properties.
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName server1.domain.local

            In this example, the function will search for the monitored device with "server1.domain.local" (the FQDN) in the name property and will return its properties.
    #>
    [CmdletBinding(DefaultParameterSetName = ’AllDevices’)]
    Param (
        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllDevices’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’NameFilter’)]
        [Parameter(ParameterSetName = ’IPFilter’)]
        $AccessId,
        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllDevices’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’NameFilter’)]
        [Parameter(ParameterSetName = ’IPFilter’)]
        $AccessKey,
        [Parameter(Mandatory = $True)]
        [Parameter(ParameterSetName = ’AllDevices’)]
        [Parameter(ParameterSetName = ’IDFilter’)]
        [Parameter(ParameterSetName = ’NameFilter’)]
        [Parameter(ParameterSetName = ’IPFilter’)]
        $AccountName,
        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$DeviceId,
        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$DeviceDisplayName,
        [Parameter(Mandatory = $True, ParameterSetName = ’IPFilter’)]
        [string]$DeviceName,
        [int]$BatchSize = 300,
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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $deviceBatchCount = 1 # Define how many times we need to loop, to get all devices.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all devices.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/device/devices" # Define the resourcePath, based on the type of device you're searching for.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific device, when a device ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$DeviceId"
			
        $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all devices, then loop through "GET" that many times.
    While ($currentBatchNum -lt $deviceBatchCount) { 
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -in ("IDFilter", "AllDevices")} {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updated `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "NameFilter" {	
                $queryParams = "?filter=displayName:$DeviceDisplayName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "IPFilter" {
                $queryParams = "?filter=name:$DeviceName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorDevices function will exit. The specific error message is: {1}" `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllDevices" {
                $message = ("{0}: Entering switch statement for all-device retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no device ID, IP/FQDN, or display name is provided...
                $devices += $response.data.items

                $message = ("{0}: There are {1} devices in `$devices." -f (Get-Date -Format s), $($devices.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all devices).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.data.total) / $BatchSize) + 1)
					
                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all devices. LogicMonitor reports that there are {2} devices." `
                            -f (Get-Date -Format s), $deviceBatchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of devices.
                $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all devices.
                $currentBatchNum++
            }
            # If a device ID, IP/FQDN, or display name is provided...
            {$_ -in ("IDFilter", "NameFilter", "IPFilter")} {
                $message = ("{0}: Entering switch statement for single-device retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $devices = $response.data
                }
                Else {
                    $devices = $response.data.items
                }
				
                $message = ("{0}: There are {1} devices in `$devices." -f (Get-Date -Format s), $($devices.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all devices).
                If ($firstLoopDone -eq $false) {
                    [int]$deviceBatchCount = ((($response.data.total) / 250) + 1)
					
                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all devices." -f (Get-Date -Format s), $deviceBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $firstLoopDone = $True

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $deviceBatchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all devices.
                $currentBatchNum++
            }
        }
    }

    Return $devices
} #1.0.0.10
Function Get-LogicMonitorRoles {
    <#
        .DESCRIPTION
            Retrieves role objects from LogicMonitor.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 8 August 2018
                - Initial release.
        .LINK
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of roles to request from LogicMonitor.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorRoles -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

            In this example, the function gets all roles, in batches of 1000. Output is logged to the application log, and written to the host.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

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

    $message = Write-Output ("{0}: Beginning {1}" -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 1 # Define how many times we need to loop, to get all roles.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all roles.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/setting/roles" # Define the resourcePath, based on the type of query you are doing.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols


    # Determine how many times "GET" must be run, to return all roles, then loop through "GET" that many times.
    While ($currentBatchNum -lt $batchCount) {
        $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the function will exit. The specific error message is: {1}" `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return
        }

        $roles += $response.data.items

        $message = ("{0}: There are {1} roles in `$roles." -f (Get-Date -Format s), $($roles.count))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # The first time through the loop, figure out how many times we need to loop (to get all roles).
        If ($firstLoopDone -eq $false) {
            [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

            $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all roles. LogicMonitor reports that there are {2} roles." `
                    -f (Get-Date -Format s), $batchCount, $response.data.total)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }

        # Increment offset, to grab the next batch of roles.
        $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $offset += $BatchSize

        $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # Increment the variable, so we know when we have retrieved all roles.
        $currentBatchNum++
    }

    Return $roles
} #1.0.0.0
Function Get-LogicMonitorSdt {
    <#
        .DESCRIPTION 
            Retrieves a list of Standard Down Time (SDT) entries from LogicMonitor. The cmdlet allows for the retrieval of a specific SDT entry, all entries, or all entries initiated by a specific user. 

            The list of SDT entries are further filterable by type of monitored object.
        .NOTES 
            Author: Mike Hashemi
            V1.0.0.0 date: 9 July 2018
                - Initial release.
            V1.0.0.1 date: 9 July 2018
                - Changed references to "devices", to "SDT entries".
                - Added parameter site assignment to the SdtEntry parameter, so it cannot be used with the SdtId parameter set.
        .LINK

        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER SdtId
            Represents the ID of a specific SDT entry. Accepts pipeline input.
        .PARAMETER AdminName
            Represents the user name of the user who created the SDT entry.
        .PARAMETER SdtType
            Represents the type of SDT entries which to return. Valid values are CollectorSDT, DeviceGroupSDT, DeviceSDT, ServiceCheckpointSDT, ServiceSDT.
        .PARAMETER IsEffective
            When included, only returns SDT entries that are currently active.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of SDT entries to request from LogicMonitor, in a single batch.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule". Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorSdt -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -SdtId A_8

            This example shows how to get the SDT entry with ID "A_8".
        .EXAMPLE
            PS C:\> $allSdts = Get-LogicMonitorSdt -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -Blocklogging

            This example shows how to get all SDT entries and store them in a variable called "allSdts". The command's logging is output only to the host, and not to the event log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorSdt -AccessId $accessID -AccessKey $AccessKey -AccountName <account name> -AdminName <username> -SdtType DeviceGroupSDT

            This example shows how to get all device group SDT entries created by the user in <username>. 
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllSdt')]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Id", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$SdtId,

        [Parameter(Mandatory = $True, ParameterSetName = "AdminName")]
        [string]$AdminName,

        [Parameter(Mandatory = $True, ParameterSetName = "AdminName", "Id", "AllSdt")]
        [ValidateSet('CollectorSDT', 'DeviceGroupSDT', 'DeviceSDT', 'ServiceCheckpointSDT', 'ServiceSDT')]
        [string]$SdtType,

        [switch]$IsEffective,

        [int]$BatchSize = 1000,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    Begin {
        # Initialize variables.
        $filter = $null # The script
        $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
        $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
        $sdtBatchCount = 1 # Define how many times we need to loop, to get all SDT entries.
        $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all SDT entries.
        $httpVerb = "GET" # Define what HTTP operation will the script run.
        $resourcePath = "/sdt/sdts" # Define the resourcePath, based on what you're searching for.
        $queryParams = $null
        $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    }
    Process {
        If (-NOT($BlockLogging)) {
            $return = Add-EventLogSource -EventLogSource $EventLogSource

            If ($return -ne "Success") {
                $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
                Write-Host $message -ForegroundColor Yellow;

                $BlockLogging = $True
            }
        }

        # Update $resourcePath to filter for a specific SDT entry, when a SDT ID is provided by the user.
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -eq "Id"} {
                $resourcePath += "/$SdtId"

                $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Build the filter, if any of the following conditions are met.
        Switch ($IsEffective, $SdtType) {
            {$_.IsPresent} {
                $filter += 'isEffective:True,'

                $message = ("{0}: Updating `$filter variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                Continue
            }
            {$_ -in 'CollectorSDT', 'DeviceGroupSDT', 'DeviceSDT', 'ServiceCheckpointSDT', 'ServiceSDT'} {
                $filter += "type:$sdtType,"

                $message = ("{0}: Updating `$filter variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                Continue
            }
        }

        If ($PsCmdlet.ParameterSetName -eq "AdminName") {
            $filter += "admin:$AdminName,"

            $message = ("{0}: Updating `$filter variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }

        If (-NOT([string]::IsNullOrEmpty($filter))) {
            $filter = $filter.TrimEnd(",")
        }

        # Determine how many times "GET" must be run, to return all SDT entries, then loop through "GET" that many times.
        While ($currentBatchNum -lt $sdtBatchCount) {
            Switch ($PsCmdlet.ParameterSetName) {
                {$_ -in ("Id", "AllSdt")} {
                    If ([string]::IsNullOrEmpty($filter)) {
                        $queryParams = "?offset=$offset&size=$BatchSize&sort=id"
                    }
                    Else {
                        $queryParams = "?filter=$filter&offset=$offset&size=$BatchSize&sort=id"
                    }

                    $message = ("{0}: Updated `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }
                "AdminName" {
                    If ([string]::IsNullOrEmpty($filter)) {
                        $queryParams = "?offset=$offset&size=$BatchSize&sort=id"
                    }
                    Else {
                        $queryParams = "?filter=$filter&offset=$offset&size=$BatchSize&sort=id"
                    }

                    $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }
            }

            # Construct the query URL.
            $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

            If ($firstLoopDone -eq $false) {
                $message = ("{0}: Building request header." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
            }

            # Make Request
            $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
            }
            Catch {
                $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, {1} will exit. The specific error message is: {2}" -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return
            }

            Switch ($PsCmdlet.ParameterSetName) {
                {$_ -in ("AllSdt", "AdminName")} {
                    $message = ("{0}: Entering switch statement for all-SDT retrieval." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $sdts += $response.data.items

                    $message = ("{0}: There are {1} SDT entries in `$sdts." -f (Get-Date -Format s), $($sdts.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    # The first time through the loop, figure out how many times we need to loop (to get all SDT entries).
                    If ($firstLoopDone -eq $false) {
                        [int]$sdtBatchCount = ((($response.data.total) / $BatchSize) + 1)

                        $message = ("{0}: {1} will query LogicMonitor {2} times to retrieve all SDT entries. LogicMonitor reports that there are {3} SDT entries." `
                                -f (Get-Date -Format s), $MyInvocation.MyCommand, $sdtBatchCount, $response.data.total)
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                        $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                    }

                    # Increment offset, to grab the next batch of SDT entries.
                    $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $offset += $BatchSize

                    $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $sdtBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    # Increment the variable, so we know when we have retrieved all SDT entries.
                    $currentBatchNum++
                }
                "Id" {
                    $message = ("{0}: Entering switch statement for single-SDT retrieval." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $sdts = $response.data

                    $message = ("{0}: There are {1} SDT entries in `$sdts." -f (Get-Date -Format s), $($sdts.count))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    # The first time through the loop, figure out how many times we need to loop (to get all SDT entries).
                    If ($firstLoopDone -eq $false) {
                        [int]$sdtBatchCount = ((($response.data.total) / 250) + 1)

                        $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all SDT entries." -f (Get-Date -Format s), $sdtBatchCount)
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                        $firstLoopDone = $True

                        $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                    }

                    $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $sdtBatchCount)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    # Increment the variable, so we know when we have retrieved all SDT entries.
                    $currentBatchNum++
                }
            }
        }

        Return $sdts
    }
} #1.0.0.1
Function Get-LogicMonitorServiceProperties {
    <#
.DESCRIPTION 
    Retrieve properties of LogicMonitor services (e.g. ping checks and website transaction).
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 12 March 2017
        - Initial release.
    V1.0.0.1 date: 13 March 2017
        - Added OutputType paramater to Confirm-OutputPathAvailability call.
    V1.0.0.2 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.3 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.4 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.        
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER ServiceId
    Represents serviceId of the desired service.
.PARAMETER ServiceName
    Represents the name of the desired service.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Get-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> 

    
.EXAMPLE
    PS C:\> Get-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> 

    
.EXAMPLE
    PS C:\> Get-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> 

    
.EXAMPLE
    PS C:\> Get-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> 

    
.EXAMPLE
    PS C:\> Get-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> 

    
#>
    [CmdletBinding(DefaultParameterSetName = ’IDFilter’)]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,
        [Parameter(Mandatory = $True)]
        $AccessKey,
        [Parameter(Mandatory = $True)]
        $AccountName,
        [Parameter(Mandatory = $True, ParameterSetName = ’IDFilter’)]
        [int]$ServiceId,
        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$ServiceName,
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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    $message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $serviceBatchCount = 1 # Define how many times we need to loop, to get all services.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all services.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
    $resourcePath = "/service/services" # Define the resourcePath, based on the type of service you're searching for.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols    

    $message = ("{0}: The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific service.
    Switch ($PsCmdlet.ParameterSetName) {
        "NameFilter" {	
            $service = Get-LogicMonitorServices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -ServiceName $ServiceName
            
            $serviceId = $service.id

            $message = ("{0}: Found ID {1} for {2}." -f (Get-Date -Format s), $serviceId, $ServiceName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }
    }

    $resourcePath += "/$ServiceId/properties"

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    $message = ("{0}: Building request header." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
        Return
    }

    $services = $response.data.items
	
    Return $services
} #V1.0.0.4
Function Get-LogicMonitorServices {
<#
.DESCRIPTION 
    Returns a list of LogicMonitor services and all of their properties. By default, the function returns all services. 
    If a service ID, or name is provided, the function will return properties for the specified service.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 30 January 2017
    V1.0.0.1 date: 31 January 2017
        - Removed custom-object creation.
    V1.0.0.2 date: 31 January 2017
        - Updated error output color.
        - Streamlined header creation (slightly).
    V1.0.0.3 date 31 January 2017
        - Added $logPath output to host.
    V1.0.0.4 date 31 January 2017
        - Added additional logging.
    V1.0.0.5 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.6 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.7 date: 21 June 2017
		- Updated logging to reduce chatter.
    V1.0.0.8 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER ServiceID
    Represents the ID of the desired service.
.PARAMETER ServiceName
    Represents the name of the desired service.
.PARAMETER BatchSize
	Default value is 300. Represents the number of devices to request in each batch.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Get-LogicMonitorServices -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName>

    In this example, the function will search for all services and will return their properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ServiceID 6

    In this example, the function will search for the service with "6" in the ID property and will return its properties.
.EXAMPLE
    PS C:\> Get-LogicMonitorDeviceGroups -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ServiceName webMonitor1

    In this example, the function will search for the service with "webMonitor1" in the name property and will return its properties.
#>
[CmdletBinding(DefaultParameterSetName=’AllServices’)]
    Param (
        [Parameter(Mandatory=$True)]
		[Parameter(ParameterSetName=’AllServices’)]
		[Parameter(ParameterSetName=’IDFilter’)]
		[Parameter(ParameterSetName=’NameFilter’)]
        $AccessId,

        [Parameter(Mandatory=$True)]
		[Parameter(ParameterSetName=’AllServices’)]
		[Parameter(ParameterSetName=’IDFilter’)]
		[Parameter(ParameterSetName=’NameFilter’)]
        $AccessKey,

		[Parameter(Mandatory=$True)]
		[Parameter(ParameterSetName=’AllServices’)]
		[Parameter(ParameterSetName=’IDFilter’)]
		[Parameter(ParameterSetName=’NameFilter’)]
        $AccountName,

        [Parameter(Mandatory=$True,ParameterSetName=’IDFilter’)]
        [int]$ServiceID,

        [Parameter(Mandatory=$True,ParameterSetName=’NameFilter’)]
        [string]$ServiceName,

		[int]$BatchSize = 300,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

	$message = ("{0}: Operating in the {1} parameter set." -f (Get-Date -Format s), $PsCmdlet.ParameterSetName)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $serviceBatchCount = 1 # Define how many times we need to loop, to get all services.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all services.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $props = @{} # Initialize hash table for custom object (created later).
	$resourcePath = "/service/services"
	$queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
	
    $message = ("{0}: Retrieving service properties. The resource path is: {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific service, when a service ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
   		$resourcePath += "/$ServiceID"

		$message = ("{0}: A collector ID was provided. Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
		If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
	}

    # Determine how many times "GET" must be run, to return all services, then loop through "GET" that many times.
    While ($currentBatchNum -lt $serviceBatchCount) { 
		Switch ($PsCmdlet.ParameterSetName) {
			{$_ -in ("IDFilter", "AllServices")} {
				$queryParams ="?offset=$offset&size=$BatchSize&sort=id"

				$message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			}
			"NameFilter" {				
				$queryParams = "?filter=name:$ServiceName&offset=$offset&size=$BatchSize&sort=id"

				$message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			}
		}

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
			$message = ("{0}: Building request header." -f (Get-Date -Format s))
			If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

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
			$headers.Add("Authorization","LMv1 $accessId`:$signature`:$epoch")
			$headers.Add("Content-Type",'application/json')
		}

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Get-LogicMonitorServices function will exit. The specific error message is: {1}" `
                -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return
        }

		Switch ($PsCmdlet.ParameterSetName) {
			"AllServices" {
				$message = ("{0}: Entering switch statement for all-service retrieval." -f (Get-Date -Format s))
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

				# If no service ID, or name is provided...
				$services += $response.data.items

				$message = ("{0}: There are {1} services in `$services. LogicMonitor reports a total of {2} services." -f (Get-Date -Format s), $($services.count), $($response.data.count))
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

				# The first time through the loop, figure out how many times we need to loop (to get all services).
				If ($firstLoopDone -eq $false) {
					[int]$serviceBatchCount = ((($response.data.total)/$BatchSize) + 1)
					
					$message = ("{0}: The function will query LogicMonitor {1} times to retrieve all services." -f (Get-Date -Format s), ($serviceBatchCount-1))
					If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

					$firstLoopDone = $true

					$message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
					If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
				}

				# Increment offset, to grab the next batch of services.
				$offset += $BatchSize

				$message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, ($serviceBatchCount-1))
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

				# Increment the variable, so we know when we have retrieved all services.
				$currentBatchNum++
			}
			# If a service ID, or name is provided...
			{$_ -in ("IDFilter", "NameFilter")} {
				$message = ("{0}: Entering switch statement for single-service retrieval." -f (Get-Date -Format s))
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                
                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
					$services = $response.data
				}
			    Else {
				    $services = $response.data.items
			    }

                If ($services.count -eq 0) {
				    $message = ("{0}: There was an error retrieving the service. LogicMonitor reported that zero services were retrieved." -f (Get-Date -Format s))
				    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
				Else {
				    $message = ("{0}: There are {1} services in `$services." -f (Get-Date -Format s), $($services.count))
				    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

				# The first time through the loop, figure out how many times we need to loop (to get all services).
				If ($firstLoopDone -eq $false) {
					[int]$serviceBatchCount = ((($response.data.total)/$BatchSize) + 1)
					
					$message = ("{0}: The function will query LogicMonitor {1} times to retrieve all services." -f (Get-Date -Format s), ($serviceBatchCount-1))
					If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

					$firstLoopDone = $True

					$message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
					If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
				}

				$message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, ($serviceBatchCount-1))
				If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			}
		}

        Return $services
	}
} #1.0.0.8
Function Remove-LogicMonitorCollector {
    <#
.DESCRIPTION 
    Accepts a collector ID, then delete the collector from LogicMonitor.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 19 June 2017
        - Initial release.
    V1.0.0.1 date: 7 August 2017
        - Updated in-line documentation.
        - Changed ! to -Not.
        - Updated examples.
        - Removed support for deleting collectors based on IP and hostname.
    V1.0.0.2 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
.LINK
    
.PARAMETER AccessId
    Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Represents the subdomain of the LogicMonitor customer.
.PARAMETER Id
    Mandatory parameter. Represents the device ID of a monitored device.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Remove-LogicMonitorCollector -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 45

    Deletes the collector with Id 45.
#>
    [CmdletBinding(DefaultParameterSetName = ’Default’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True)]
        [int]$CollectorId,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $data = ""
    $httpVerb = 'DELETE'
    $queryParams = $null
    $resourcePath = "/setting/collectors/$CollectorId"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
	
    $message = ("{0}: Updated `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        
    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"
    
    $message = ("{0}: The value of `$url is {1}." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
        Return "Error"
    }
    
    If ($response.status -ne "200") {
        $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

        Return $response
    }
    ElseIf ($response.status -eq "200") {
        $message = ("{0}: LogicMonitor reported that device {1}, was deleted." -f (Get-Date -Format s), $CollectorId)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Return $response
    }
    

    Return "Success"
} #1.0.0.2
Function Remove-LogicMonitorDevice {
    <#
        .DESCRIPTION 
            Accepts a device ID, display name, or device IP/DNS name, then deletes it.
        .NOTES 
            Author: Mike Hashemi
            V1.0.0.0 date: 19 June 2017
                - Initial release.
            V1.0.0.1 date: 7 August 2017
                - Changed ! to -Not.
                - Updated .EXAMPLE.
            V1.0.0.2 date: 28 August 2017
                - Updated NameFilter code.
            V1.0.0.3 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.4 date: 2 July 2018
                - Updated white space.
                - The cmdlet now only returns the API response (after the query is made, we'll still return "Error" if there is a problem eariler in the code).
        .LINK

        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Represents the subdomain of the LogicMonitor customer.
        .PARAMETER Id
            Mandatory parameter. Represents the device ID of a monitored device.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Remove-LogicMonitorDevice -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 45

            Deletes the device with Id 45.
        .EXAMPLE
            PS C:\> Remove-LogicMonitorDevice -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName "10.0.0.1"

            Deletes the device with name 10.0.0.1. If more than one device is returned, the function will exit.
        .EXAMPLE
            PS C:\> Remove-LogicMonitorDevice -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName "server1 - Customer"

            Deletes the device with display name "server1 - Customer".
    #>
    [CmdletBinding(DefaultParameterSetName = ’Default’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’Default’)]
        [int]$DeviceId,

        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$DeviceDisplayName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IPFilter’)]
        [string]$DeviceName,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $data = ""
    $httpVerb = 'DELETE'
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    $message = ("{0}: Updated `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Update $resourcePath to filter for a specific device, when a device ID, name, or displayName is provided by the user.
    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath = "/device/devices/$DeviceId"
        }
        NameFilter {
            $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceDisplayName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceDisplayName $DeviceDisplayName -EventLogSource $EventLogSource
            
            If ($device.id) {
                $DeviceId = $device.id
                $resourcePath = "/device/devices/$DeviceId"
            }
            Else {
                $message = ("{0}: No device was returned when searching for {1}. To prevent errors, {2} will exit." `
                        -f (Get-Date -Format s), $DeviceDisplayName, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }
        IPFilter {
            $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            If ($DeviceId -eq $null) {
                $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceName $DeviceName -EventLogSource $EventLogSource
            }

            If ($device.count -gt 1) {
                $message = ("{0}: More than one device with the name {1} were detected (specifically {2}). To prevent errors, {3} will exit." `
                        -f (Get-Date -Format s), $DeviceName, $device.count, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }
            ElseIf ($device.id) {
                $DeviceId = $device.id
                $resourcePath = "/device/devices/$DeviceId"
            }
            Else {
                $message = ("{0}: No device was returned when searching for {1}. To prevent errors, {2} will exit." `
                        -f (Get-Date -Format s), $DeviceName, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }
    }

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

    $message = ("{0}: The value of `$url is {1}." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers #-Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

        Return $response
    }

    If ($response.status -ne "200") {
        $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

        Return $response
    }
    ElseIf ($response.status -eq "200") {
        $message = ("{0}: LogicMonitor reported that device {1}, was deleted." -f (Get-Date -Format s), $DeviceId)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Return $response
    }

    Return $response
} #1.0.0.4
Function Remove-LogicMonitorDeviceProperties {
    <#
.DESCRIPTION 
    Accepts a device ID, display name, or device IP/DNS name, and one or more property names, then deletes the property(ies).
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 2 February 2017
        - Initial release.
    V1.0.0.1 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.2 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.3 date: 21 June 2017
        - Updated logging to reduce chatter.
        - Added missing parameters to the in-line help.
    V1.0.0.4 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Represents the subdomain of the LogicMonitor customer. Default value is "synoptek".
.PARAMETER DeviceId
    Represents the device ID of a monitored device.
.PARAMETER DeviceDisplayName
    Represents the display name of the device to be monitored. This name must be unique in your LogicMonitor account.
.PARAMETER DeviceName
     Represents the IP address or DNS name of the device to be monitored. This IP/name must be unique on the monitoring collector.
.PARAMETER PropertyNames
    Mandatory parameter. Represents the name of the target property. Note that LogicMonitor properties are case sensitive.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Remove-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 45 -PropertyNames Location

    In this example, the function will remove the Location property for the device with "45" in the ID property.
.EXAMPLE
    PS C:\> Remove-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName "10.0.0.1" -PropertyNames Location

    In this example, the function will remove the Location property for the device with "10.0.0.1" in the name property.
.EXAMPLE
    PS C:\> Remove-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName "server1 - Customer" -PropertyNames Location,AssignedTeam

    In this example, the function will remove the Location and AssignedTeam properties for the device with "server1 - Customer" in the display name property.
.EXAMPLE
#>
    [CmdletBinding(DefaultParameterSetName = ’Default’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’Default’)]
        [int]$DeviceId,

        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$DeviceDisplayName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IPFilter’)]
        [string]$DeviceName,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyNames,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $data = ""
    $httpVerb = 'DELETE'
    $queryParams = ""
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
	
    $message = ("{0}: Updated `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # For each property, append the name to the $resourcePath.
    Foreach ($property in $PropertyNames) {
        # Update $resourcePath to filter for a specific device, when a device ID, name, or displayName is provided by the user.
        Switch ($PsCmdlet.ParameterSetName) {
            Default {
                $resourcePath = "/device/devices/$DeviceId/properties"
            }
            NameFilter {
                $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceDisplayName)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($DeviceId -eq $null) {
                    $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceDisplayName $DeviceDisplayName
                }
            
                If ($device.id) {
                    $DeviceId = $device.id
                    $resourcePath = "/device/devices/$DeviceId/properties"
                }
                Else {
                    $message = ("{0}: No device was returned when searching for {1}. To prevent errors, {2} will exit." `
                            -f (Get-Date -Format s), $DeviceDisplayName, $MyInvocation.MyCommand)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"    
                }

                $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            IPFilter {
                $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceName)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
			
                If ($DeviceId -eq $null) {
                    $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceName $DeviceName
                }

                If ($device.count -gt 1) {
                    $message = ("{0}: More than one device with the name {1} were detected (specifically {2}). To prevent errors, {3} will exit." `
                            -f (Get-Date -Format s), $DeviceName, $device.count, $MyInvocation.MyCommand)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
                ElseIf ($device.id) {
                    $DeviceId = $device.id
                    $resourcePath = "/device/devices/$DeviceId/properties"
                }
                Else {
                    $message = ("{0}: No device was returned when searching for {1}. To prevent errors, {2} will exit." `
                            -f (Get-Date -Format s), $DeviceName, $MyInvocation.MyCommand)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"    
                }

                $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }
    
        $resourcePath += "/$property"

        $message = ("{0}: Updated `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"
    
        $message = ("{0}: The value of `$url is {1}." -f (Get-Date -Format s), $url)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # Get current time in milliseconds
        $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
        # Concatenate Request Details
        $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                    -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
            Return "Error"
        }
    
        If ($response.status -ne "200") {
            $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return $response
        }
    }

    Return "Success"
} #1.0.0.4
Function Start-LogicMonitorDeviceSdt {
    <#
        .DESCRIPTION 
            Starts standard down time (SDT) for a device in LogicMonitor.
        .NOTES 
            Author: Mike Hashemi
            V1.0.0.0 date: 9 July 2018
                - Initial release.
            V1.0.0.1 date: 11 July 2018
                - Updated code to handle times better.
            V1.0.0.2 date: 12 July 2018
                - Changed the variable cast of $StartTime from [datetime] to [string].
                - Changed references to "LogicMonitorCommentSdt", to "LogicMonitorDeviceSdt".
        .LINK

        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER Id
            Represents the device ID of a monitored device. Accepts pipeline input. Either this or the DisplayName is required.
        .PARAMETER DisplayName
            Represents the device display name of a monitored device. Accepts pipeline input. Must be unique in LogicMonitor. Either this or the Id is required.
        .PARAMETER StartDate
            Represents the SDT start date. If no value is provided, the current date is used.
        .PARAMETER StartTime
            Represents the SDT start time. If no value is provided, the current time is used.
        .PARAMETER Duration
            Represents the duration of SDT in the format days, hours, minutes (xxx:xx:xx). If no value is provided, the duration will be one hour.
        .PARAMETER Comment
            Represents the text that will show in the notes field of the SDT entry. The text "...SDT initiated via Start-LogicMonitorDeviceSdt." will be appended to the user's comment.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule". Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Start-LogicMonitorDeviceSdt -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -Id 1

            In this example, SDT will be started for the device with Id "1". The SDT will start immediately and will last one hour.
        .EXAMPLE
            PS C:\> Start-LogicMonitorDeviceSdt -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -Id 1 -StartDate 06/07/2050 -Duration 00:02:00 -Comment "Testing" 

            In this example, SDT will be started for the device with Id "1". The SDT will start on 7 June 2050 (at the time the command was run). The duraction will be two hours and the comment will be "Testing......SDT initiated via Start-LogicMonitorDeviceSdt.".
        .EXAMPLE
            PS C:\> Get-LogicMonitorDevices -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -DeviceId 1 | Start-LogicMonitorDeviceSdt -AccessId $accessID -AccessKey $accessKey -AccountName <account name> -StartDate 06/07/2050 -Duration 00:02:00 -Comment "Testing" 

            In this example, SDT will be started for the device with Id "1". The SDT will start on 7 June 2050 (at the time the command was run). The duraction will be two hours and the comment will be "Testing......SDT initiated via Start-LogicMonitorDeviceSdt.".
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Id", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = "Name", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$DisplayName,

        [datetime]$StartDate,

        [ValidateScript( {$_ -match '^([01]\d|2[0-3]):?([0-5]\d)$'})]
        [string]$StartTime,

        [ValidateScript( {$_ -match '^\d{1,3}:([01]?[0-9]|2[0-3]):([0-5][0-9])$'})]
        [string]$Duration = "00:01:00",

        [string]$Comment,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    Begin {
        #Request Info
        $httpVerb = 'POST'
        $resourcePath = "/sdt/sdts"
        $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
        $comment += "...SDT initiated via Start-LogicMonitorDeviceSdt"
    }
    Process {
        If (-NOT($BlockLogging)) {
            $return = Add-EventLogSource -EventLogSource $EventLogSource

            If ($return -ne "Success") {
                $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
                Write-Host $message -ForegroundColor Yellow;

                $BlockLogging = $True
            }
        }

        $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $message = ("{0}: Validating start time/date." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        If (-NOT($StartDate) -and -NOT($StartTime)) {
            # Neither start time nor end time provided.

            $message = ("{0}: StartDate and StartTime are null." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $StartDate = (Get-Date).AddMinutes(1)
        }
        ElseIf (-NOT($StartDate) -and ($StartTime)) {
            # Start date not provided. Start time is provided.
            $message = ("{0}: StartDate is null and StartTime is {1}." -f (Get-Date -Format s), $StartTime)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $StartDate = Get-Date
            $StartDate = $StartDate.Date.Add((New-Timespan -Hour $StartTime.Split(':')[0] -Minute $StartTime.Split(':')[0]))
        }
        ElseIf (($StartDate) -and -NOT($StartTime)) {
            # Start date is provided. Start time is not provided.
            $message = ("{0}: StartDate is {1} and StartTime is null. The object type of StartDate is {2}" -f (Get-Date -Format s), $StartDate, $StartDate.GetType())
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $currentTime = (Get-Date).AddMinutes(1)
            $StartDate = $StartDate.Date.Add((New-Timespan -Hour $currentTime.Hour -Minute $currentTime.Minute))
        }
        Else {
            # Start date is provided. Start time is provided.
            $message = ("{0}: StartDate is {1} and StartTime is {2}." -f (Get-Date -Format s), $StartDate, $StartTime)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $StartDate = $StartDate.Date.Add([Timespan]::Parse($StartTime))
        }

        # Split the duration into days, hours, and minutes.
        [array]$duration = $duration.Split(":")

        $message = ("{0}: Configuring duration." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # Use the start date/time + duration to determine when the end date/time.
        $endDate = $StartDate.AddDays($duration[0])
        $endDate = $endDate.AddHours($duration[1])
        $endDate = $endDate.AddMinutes($duration[2])

        $message = ("{0}: The value of `$endDate is: {1}." -f (Get-Date -Format s), $endDate)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        $sdtStart = [Math]::Round((New-TimeSpan -Start (Get-Date -Date "1/1/1970") -End ($StartDate).ToUniversalTime()).TotalMilliseconds)
        $sdtEnd = [Math]::Round((New-TimeSpan -Start (Get-Date -Date "1/1/1970") -End ($endDate).ToUniversalTime()).TotalMilliseconds)

        If ($PsCmdlet.ParameterSetName -eq "id") {
            $message = ("{0}: SDT Start: {1}; SDT End: {2}; Device ID: {3}; Commnet: {4}." -f (Get-Date -Format s), $StartDate, $endDate, $Id, $Comment)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $data = "{`"sdtType`":1,`"type`":`"DeviceSDT`",`"deviceId`":`"$Id`",`"startDateTime`":$sdtStart,`"endDateTime`":$sdtEnd,`"comment`":`"$Comment`"}"
        }
        Else {
            $message = ("{0}: SDT Start: {1}; SDT End: {2}; Device name: {3}; Commnet: {4}." -f (Get-Date -Format s), $StartDate, $endDate, $DisplayName, $Comment)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            $data = "{`"sdtType`":1,`"type`":`"DeviceSDT`",`"deviceDisplayName`":`"$DisplayName`",`"startDateTime`":$sdtStart,`"endDateTime`":$sdtEnd,`"comment`":`"$Comment`"}"
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

        # Get current time in milliseconds
        $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

        # Concatenate Request Details
        $requestVars = $httpVerb + $epoch + $data + $resourcePath

        # Construct Signature
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
        $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
        $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
        $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

        # Construct Headers
        $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", $auth)
        $headers.Add("Content-Type", 'application/json')

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop

            If (($response.status -eq '200') -and ($response.errmsg -eq 'OK')) {
                Return $response.status
            }
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}. The response was: {3}" `
                    -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception, $response.data)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return $response.status
        }
    }
} #1.0.0.2
# Need to figure out, in what format(s) I can have the user provide start and end dates. Using '06/07/2017' (for example) works, but throws an error.
# The ElseIf for "Start date is provided. Start time is not provided." complains, but I'm not sure why. The lines work when called outside the function.
Function Start-LogicMonitorSDT {
    <#
.DESCRIPTION 
    Starts standard down time (SDT) for a device in LogicMonitor.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 19 December 2016
        - Initial release
    V1.0.0.1 date: 3 May 2016
        - Updated logging code.
        - Added to the SynoptekLogicMonitor module.
        - Added usage examples.
    V1.0.0.2 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER Id
    Represents the device ID of a monitored device. Accepts pipeline input. Either this or the DisplayName is required.
.PARAMETER DisplayName
    Represents the device display name of a monitored device. Accepts pipeline input. Must be unique in LogicMonitor. Either this or the Id is required.
.PARAMETER StartDate
    Represents the SDT start date. If no value is provided, the current date is used.
.PARAMETER StartTime
    Represents the SDT start time. If no value is provided, the current time is used.
.PARAMETER Duration
    Represents the duration of SDT in the format days, hours, minutes (xxx:xx:xx). If no value is provided, the duration will be one hour.
.PARAMETER Comment
    Default value is "SDT initiated by Start-LogicMonitorSDT". 
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Start-LogicMonitorSDT -AccessId $accessID -AccessKey $accessKey -AccountName $accountname -Id 1

    In this example, SDT will be started for the device with Id "1". The SDT will start immediately and will last one hour.
.EXAMPLE 
    PS C:\> 
.EXAMPLE 

.EXAMPLE 

.EXAMPLE 
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Id", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = "Name", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$DisplayName,

        [datetime]$StartDate,

        [datetime]$StartTime,

        [string]$Duration = "00:01:00",

        [string]$Comment = "SDT initiated by Start-LogicMonitorSDT",

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    Begin {
        #Request Info
        $httpVerb = 'POST'
        $resourcePath = "/sdt/sdts"
        $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

        # Regular expression to validate that the provided SDT duration was formatted correctly.
        $regex = '^\d{1,3}:([01]?[0-9]|2[0-3]):([0-5][0-9])$'
    }
    Process {
        If (-NOT($BlockLogging)) {
            $return = Add-EventLogSource -EventLogSource $EventLogSource
    
            If ($return -ne "Success") {
                $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
                Write-Host $message -ForegroundColor Yellow;

                $BlockLogging = $True
            }
        }

        $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        While ($Duration -notmatch $regex) {
            Write-Output ("The value for duration ({0}) is invalid. Please provide a valid SDT duration." -f $Duration)
            $Duration = Read-Host "Please enter the end duration of SDT (days:hours:minutes (999:23:59))"
        }

        $message = ("{0}: Validating start time/date." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        If (($StartDate -eq $null) -and ($StartTime -eq $null)) {
            # Neither start time nor end time provided.
            $StartDate = (Get-Date).AddMinutes(1)
        }
        ElseIf (($StartDate -eq $null) -and ($StartTime -ne $null)) {
            # Start date not provided. Start time is provided.
            $StartDate = (Get-Date -Format d)
            [datetime]$StartDate = $StartDate
            $StartDate = $StartDate.Add($StartTime)
        }
        ElseIf (($StartDate -ne $null) -and ($StartTime -eq $null)) {
            # Start date is provided. Start time is not provided.
            $StartTime = (Get-Date -Format HH:mm)
            [datetime]$StartDate = $StartDate
            $StartDate = $StartDate.Add($StartTime)
        }
        Else {
            $StartDate = $StartDate.Add($StartTime)
        }

        # Split the duration into days, hours, and minutes.
        [array]$duration = $duration.Split(":")

        $message = ("{0}: Configuring duration." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        # Use the start date/time + duration to determine when the end date/time.
        $endDate = $StartDate.AddDays($duration[0])
        $endDate = $endDate.AddHours($duration[1])
        $endDate = $endDate.AddMinutes($duration[2])
    
        $sdtStart = [Math]::Round((New-TimeSpan -Start (Get-Date -Date "1/1/1970") -End ($StartDate).ToUniversalTime()).TotalMilliseconds)
        $sdtEnd = [Math]::Round((New-TimeSpan -Start (Get-Date -Date "1/1/1970") -End ($endDate).ToUniversalTime()).TotalMilliseconds)
		
        While (($Id -eq $null) -and ($DisplayName -eq $null)) {
            $input = Read-Host = "Enter the target device's ID or display name"

            # If the input is only digits, assign to $id, otherwise, assign to $displayName.
            If ($input -match "^[\d\.]+$") {$id = $input} Else {$displayName = $input}
        }

        $message = ("{0}: SDT Start: {1}; SDT End: {2}; Device ID: {3}; Device Display Name: {4}." -f (Get-Date -Format s), $StartDate, $endDate, $Id, $DisplayName)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        If ($id) {
            $data = "{`"sdtType`":1,`"type`":`"DeviceSDT`",`"deviceId`":`"$Id`",`"startDateTime`":$sdtStart,`"endDateTime`":$sdtEnd}"
        }
        Else {
            $data = "{`"sdtType`":1,`"type`":`"DeviceSDT`",`"deviceDisplayName`":`"$DisplayName`",`"startDateTime`":$sdtStart,`"endDateTime`":$sdtEnd,`"comment`":`"$Comment`"}"
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

        # Get current time in milliseconds
        $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
        # Concatenate Request Details
        $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
        # Construct Signature
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
        $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
        $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
        $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

        # Construct Headers
        $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", $auth)
        $headers.Add("Content-Type", 'application/json')
        
        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                    -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
    }
} #1.0.0.2
Function Update-LogicMonitorAlertRulesProperties {
    <#
        .DESCRIPTION
            Accepts an alert rule ID or name and one or more property name/value pairs, then updates the property(ies).
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 8 August 2018
                - Initial release.
            V1.0.0.1 date: 13 August 2018
                - Changed $queryParams to $null.
                - Added support for pipeline input of the Id.
        .LINK

        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Represents the subdomain of the LogicMonitor customer.
        .PARAMETER AlertRuleId
            Represents the collector's ID. Accepts pipeline input by property name.
        .PARAMETER AlertRuleName
            Represents the collectors description.
        .PARAMETER PropertyName
            Represents the name of the target property. Note that LogicMonitor properties are case sensitive.
        .PARAMETER PropertyValue
            Represents the value of the target property.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Update-LogicMonitorAlertRulesProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -Id 6 -PropertyNames hostname,collectorSize -PropertyValues server2,small

            In this example, the cmdlet will update the hostname and collectorSize properties for the collector with "6" in the ID property. The hostname will be set to "server2" and the collector size will be set to "Small". If the properties are not present, they will be added.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, ParameterSetName = 'Default')]
        [int]$AlertRuleId,

        [Parameter(Mandatory = $True, ParameterSetName = 'NameFilter')]
        [string]$AlertRuleName,

        [Parameter(Mandatory = $True)]
        [ValidateSet('name', 'priority', 'levelStr', 'devices', 'deviceGroups', 'datasource', 'instance', 'datapoint', 'escalationInterval', 'escalatingChainId', 'suppressAlertClear', 'suppressAlertAckSdt')]
        [string[]]$PropertyNames,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyValues,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    Begin {
        If (-NOT($BlockLogging)) {
            $return = Add-EventLogSource -EventLogSource $EventLogSource

            If ($return -ne "Success") {
                $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
                Write-Host $message -ForegroundColor Yellow;

                $BlockLogging = $True
            }
        }

        $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        # Initialize variables.
        [int]$index = 0
        [hashtable]$propertyData = @{}
        [string]$data = ""
        [string]$httpVerb = 'PUT'
        [string]$queryParams = ""
        [string]$resourcePath = "/setting/alert/rules"
        [System.Net.SecurityProtocolType]$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    }
    Process {
        If ($PropertyNames -notcontains "name" -or $PropertyNames -notcontains "priority") {
            $message = ("{0}: The alert rule name and priority are required, but one or both were not provided. Please try again." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
        Else {
            # Update $resourcePath to filter for a specific alert rule, when an alert rule ID, or name are provided by the user.
            Switch ($PsCmdlet.ParameterSetName) {
                Default {
                    $resourcePath += "/$AlertRuleId"
                }
                "NameFilter" {
                    $message = ("{0}: Attempting to retrieve the collector ID of {1}." -f (Get-Date -Format s), $AlertRuleName)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                    $alertRule = Get-LogicMonitorAlertRules -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -AlertRuleName $AlertRuleName -EventLogSource $EventLogSource

                    $resourcePath += "/$($alertRule.id)"

                    $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }
            }

            $message = ("{0}: Finished updating `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            Foreach ($property in $PropertyNames) {
                Switch ($property) {
                    {$_ -in ("deviceGroups", "devices")} {
                        $propertyData.Add($_, @($PropertyValues[$index] -split ','))

                        $index++
                    }
                    default {
                        $propertyData.Add($_, $($PropertyValues[$index]))

                        $index++
                    }
                }
            }

            # I am assigning $propertyData to $data, so that I can use the same $requestVars concatination and Invoke-RestMethod as other cmdlets in the module.
            $data = $propertyData | ConvertTo-Json -Depth 6

            $message = ("{0}: Finished updating `$data. The value update is {1}." -f (Get-Date -Format s), $data)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            # Construct the query URL.
            $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

            # Get current time in milliseconds
            $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

            # Concatenate Request Details
            $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

            # Make Request
            $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
            }
            Catch {
                $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                        -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error", $response
            }

            If ($response.status -ne "200") {
                $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
            }

            Return $response
        }
    }
} #1.0.0.0
Function Update-LogicMonitorCollectorProperties {
    <#
        .DESCRIPTION
            Accepts a collector ID or description and one or more property name/value pairs, then updates the property(ies).
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 11 July 2018
                - Initial release.
            V1.0.0.1 date: 19 July 2018
                - Added support for both PUT and PATCH operations.
                - Updated how the $propertyData is built, based on input from Joe Tran (https://github.com/jtran1209/).
            V1.0.0.2 date: 19 July 2018
                - Removed mandatory flag from OpType.
        .LINK

        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Represents the subdomain of the LogicMonitor customer.
        .PARAMETER CollectorId
            Represents the collector's ID.
        .PARAMETER CollectorDisplayName
            Represents the collectors description.
        .PARAMETER PropertyName
            Represents the name of the target property. Note that LogicMonitor properties are case sensitive.
        .PARAMETER PropertyValue
            Represents the value of the target property.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER OpType
            Default value is "PATCH". Defines whether the command should use PUT or PATCH. PUT updates the provided properties and returns the rest to default values while PATCH updates the provided properties without chaning the others.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Update-LogicMonitorCollectorProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -CollectorId 6 -PropertyNames hostname,collectorSize -PropertyValues server2,small

            In this example, the cmdlet will update the hostname and collectorSize properties for the collector with "6" in the ID property. The hostname will be set to "server2" and the collector size will be set to "Small". If the properties are not present, they will be added.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = 'Default')]
        [int]$CollectorId,

        [Parameter(Mandatory = $True, ParameterSetName = 'NameFilter')]
        [string]$CollectorDisplayName,

        [Parameter(Mandatory = $True)]
        [ValidateSet('description', 'backupAgentId', 'enableFailBack', 'resendIval', 'suppressAlertClear', 'escalatingChainId', 'collectorGroupId', 'collectorGroupName', 'enableFailOverOnCollectorDevice', 'build')]
        [string[]]$PropertyNames,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyValues,

        [ValidateSet('PUT', 'PATCH')]
        [string]$OpType = 'PATCH',

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    [hashtable]$propertyData = @{}
    [string]$standardProperties = ""
    [string]$data = ""
    [string]$httpVerb = $OpType.ToUpper()
    [string]$queryParams = "?patchFields="
    [string]$resourcePath = "/setting/collectors"
    [System.Net.SecurityProtocolType]$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    # Update $resourcePath to filter for a specific device, when a device ID, name, or displayName is provided by the user.
    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath += "/$CollectorId"
        }
        NameFilter {
            $message = ("{0}: Attempting to retrieve the collector ID of {1}." -f (Get-Date -Format s), $CollectorDisplayName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            $collector = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -CollectorDisplayName $CollectorDisplayName -EventLogSource $EventLogSource

            $resourcePath += "/$($collector.id)"

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
        }
    }

    $message = ("{0}: Finished updating `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    Foreach ($property in $PropertyNames) {
        If ($OpType -eq 'PATCH') {
            $queryParams += "$property,"

            $message = ("{0}: Added {1} to `$queryParams. The new value of `$queryParams is: {2}" -f (Get-Date -Format s), $property, $queryParams)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
        }

        $propertyData.add($property, $PropertyValues[$index])

        $index++
    }

    If ($OpType -eq 'PATCH') {
        $queryParams = $queryParams.TrimEnd(",")
        $queryParams += "&opType=replace"
    }

    # I am assigning $propertyData to $data, so that I can use the same $requestVars concatination and Invoke-RestMethod as other cmdlets in the module.
    $data = $propertyData | ConvertTo-Json -Depth 6

    $message = ("{0}: Finished updating `$data. The value update is {1}." -f (Get-Date -Format s), $data)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

        Return "Error", $response
    }

    If ($response.status -ne "200") {
        $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
    }

    Return $response
} #1.0.0.2
Function Update-LogicMonitorCollectorVersion {
    <#
        .DESCRIPTION
            Accepts a collector ID or description, a version number, and a start time, then schedules the installation of a new version of the collector.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 30 August 2018
                - Initial release.
        .LINK

        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Represents the subdomain of the LogicMonitor customer.
        .PARAMETER CollectorId
            Represents the collector's ID.
        .PARAMETER DisplayName
            Represents the collectors description.
        .PARAMETER MajorVersion
            
        .PARAMETER MinorVersion
            
        .PARAMETER StartDate

        .PARAMETER StartTime

        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Update-LogicMonitorCollectorVersion -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -CollectorId 6 -MajorVersion 27 -MinorVersion 2

            In this example, the cmdlet will upgrade the collector to 27.002. The installation will run immediately.
        .EXAMPLE
            PS C:\> Update-LogicMonitorCollectorVersion -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -CollectorId 6 -MajorVersion 27 -MinorVersion 2 -StartDate 08/30/2018 -StartTime 12:00

            In this example, the cmdlet will upgrade the collector to 27.002. The installation will run at 12:00 on 30 August 2018.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Default", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [int]$Id,

        [Parameter(Mandatory = $True, ParameterSetName = "Name", ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [string]$DisplayName,

        [int]$MajorVersion,

        [int]$MinorVersion,

        [datetime]$StartDate,

        [datetime]$StartTime,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    Begin {
        # Initialize variables.
        [hashtable]$upgradeProperties = @{}
        [hashtable]$propertyData = @{}
        [string]$data = ""
        [string]$httpVerb = "PATCH"
        [string]$queryParams = ""
        [string]$resourcePath = "/setting/collectors"
        [System.Net.SecurityProtocolType]$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
        [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    }
    Process {
        If (-NOT($BlockLogging)) {
            $return = Add-EventLogSource -EventLogSource $EventLogSource

            If ($return -ne "Success") {
                $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
                Write-Host $message -ForegroundColor Yellow;

                $BlockLogging = $True
            }
        }

        $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        $message = ("{0}: Validating start time/date." -f (Get-Date -Format s))
        If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        If (($StartDate -eq $null) -and ($StartTime -eq $null)) {
            # Neither start time nor end time provided.
            $StartDate = (Get-Date).AddMinutes(1)
        }
        ElseIf (($StartDate -eq $null) -and ($StartTime -ne $null)) {
            # Start date not provided. Start time is provided.
            $StartDate = (Get-Date -Format d)
            [datetime]$StartDate = $StartDate
            $StartDate = $StartDate.Add($StartTime)
        }
        ElseIf (($StartDate -ne $null) -and ($StartTime -eq $null)) {
            # Start date is provided. Start time is not provided.
            $StartTime = (Get-Date -Format HH:mm)
            [datetime]$StartDate = $StartDate
            $StartDate = $StartDate.Add($StartTime)
        }
        Else {
            $StartDate = $StartDate.Add($StartTime)
        }

        $startEpoch = [Math]::Round((New-TimeSpan -Start (Get-Date -Date "1/1/1970") -End ($StartDate).ToUniversalTime()).TotalMilliseconds)

        # Update $resourcePath to filter for a specific collector, when a collector ID or displayName is provided by the user.
        Switch ($PsCmdlet.ParameterSetName) {
            Default {
                $resourcePath += "/$Id"
            }
            NameFilter {
                $message = ("{0}: Attempting to retrieve the collector ID of {1}." -f (Get-Date -Format s), $DisplayName)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $collector = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceDisplayName $DisplayName -EventLogSource $EventLogSource

                $resourcePath += "/$($collector.id)"

                $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        $message = ("{0}: Finished updating `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        # Sleeping because we get an error about scheduling, if we don't wait.
        Start-Sleep -Seconds 5

        $propertyData = @{
            "majorVersion" = $MajorVersion
            "minorVersion" = $MinorVersion
            "startEpoch"   = $startEpoch
            "description"  = "Collector upgrade initiated by LogicMonitor PowerShell module."
        }

        $propertyData.Add("onetimeUpgradeInfo", $upgradeProperties)

        # I am assigning $propertyData to $data, so that I can use the same $requestVars concatination and Invoke-RestMethod as other cmdlets in the module.
        $data = $propertyData | ConvertTo-Json -Depth 6

        $message = ("{0}: Finished updating `$data. The value update is {1}." -f (Get-Date -Format s), $data)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        # Get current time in milliseconds
        $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

        # Concatenate Request Details
        $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                    -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error", $response
        }

        If ($response.status -ne "200") {
            $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
        }

        Return $response
    }
} #1.0.0.0
Function Update-LogicMonitorDeviceProperties {
    <#
        .DESCRIPTION
            Accepts a device ID, display name, or device IP/DNS name, and one or more property name/value pairs, then updates the property(ies).
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 12 December 2016
            V1.0.0.1 date: 31 January 2017
                - Updated syntax and logging.
                - Improved error handling.
            V1.0.0.2 date: 31 January 2017
                - Updated error output color.
                - Streamlined header creation (slightly).
            V1.0.0.3 date: 31 January 2017
                - Added $logPath output to host.
            V1.0.0.4 date: 31 January 2017
                - Added additional logging.
            V1.0.0.5 date: 10 February 2017
                - Updated procedure order.
            V1.0.0.6 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.7 date: 21 June 2017
                - Updated logging to reduce chatter.
            V1.0.0.8 date: 12 July 2017
                - Added -EventLogSource to a couple of cmdlet calls.
            V1.0.0.9 date: 1 August 2017
                - Updated inline documentation.
            V1.0.0.10 date: 28 September 2017
                - Replaced ! with -Not.
            V1.0.0.11 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.12 date: 11 July 2018
                - Updated white space.
                - Updated in-line help.
            V1.0.0.13 date: 18 July 2018
                - More whites space updates.
                - Added the API's response to the return data when there is an Invoke-RestMethod failure.
        .LINK

        .PARAMETER AccessId
            Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Represents the subdomain of the LogicMonitor customer.
        .PARAMETER DeviceId
            Represents the device ID of a monitored device.
        .PARAMETER DeviceDisplayName
            Represents the device's display name.
        .PARAMETER PropertyName
            Represents the name of the target property. Note that LogicMonitor properties are case sensitive.
        .PARAMETER PropertyValue
            Represents the value of the target property.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Update-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceId 6 -PropertyNames Location,AssignedTeam -PropertyValues Denver,Finance

            In this example, the function will update the Location and AssignedTeam properties for the device with "6" in the ID property. The location will be set to "Denver" and the assigned team will be "Finance". If the properties are not present, they will be added.
        .EXAMPLE
            PS C:\> Update-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName server1 -PropertyNames Location -PropertyValues Denver

            In this example, the function will update the Location property for the device with "server1" in the displayName property. The location will be set to "Denver". If the property is not present, it will be added.
        .EXAMPLE
            PS C:\> Update-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName 10.0.0.0 -PropertyNames Location -PropertyValues Denver

            In this example, the function will update the Location property for the device with "10.0.0.0" in the name property. The location will be set to "Denver". If the property is not present, it will be added.
        .EXAMPLE
            PS C:\> Update-LogicMonitorDeviceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName server1.domain.local -PropertyNames Location -PropertyValues Denver

            In this example, the function will update the Location property for the device with "server1.domain.local" in the name property. The location will be set to "Denver". If the property is not present, it will be added.
    #>
    [CmdletBinding(DefaultParameterSetName = ’Default’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’Default’)]
        [int]$DeviceId,

        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$DeviceDisplayName,

        [Parameter(Mandatory = $True, ParameterSetName = ’IPFilter’)]
        [string]$DeviceName,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyNames,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyValues,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    [int]$index = 0
    $propertyData = ""
    $standardProperties = ""
    $data = ""
    $httpVerb = 'PATCH'
    $queryParams = "?patchFields="
    $resourcePath = "/device/devices"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    # Update $resourcePath to filter for a specific device, when a device ID, name, or displayName is provided by the user.
    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath += "/$DeviceId"
        }
        NameFilter {
            $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceDisplayName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceDisplayName $DeviceDisplayName -EventLogSource $EventLogSource

            $resourcePath += "/$($device.id)"

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
        }
        IPFilter {
            $message = ("{0}: Attempting to retrieve the device ID of {1}." -f (Get-Date -Format s), $DeviceName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

            $device = Get-LogicMonitorDevices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -DeviceName $DeviceName -EventLogSource $EventLogSource

            If ($device.count -gt 1) {
                $message = ("{0}: More than one device with the name {1} were detected (specifically {2}). To prevent errors, {3} will exit." `
                        -f (Get-Date -Format s), $DeviceName, $device.count, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            $resourcePath += "/$($device.id)"

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
        }
    }

    $message = ("{0}: Finished updating `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # For each property, assign the name and value to $propertyData.
    Foreach ($property in $PropertyNames) {
        Switch ($property) {
            {$_ -in ("name", "displayName", "preferredCollectorId", "hostGroupIds", "description", "disableAlerting", "link", "enableNetflow", "netflowCollectorId")} {
                $queryParams += "$property,"

                $message = ("{0}: Added {1} to `$queryParams. The new value of `$queryParams is: {2}" -f (Get-Date -Format s), $property, $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $message = ("{0}: Updating/adding standard property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $standardProperties += "`"$property`":`"$($PropertyValues[$index])`","

                $index++
            }
            Default {
                $customProps = $True

                $message = ("{0}: Found that there is a custom property present." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($property -like "*pass") {
                    $message = ("{0}: Updating/adding property: {1} with a value of ********." -f (Get-Date -Format s), $property)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }
                Else {
                    $message = ("{0}: Updating/adding property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $propertyData += "{`"name`":`"$property`",`"value`":`"$($PropertyValues[$index])`"},"

                $index++
            }
        }
    }

    If ($customProps -eq $True) {
        $queryParams += "customProperties&opType=replace"
    }
    Else {
        $queryParams = $queryParams.TrimEnd(",")
        $queryParams += "&opType=replace"
    }

    # Trim the trailing comma.
    $propertyData = $propertyData.TrimEnd(",")

    $standardProperties = $standardProperties.TrimEnd(",")

    If (($standardProperties.Length -gt 0) -and ($propertyData.Length -gt 0)) {
        $message = ("{0}: The length of `$standardProperties is {1}." -f (Get-Date -Format s), $standardProperties.Length)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

        # Assign the entire string to the $data variable.
        $data = "{$standardProperties,`"customProperties`":[$propertyData]}"
    }
    ElseIf (($standardProperties.Length -gt 0) -and ($propertyData.Length -le 0)) {
        $data = "{$standardProperties}"
    }
    Else {
        # Assign the entire string to the $data variable.
        $data = "{`"customProperties`":[$propertyData]}"
    }

    $message = ("{0}: Finished updating `$data. The value update is {1}." -f (Get-Date -Format s), $data)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath

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

    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}

        Return "Error", $response
    }

    If ($response.status -ne "200") {
        $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
    }

    Return $response
} #1.0.0.13
##Needs some testing (like updating multiple properties)
##Then addition to the lm module and published to the ps gallery.
##Do I want to support the PUT method to update additoinal properties (those not covered by PATCH)?
##Need to update in-line documentation.
Function Update-LogicMonitorServiceProperties {
    <#
.DESCRIPTION 
    Accepts a service ID or name and one or more property name/value pairs, then updates the property(ies), replacing existing values if the property is already defined.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 23 February 2017
        - Initial release.
    V1.0.0.1 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
.LINK
    
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Represents the subdomain of the LogicMonitor customer.
.PARAMETER Id
    Mandatory parameter. Represents the service ID of a monitored service.
.PARAMETER PropertyName
    Mandatory parameter. Represents the name of the target property. Note that LogicMonitor properties are case sensitive.
.PARAMETER PropertyValue
    Mandatory parameter. Represents the value of the target property.
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Update-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -ServiceId 6 -PropertyNames ### -PropertyValues ###

    In this example, the function will update the
.EXAMPLE
    PS C:\> Update-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceDisplayName server1 -PropertyNames Location -PropertyValues Denver

    
.EXAMPLE
    PS C:\> Update-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName 10.0.0.0 -PropertyNames Location -PropertyValues Denver

    
.EXAMPLE
    PS C:\> Update-LogicMonitorServiceProperties -AccessId <accessId> -AccessKey <accessKey> -AccountName <accountName> -DeviceName server1.domain.local -PropertyNames Location -PropertyValues Denver

    
#>
    [CmdletBinding(DefaultParameterSetName = ’Default’)]
    Param (
        [Parameter(Mandatory = $True)]
        [string]$AccessId,

        [Parameter(Mandatory = $True)]
        [string]$AccessKey,

        [Parameter(Mandatory = $True)]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = ’Default’)]
        [int]$ServiceId,
		
        [Parameter(Mandatory = $True, ParameterSetName = ’NameFilter’)]
        [string]$ServiceName,
        
        [Parameter(Mandatory = $True)]
        [string[]]$PropertyNames,

        [Parameter(Mandatory = $True)]
        [string[]]$PropertyValues,

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
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    Set-Variable -Name index -Value 0 -Force -Scope Local
    $propertyData = ""
    $standardProperties = ""
    $data = ""
    $httpVerb = 'PATCH'
    $queryParams = "?patchFields="
    $resourcePath = "/service/services"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    
    # Update $resourcePath to filter for a specific service, when a service ID or service name is provided by the user.
    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath += "/$ServiceId"
        }
        NameFilter {
            $message = ("{0}: Attempting to retrieve the service ID of {1}." -f (Get-Date -Format s), $DeviceDisplayName)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
			
            $service = Get-LogicMonitorServices -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -ServiceName $DeviceDisplayName -EventLogSource $EventLogSource
            
            $resourcePath += "/$($service.id)"

            $message = ("{0}: The value of `$resourcePath is {1}." -f (Get-Date -Format s), $resourcePath)
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
        }
    }
	
    $message = ("{0}: Finished updating `$resourcePath. The value is {1}." -f (Get-Date -Format s), $resourcePath)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # For each property, assign the name and value to $propertyData.
    Foreach ($property in $PropertyNames) {    
        Switch ($property) {
            {$_ -in ("name", "description", "serviceFolderId", "stopMonitoring", "disableAlerting", "individualSmAlertEnable", "individualAlertLevel", `
                        "overallAlertLevel", "pollingInterval", "transition", "globalSmAlertCond", "testLocation", "serviceProperties")} {
				
                $queryParams += "$property,"
	
                $message = ("{0}: Added {1} to `$queryParams. The new value of `$queryParams is: {2}" -f (Get-Date -Format s), $property, $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

                $message = ("{0}: Updating/adding standard property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
	
                $standardProperties += "`"$property`":`"$($PropertyValues[$index])`","
	    
                $index++
            }
            Default {
                $customProps = $True
	
                $message = ("{0}: Found that there is a custom property present." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
	
                If ($property -like "*pass") {
                    $message = ("{0}: Updating/adding property: {1} with a value of ********." -f (Get-Date -Format s), $property)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }
                Else {
                    $message = ("{0}: Updating/adding property: {1} with a value of {2}." -f (Get-Date -Format s), $property, $($PropertyValues[$index]))
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
                }
	
                $propertyData += "{`"name`":`"$property`",`"value`":`"$($PropertyValues[$index])`"},"
	
                $index++
            }
        }
    }
	
    If ($customProps -eq $True) {
        $queryParams += "customProperties&opType=replace"
    }
    Else {
        $queryParams = "$($queryParams.TrimEnd(","))&opType=replace"
    }
	
    # Trim the trailing comma.
    $propertyData = $propertyData.TrimEnd(",")
	
    $standardProperties = $standardProperties.TrimEnd(",")
	
    If (($standardProperties.Length -gt 0) -and ($propertyData.Length -le 0)) {
        $data = "{$standardProperties}"
    }
    Else {
        ##will this section ever be hit? I don't think so, but need to confirm.
        # Assign the entire string to the $data variable.
        $data = "{`"customProperties`":[$propertyData]}"
    }
	
    $message = ("{0}: Finished updating `$data. The value update is {1}." -f (Get-Date -Format s), $data)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"
    
    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}
    
    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the {1} function will exit. The specific error message is: {2}" `
                -f (Get-Date -Format s), $MyInvocation.MyCommand, $_.Message.Exception)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
        
        Return "Error"
    }
    
    If ($response.status -ne "200") {
        $message = ("{0}: LogicMonitor reported an error (status {1}). The message is: {2}" -f (Get-Date -Format s), $response.status, $response.errmsg)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -Message $message -EventId 5417}
    }

    Return $response
} #1.0.0.1
